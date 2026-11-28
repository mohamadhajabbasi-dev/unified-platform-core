#!/usr/bin/env bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]]
: "$PG_CONTAINER"
psql_ci() { timeout 60s docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
holder=''
cleanup() { if [[ -n "$holder" ]]; then kill -KILL "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true; fi; rm -rf "$tmp"; }
trap cleanup EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
for migration in db/migrations/*.sql; do
 [[ "$migration" == db/migrations/0106_outbox_worker_recovery.sql ]] && break
 psql_ci < "$migration"
done
psql_ci < db/tests/0105_outbox_retry_backoff.sql
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1060000-0000-0000-0000-000000000003','worker-a','Synthetic A'),
 ('a1060000-0000-0000-0000-000000000004','worker-b','Synthetic B'),
 ('a1060000-0000-0000-0000-000000000005','worker-c','Synthetic C');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1060000-0000-0000-0000-000000000003','d1060000-0000-0000-0000-000000000005','Synthetic A'),
 ('a1060000-0000-0000-0000-000000000004','d1060000-0000-0000-0000-000000000006','Synthetic B'),
 ('a1060000-0000-0000-0000-000000000005','d1060000-0000-0000-0000-000000000007','Synthetic C1'),
 ('a1060000-0000-0000-0000-000000000005','d1060000-0000-0000-0000-000000000008','Synthetic C2'),
 ('a1060000-0000-0000-0000-000000000005','d1060000-0000-0000-0000-000000000009','Synthetic C3');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1060000-0000-0000-0000-000000000003','c1060000-0000-0000-0000-000000000003','one'),
 ('a1060000-0000-0000-0000-000000000003','c1060000-0000-0000-0000-000000000006','two'),
 ('a1060000-0000-0000-0000-000000000004','c1060000-0000-0000-0000-000000000004','one'),
 ('a1060000-0000-0000-0000-000000000004','c1060000-0000-0000-0000-000000000006','two'),
 ('a1060000-0000-0000-0000-000000000005','c1060000-0000-0000-0000-000000000005','one');
SQL
a='a1060000-0000-0000-0000-000000000003'; ca='c1060000-0000-0000-0000-000000000003'
b='a1060000-0000-0000-0000-000000000004'; cb='c1060000-0000-0000-0000-000000000004'
c='a1060000-0000-0000-0000-000000000005'; cc='c1060000-0000-0000-0000-000000000005'
other='c1060000-0000-0000-0000-000000000006'
ea=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$a'")
eb=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$b'")
ec1=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$c' ORDER BY recorded_at,event_id LIMIT 1")
ec2=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$c' ORDER BY recorded_at,event_id LIMIT 1 OFFSET 1")
ec3=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$c' ORDER BY recorded_at,event_id LIMIT 1 OFFSET 2")
for e in "$ea" "$eb" "$ec1" "$ec2" "$ec3"; do [[ "$e" =~ ^[0-9a-f-]{36}$ ]]; done
old=$(psql_ci -c "SELECT ops.claim_synthetic_outbox_event('$c','$cc','$ec1',300)")
[[ "$old" =~ ^[0-9a-f-]{36}$ ]]
[[ "$(psql_ci -c "SELECT ops.fail_synthetic_outbox_claim('$c','$cc','$ec1','$old',300)")" == t ]]
[[ "$(psql_ci -c "SELECT ops.record_synthetic_outbox_receipt('$c','$cc','$ec3')")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND NOT(n.nspname='ops' AND p.proname='ready_synthetic_outbox_events')
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0106_outbox_worker_recovery.sql
psql_ci < db/tests/0106_outbox_worker_recovery.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
echo 'PASS committed pre-0106 upgrade: prior rows including claims and receipts, functions, ACL and RLS unchanged'
worker() { bash db/tests/workers/outbox_synthetic_worker.sh "$@"; }
events() { psql_ci -c "SELECT to_jsonb(e) FROM ops.outbox_events e ORDER BY tenant_id,event_id"; }
events > "$tmp/events_before"
[[ "$(psql_ci -c "SELECT event_id FROM ops.pending_outbox_events('$c','$cc',1)")" == "$ec1" ]]
[[ "$(psql_ci -c "SELECT event_id FROM ops.ready_synthetic_outbox_events('$c','$cc',1)")" == "$ec2" ]]
# Real process termination after its committed claim. Launch bash directly so $! is the worker PID.
bash db/tests/workers/outbox_synthetic_worker.sh "$a" "$ca" hold 20 > "$tmp/holder" 2>&1 &
holder=$!
ready=0
for i in {1..100}; do
 if grep -q '^CLAIM ' "$tmp/holder"; then ready=1; break; fi
 kill -0 "$holder"; sleep 0.1
done
[[ "$ready" == 1 ]]
read -r label event token count < "$tmp/holder"
[[ "$label" == CLAIM && "$event" == "$ea" && "$token" =~ ^[0-9a-f-]{36}$ && "$count" == 1 ]]
where="tenant_id='$a' AND consumer_id='$ca' AND event_id='$ea'"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND lease_token='$token' AND expires_at>clock_timestamp()")" == 1 ]]
# Wait for the direct worker to exec sleep, avoiding a child-process race.
sleep 0.2
kill -KILL "$holder"
set +e
wait "$holder" 2>/dev/null
rc=$?
set -e
holder=''
[[ "$rc" == 137 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 0 ]]
[[ "$(worker "$a" "$ca" complete 120)" == EMPTY ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND lease_token='$token' AND expires_at>clock_timestamp()")" == 1 ]]
worker "$a" "$other" complete 120 > "$tmp/independent-consumer"
grep -qx "DONE $ea" "$tmp/independent-consumer"
worker "$b" "$cb" complete 120 > "$tmp/independent-tenant"
grep -qx "DONE $eb" "$tmp/independent-tenant"
expired=0
for i in {1..120}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND expires_at<=clock_timestamp()")" == 1 ]]; then expired=1; break; fi
 sleep 0.25
done
[[ "$expired" == 1 ]]
[[ "$(psql_ci -c "SELECT ops.complete_synthetic_outbox_claim('$a','$ca','$ea','$token')")" == f ]]
worker "$a" "$ca" complete 120 > "$tmp/restarted"
read -r label event newtoken count < "$tmp/restarted"
[[ "$label" == CLAIM && "$event" == "$ea" && "$newtoken" =~ ^[0-9a-f-]{36}$ && "$newtoken" != "$token" && "$count" == 2 ]]
grep -qx "DONE $ea" "$tmp/restarted"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where")" == 0 ]]
[[ "$(worker "$a" "$ca" complete 120)" == EMPTY ]]
echo 'PASS real worker process killed after committed claim, early restart excluded, actual expiry, fresh fence and one receipt; independent scopes progress'
# Two actual worker processes contend for the only eligible event behind the cooling head.
worker "$c" "$cc" complete 120 > "$tmp/race1" & p1=$!
worker "$c" "$cc" complete 120 > "$tmp/race2" & p2=$!
wait "$p1"; wait "$p2"
[[ "$(grep -hxc "DONE $ec2" "$tmp/race1" "$tmp/race2" | awk '{s+=$1} END{print s}')" == 1 ]]
[[ "$(grep -hxc EMPTY "$tmp/race1" "$tmp/race2" | awk '{s+=$1} END{print s}')" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id='$c' AND consumer_id='$cc' AND event_id='$ec2'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id='$c' AND consumer_id='$cc' AND event_id='$ec1'")" == 0 ]]
# Explicit worker failure and actual database-clock cooldown, without fixture timestamp modification.
worker "$b" "$other" fail 120 > "$tmp/failure"
read -r label event failedtoken count < "$tmp/failure"
[[ "$label" == CLAIM && "$event" == "$eb" && "$count" == 1 ]]
grep -qx "FAILED $eb" "$tmp/failure"
[[ "$(worker "$b" "$other" complete 120)" == EMPTY ]]
whereb="tenant_id='$b' AND consumer_id='$other' AND event_id='$eb'"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $whereb")" == 0 ]]
eligible=0
for i in {1..80}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $whereb AND retry_not_before<=clock_timestamp()")" == 1 ]]; then eligible=1; break; fi
 sleep 0.25
done
[[ "$eligible" == 1 ]]
worker "$b" "$other" complete 120 > "$tmp/retry"
read -r label event newtoken count < "$tmp/retry"
[[ "$label" == CLAIM && "$event" == "$eb" && "$newtoken" != "$failedtoken" && "$count" == 2 ]]
grep -qx "DONE $eb" "$tmp/retry"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $whereb")" == 1 ]]
events > "$tmp/events_after"
cmp "$tmp/events_before" "$tmp/events_after"
echo 'PASS two worker processes converge to one receipt; explicit failure/cooldown/retry across processes; canonical events unchanged'

#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0104_outbox_claim_lease.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND (schemaname,tablename)<>('ops','outbox_claims') ORDER BY schemaname,tablename
\gexec
SELECT tenant_id,consumer_id,event_id,lease_token,expires_at FROM ops.outbox_claims ORDER BY tenant_id,consumer_id,event_id;
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND NOT(n.nspname='ops' AND p.proname IN ('claim_synthetic_outbox_event','complete_synthetic_outbox_claim','fail_synthetic_outbox_claim'))
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT p.oid,p.proname,p.proowner,p.proacl,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='ops' AND p.proname IN ('claim_synthetic_outbox_event','complete_synthetic_outbox_claim') ORDER BY p.proname;
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
[[ "$(psql_ci -c 'SELECT count(*) FROM ops.outbox_claims')" -gt 0 ]]
psql_ci < db/migrations/0105_outbox_retry_backoff.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c 'SELECT count(*) FROM ops.outbox_claims WHERE attempt_count<>1 OR retry_not_before IS NOT NULL')" == 0 ]]
psql_ci < db/tests/0104_outbox_claim_lease.sql
psql_ci < db/tests/0105_outbox_retry_backoff.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0105 upgrade: previous claim columns, rows, function ownership/ACL, other definitions and RLS preserved; existing claims initialized to lower bound one'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1050000-0000-0000-0000-000000000003','retry-race-a','Synthetic A'),
 ('a1050000-0000-0000-0000-000000000004','retry-race-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1050000-0000-0000-0000-000000000003','d1050000-0000-0000-0000-000000000003','Synthetic A1'),
 ('a1050000-0000-0000-0000-000000000003','d1050000-0000-0000-0000-000000000004','Synthetic A2'),
 ('a1050000-0000-0000-0000-000000000003','d1050000-0000-0000-0000-000000000005','Synthetic A3'),
 ('a1050000-0000-0000-0000-000000000004','d1050000-0000-0000-0000-000000000006','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1050000-0000-0000-0000-000000000003','c1050000-0000-0000-0000-000000000003','one'),
 ('a1050000-0000-0000-0000-000000000003','c1050000-0000-0000-0000-000000000004','two'),
 ('a1050000-0000-0000-0000-000000000004','c1050000-0000-0000-0000-000000000003','one');
SQL
a='a1050000-0000-0000-0000-000000000003'
b='a1050000-0000-0000-0000-000000000004'
c='c1050000-0000-0000-0000-000000000003'
c2='c1050000-0000-0000-0000-000000000004'
eb=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$b'")
[[ "$eb" =~ ^[0-9a-f-]{36}$ ]]
psql_ci -c "SELECT to_jsonb(e) FROM ops.outbox_events e ORDER BY tenant_id,event_id" > "$tmp/events_before"
for mode in rollback-fail commit-fail commit-complete; do
 case "$mode" in rollback-fail) offset=0; outcome=ROLLBACK;; commit-fail) offset=1; outcome=COMMIT;; commit-complete) offset=2; outcome=COMMIT;; esac
 e=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$a' ORDER BY event_id LIMIT 1 OFFSET $offset")
 [[ "$e" =~ ^[0-9a-f-]{36}$ ]]
 token=$(psql_ci -c "SELECT ops.claim_synthetic_outbox_event('$a','$c','$e',120)")
 [[ "$token" =~ ^[0-9a-f-]{36}$ ]]
 where="tenant_id='$a' AND consumer_id='$c' AND event_id='$e'"
 fail="SELECT ops.fail_synthetic_outbox_claim('$a','$c','$e','$token',120)"
 complete="SELECT ops.complete_synthetic_outbox_claim('$a','$c','$e','$token')"
 if [[ "$mode" == commit-complete ]]; then first_call="$complete"; second_call="$fail"; else first_call="$fail"; second_call="$complete"; fi
 psql_ci > "$tmp/first-$mode" 2>&1 <<SQL &
SET application_name='upc_retry_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$first_call;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_retry_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND lease_token='$token' AND retry_not_before IS NULL AND attempt_count=1")" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 0 ]]
 psql_ci > "$tmp/second-$mode" 2>&1 <<SQL &
SET application_name='upc_retry_second';
SET statement_timeout='40s';
$second_call;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_retry_second' AND b.application_name='upc_retry_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 [[ "$(psql_ci -c "SET statement_timeout='3s'; SELECT ops.claim_synthetic_outbox_event('$a','$c2','$e',120) IS NOT NULL")" == t ]]
 if [[ "$mode" == rollback-fail ]]; then
  [[ "$(psql_ci -c "SET statement_timeout='3s'; SELECT ops.claim_synthetic_outbox_event('$b','$c','$eb',120) IS NOT NULL")" == t ]]
 fi
 wait "$first"; wait "$second"
 grep -qx t "$tmp/first-$mode"
 if [[ "$mode" == rollback-fail ]]; then grep -qx t "$tmp/second-$mode"; else grep -qx f "$tmp/second-$mode"; fi
 if [[ "$mode" == commit-fail ]]; then
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 0 ]]
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND lease_token<>'$token' AND retry_not_before>clock_timestamp() AND attempt_count=1")" == 1 ]]
  saved=$(psql_ci -c "SELECT to_jsonb(l) FROM ops.outbox_claims l WHERE $where")
  [[ "$(psql_ci -c "$fail")" == f ]]
  [[ "$(psql_ci -c "SELECT ops.claim_synthetic_outbox_event('$a','$c','$e',120) IS NULL")" == t ]]
  [[ "$(psql_ci -c "SELECT to_jsonb(l) FROM ops.outbox_claims l WHERE $where")" == "$saved" ]]
  # Advance only the synthetic fixture to the eligible time; elapsed cooldown also covered in SQL acceptance.
  psql_ci -c "UPDATE ops.outbox_claims SET retry_not_before=expires_at WHERE $where"
  newtoken=$(psql_ci -c "SELECT ops.claim_synthetic_outbox_event('$a','$c','$e',120)")
  [[ "$newtoken" =~ ^[0-9a-f-]{36}$ && "$newtoken" != "$token" ]]
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where AND attempt_count=2 AND retry_not_before IS NULL")" == 1 ]]
  [[ "$(psql_ci -c "$complete")" == f ]]
  [[ "$(psql_ci -c "SELECT ops.complete_synthetic_outbox_claim('$a','$c','$e','$newtoken')")" == t ]]
 fi
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where")" == 0 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 1 ]]
done
psql_ci -c "SELECT to_jsonb(e) FROM ops.outbox_events e ORDER BY tenant_id,event_id" > "$tmp/events_after"
cmp "$tmp/events_before" "$tmp/events_after"
echo 'PASS concurrent outbox failure and completion: observed blockers, rollback/commit in both directions, committed cooldown, reclaim count, independent scope and one receipt'

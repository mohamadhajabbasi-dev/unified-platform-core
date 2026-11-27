#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0095_outbox_pending_enumeration.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND (n.nspname,p.proname)<>('ops','record_synthetic_outbox_receipt') ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0096_outbox_idempotent_receipt.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0096_outbox_idempotent_receipt.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0096 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0960000-0000-0000-0000-000000000003','receipt-race','Synthetic race');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES('a0960000-0000-0000-0000-000000000003','c0960000-0000-0000-0000-000000000003','race');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES('a0960000-0000-0000-0000-000000000003','d0960000-0000-0000-0000-000000000003','Synthetic race');
SQL
event=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='a0960000-0000-0000-0000-000000000003'")
[[ "$event" =~ ^[0-9a-f-]{36}$ ]]
call="SELECT ops.record_synthetic_outbox_receipt('a0960000-0000-0000-0000-000000000003','c0960000-0000-0000-0000-000000000003','$event')"
for outcome in ROLLBACK COMMIT; do
 psql_ci > "$tmp/first-$outcome" 2>&1 <<SQL &
SET application_name='upc_receipt_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$call;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_receipt_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE event_id='$event'")" == 0 ]]
 psql_ci > "$tmp/second-$outcome" 2>&1 <<SQL &
SET application_name='upc_receipt_second';
SET statement_timeout='40s';
$call;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_receipt_second' AND b.application_name='upc_receipt_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 wait "$first"
 wait "$second"
 grep -qx t "$tmp/first-$outcome"
 if [[ "$outcome" == ROLLBACK ]]; then
  grep -qx t "$tmp/second-$outcome"
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE event_id='$event'")" == 1 ]]
  # Reset only the synthetic fixture for the distinct commit race.
  psql_ci -c "DELETE FROM ops.outbox_consumer_receipts WHERE event_id='$event'"
 else
  grep -qx f "$tmp/second-$outcome"
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE event_id='$event'")" == 1 ]]
 fi
done
stamp=$(psql_ci -c "SELECT recorded_at FROM ops.outbox_consumer_receipts WHERE event_id='$event'")
[[ "$(psql_ci -c "$call")" == f ]]
[[ "$(psql_ci -c "SELECT recorded_at FROM ops.outbox_consumer_receipts WHERE event_id='$event'")" == "$stamp" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.pending_outbox_events('a0960000-0000-0000-0000-000000000003','c0960000-0000-0000-0000-000000000003',500)")" == 0 ]]
echo 'PASS concurrent synthetic receipt: actual blocker in rollback and commit races, one receipt, exact replay and unchanged timestamp'

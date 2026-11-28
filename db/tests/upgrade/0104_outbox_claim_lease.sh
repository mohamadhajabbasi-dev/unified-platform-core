#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0103_dormant_workflow_definition.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND (schemaname,tablename)<>('ops','outbox_claims') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND NOT(n.nspname='ops' AND p.proname IN ('claim_synthetic_outbox_event','complete_synthetic_outbox_claim'))
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' AND (n.nspname,c.relname)<>('ops','outbox_claims') ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0104_outbox_claim_lease.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0104_outbox_claim_lease.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0104 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1040000-0000-0000-0000-000000000003','claim-race-a','Synthetic A'),
 ('a1040000-0000-0000-0000-000000000004','claim-race-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1040000-0000-0000-0000-000000000003','d1040000-0000-0000-0000-000000000003','Synthetic A1'),
 ('a1040000-0000-0000-0000-000000000003','d1040000-0000-0000-0000-000000000004','Synthetic A2'),
 ('a1040000-0000-0000-0000-000000000004','d1040000-0000-0000-0000-000000000005','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1040000-0000-0000-0000-000000000003','c1040000-0000-0000-0000-000000000003','one'),
 ('a1040000-0000-0000-0000-000000000003','c1040000-0000-0000-0000-000000000004','two'),
 ('a1040000-0000-0000-0000-000000000004','c1040000-0000-0000-0000-000000000003','one');
SQL
a='a1040000-0000-0000-0000-000000000003'
b='a1040000-0000-0000-0000-000000000004'
c='c1040000-0000-0000-0000-000000000003'
c2='c1040000-0000-0000-0000-000000000004'
eb=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$b'")
[[ "$eb" =~ ^[0-9a-f-]{36}$ ]]
psql_ci -c "SELECT to_jsonb(e) FROM ops.outbox_events e ORDER BY tenant_id,event_id" > "$tmp/events_before"
for outcome in ROLLBACK COMMIT; do
 if [[ "$outcome" == ROLLBACK ]]; then offset=0; else offset=1; fi
 e=$(psql_ci -c "SELECT event_id FROM ops.outbox_events WHERE tenant_id='$a' ORDER BY event_id LIMIT 1 OFFSET $offset")
 [[ "$e" =~ ^[0-9a-f-]{36}$ ]]
 claim="SELECT ops.claim_synthetic_outbox_event('$a','$c','$e',120) IS NOT NULL"
 where="tenant_id='$a' AND consumer_id='$c' AND event_id='$e'"
 for phase in claim complete; do
  if [[ "$phase" == claim ]]; then
   call="$claim"
  else
   token=$(psql_ci -c "SELECT lease_token FROM ops.outbox_claims WHERE $where")
   [[ "$token" =~ ^[0-9a-f-]{36}$ ]]
   call="SELECT ops.complete_synthetic_outbox_claim('$a','$c','$e','$token')"
  fi
  psql_ci > "$tmp/first-$outcome-$phase" 2>&1 <<SQL &
SET application_name='upc_claim_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$call;
SELECT pg_sleep(12);
$outcome;
SQL
  first=$!
  ready=0
  for i in {1..50}; do
   if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_claim_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
   sleep 0.1
  done
  [[ "$ready" == 1 ]]
  [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 0 ]]
  if [[ "$phase" == claim ]]; then
   [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where")" == 0 ]]
  fi
  psql_ci > "$tmp/second-$outcome-$phase" 2>&1 <<SQL &
SET application_name='upc_claim_second';
SET statement_timeout='40s';
$call;
SQL
  second=$!
  blocked=0
  for i in {1..50}; do
   if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_claim_second' AND b.application_name='upc_claim_first'")" == 1 ]]; then blocked=1; break; fi
   sleep 0.1
  done
  [[ "$blocked" == 1 ]]
  if [[ "$phase" == claim ]]; then
   [[ "$(psql_ci -c "SET statement_timeout='3s'; SELECT ops.claim_synthetic_outbox_event('$a','$c2','$e',120) IS NOT NULL")" == t ]]
   if [[ "$outcome" == ROLLBACK ]]; then
    [[ "$(psql_ci -c "SET statement_timeout='3s'; SELECT ops.claim_synthetic_outbox_event('$b','$c','$eb',120) IS NOT NULL")" == t ]]
   fi
  fi
  wait "$first"
  wait "$second"
  grep -qx t "$tmp/first-$outcome-$phase"
  if [[ "$outcome" == ROLLBACK ]]; then grep -qx t "$tmp/second-$outcome-$phase"; else grep -qx f "$tmp/second-$outcome-$phase"; fi
  if [[ "$phase" == claim ]]; then
   [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where")" == 1 ]]
  else
   [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_claims WHERE $where")" == 0 ]]
   [[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE $where")" == 1 ]]
   [[ "$(psql_ci -c "$call")" == f ]]
   [[ "$(psql_ci -c "$claim")" == f ]]
  fi
 done
done
psql_ci -c "SELECT to_jsonb(e) FROM ops.outbox_events e ORDER BY tenant_id,event_id" > "$tmp/events_after"
cmp "$tmp/events_before" "$tmp/events_after"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id='$a' AND consumer_id='$c'")" == 2 ]]
echo 'PASS concurrent outbox claim and completion: observed blockers, commit/rollback, independent scope, exact one receipt per tuple, unchanged canonical events'

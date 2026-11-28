#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0097_inbox_idempotent_identity.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND (n.nspname,p.proname)<>('ops','record_synthetic_external_variant_mapping') ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0098_external_variant_identity.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0098_external_variant_identity.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0098 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0980000-0000-0000-0000-000000000001','map-test-a','Synthetic A'),
 ('a0980000-0000-0000-0000-000000000002','map-test-b','Synthetic B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0980000-0000-0000-0000-000000000001','d0980000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0980000-0000-0000-0000-000000000002','d0980000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0980000-0000-0000-0000-000000000001','e0980000-0000-0000-0000-000000000001','d0980000-0000-0000-0000-000000000001','map-1','Synthetic'),
 ('a0980000-0000-0000-0000-000000000001','e0980000-0000-0000-0000-000000000002','d0980000-0000-0000-0000-000000000001','map-2','Synthetic'),
 ('a0980000-0000-0000-0000-000000000002','e0980000-0000-0000-0000-000000000003','d0980000-0000-0000-0000-000000000002','map-1','Synthetic');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a0980000-0000-0000-0000-000000000001','c0980000-0000-0000-0000-000000000001','one','synthetic'),
 ('a0980000-0000-0000-0000-000000000001','c0980000-0000-0000-0000-000000000002','two','synthetic'),
 ('a0980000-0000-0000-0000-000000000002','c0980000-0000-0000-0000-000000000003','one','synthetic');
SQL
a='a0980000-0000-0000-0000-000000000001'
c='c0980000-0000-0000-0000-000000000001'
v1='e0980000-0000-0000-0000-000000000001'
v2='e0980000-0000-0000-0000-000000000002'
before_events=$(psql_ci -c "SELECT count(*) FROM ops.outbox_events WHERE tenant_id='$a'")
for scenario in rollback conflict replay; do
 case "$scenario" in
 rollback) outcome=ROLLBACK; ext='f0980000-0000-0000-0000-000000000011'; target="$v2"; expected="$v2";;
 conflict) outcome=COMMIT; ext='f0980000-0000-0000-0000-000000000012'; target="$v2"; expected="$v1";;
 replay) outcome=COMMIT; ext='f0980000-0000-0000-0000-000000000013'; target="$v1"; expected="$v1";;
 esac
 where="tenant_id='$a' AND connection_id='$c' AND external_variant_id='$ext'"
 call_first="SELECT ops.record_synthetic_external_variant_mapping('$a','$c','$ext','$v1')"
 call_second="SELECT ops.record_synthetic_external_variant_mapping('$a','$c','$ext','$target')"
 psql_ci > "$tmp/first-$scenario" 2>&1 <<SQL &
SET application_name='upc_mapping_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$call_first;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_mapping_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings WHERE $where")" == 0 ]]
 psql_ci > "$tmp/second-$scenario" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_mapping_second';
SET statement_timeout='40s';
$call_second;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_mapping_second' AND b.application_name='upc_mapping_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 wait "$first"
 grep -qx t "$tmp/first-$scenario"
 if [[ "$scenario" == conflict ]]; then
  if wait "$second"; then echo 'FAIL conflicting target accepted'; exit 1; fi
  grep -q '23505: Conflicting canonical variant' "$tmp/second-$scenario"
 else
  wait "$second"
  if [[ "$scenario" == rollback ]]; then grep -qx t "$tmp/second-$scenario"; else grep -qx f "$tmp/second-$scenario"; fi
 fi
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings WHERE $where")" == 1 ]]
 [[ "$(psql_ci -c "SELECT variant_id FROM ops.external_variant_mappings WHERE $where")" == "$expected" ]]
 stamp=$(psql_ci -c "SELECT recorded_at FROM ops.external_variant_mappings WHERE $where")
 [[ "$(psql_ci -c "SELECT ops.record_synthetic_external_variant_mapping('$a','$c','$ext','$expected')")" == f ]]
 [[ "$(psql_ci -c "SELECT recorded_at FROM ops.external_variant_mappings WHERE $where")" == "$stamp" ]]
done
[[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings WHERE tenant_id='$a'")" == 3 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM catalog.variants WHERE tenant_id='$a'")" == 2 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_events WHERE tenant_id='$a'")" == "$before_events" ]]
echo 'PASS concurrent synthetic external mapping: actual blockers in rollback, conflicting commit and replay races; original target and timestamp retained; no catalog or outbox effect'

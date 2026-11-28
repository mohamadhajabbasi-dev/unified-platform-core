#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0098_external_variant_identity.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND (schemaname,tablename)<>('iam','security_policies') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' AND (n.nspname,c.relname)<>('iam','security_policies') ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0099_dormant_security_policy.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0099_dormant_security_policy.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0099 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0990000-0000-0000-0000-000000000001','security-test-a','Synthetic A'),
 ('a0990000-0000-0000-0000-000000000002','security-test-b','Synthetic B');
SQL
a='a0990000-0000-0000-0000-000000000001'
b='a0990000-0000-0000-0000-000000000002'
for scenario in rollback commit; do
 if [[ "$scenario" == rollback ]]; then outcome=ROLLBACK; network='198.51.100.0/24'; else outcome=COMMIT; network='203.0.113.0/24'; fi
 where="tenant_id='$a' AND source_network='$network'::cidr"
 insert="INSERT INTO iam.security_policies(tenant_id,source_network) VALUES('$a','$network') RETURNING policy_id"
 psql_ci > "$tmp/first-$scenario" 2>&1 <<SQL &
SET application_name='upc_security_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$insert;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_security_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM iam.security_policies WHERE $where")" == 0 ]]
 psql_ci > "$tmp/second-$scenario" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_security_second';
SET statement_timeout='40s';
$insert;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_security_second' AND b.application_name='upc_security_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 # The identical selector in another tenant is independent while the first tenant is locked.
 psql_ci -c "SET statement_timeout='3s'; INSERT INTO iam.security_policies(tenant_id,source_network) VALUES('$b','$network')"
 wait "$first"
 if [[ "$scenario" == commit ]]; then
  if wait "$second"; then echo 'FAIL duplicate network accepted'; exit 1; fi
  grep -q '23505:' "$tmp/second-$scenario"
  winner=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first-$scenario")
 else
  wait "$second"
  winner=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second-$scenario")
 fi
 [[ "$(psql_ci -c "SELECT count(*) FROM iam.security_policies WHERE $where")" == 1 ]]
 [[ "$(psql_ci -c "SELECT policy_id FROM iam.security_policies WHERE $where")" == "$winner" ]]
done
[[ "$(psql_ci -c "SELECT count(*) FROM iam.security_policies WHERE tenant_id IN('$a','$b')")" == 4 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.audit_events WHERE tenant_id IN('$a','$b')")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_events WHERE tenant_id IN('$a','$b')")" == 0 ]]
echo 'PASS concurrent dormant security selectors: actual duplicate blockers in commit and rollback, tenant-independent insertion, one winning identity per scope and no runtime side effects'

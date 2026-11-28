#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0099_dormant_security_policy.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND (schemaname,tablename)<>('iam','api_credentials_metadata') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' AND (n.nspname,c.relname)<>('iam','api_credentials_metadata') ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0100_dormant_api_credentials.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0100_dormant_api_credentials.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0100 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1000000-0000-0000-0000-000000000001','credential-test-a','Synthetic A'),
 ('a1000000-0000-0000-0000-000000000002','credential-test-b','Synthetic B');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','one','synthetic'),
 ('a1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','two','synthetic'),
 ('a1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003','one','synthetic');
SQL
a='a1000000-0000-0000-0000-000000000001'
b='a1000000-0000-0000-0000-000000000002'
ca='c1000000-0000-0000-0000-000000000001'
cb='c1000000-0000-0000-0000-000000000003'
for scenario in rollback commit; do
 if [[ "$scenario" == rollback ]]; then outcome=ROLLBACK; vr='e1000000-0000-0000-0000-000000000011'; independent='e1000000-0000-0000-0000-000000000021'; expected="$b"; else outcome=COMMIT; vr='e1000000-0000-0000-0000-000000000012'; independent='e1000000-0000-0000-0000-000000000022'; expected="$a"; fi
 insert_a="INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES('$a','$ca','$vr') RETURNING credential_id"
 insert_b="INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES('$b','$cb','$vr') RETURNING credential_id"
 psql_ci > "$tmp/first-$scenario" 2>&1 <<SQL &
SET application_name='upc_credential_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$insert_a;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_credential_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM iam.api_credentials_metadata WHERE vault_reference_id='$vr'")" == 0 ]]
 psql_ci > "$tmp/second-$scenario" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_credential_second';
SET statement_timeout='40s';
$insert_b;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_credential_second' AND b.application_name='upc_credential_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 psql_ci -c "SET statement_timeout='3s'; INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES('$b','$cb','$independent')"
 wait "$first"
 if [[ "$scenario" == commit ]]; then
  if wait "$second"; then echo 'FAIL reference reuse across tenants'; exit 1; fi
  grep -q '23505:' "$tmp/second-$scenario"
  winner=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first-$scenario")
 else
  wait "$second"
  winner=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second-$scenario")
 fi
 [[ "$(psql_ci -c "SELECT count(*) FROM iam.api_credentials_metadata WHERE vault_reference_id='$vr'")" == 1 ]]
 [[ "$(psql_ci -c "SELECT tenant_id FROM iam.api_credentials_metadata WHERE vault_reference_id='$vr'")" == "$expected" ]]
 [[ "$(psql_ci -c "SELECT credential_id FROM iam.api_credentials_metadata WHERE vault_reference_id='$vr'")" == "$winner" ]]
done
[[ "$(psql_ci -c "SELECT count(*) FROM iam.api_credentials_metadata WHERE tenant_id IN('$a','$b')")" == 4 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.integration_connections WHERE tenant_id IN('$a','$b')")" == 3 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.audit_events WHERE tenant_id IN('$a','$b')")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_events WHERE tenant_id IN('$a','$b')")" == 0 ]]
echo 'PASS concurrent dormant API credential metadata: actual duplicate reference blockers in commit and rollback, independent reference insert, one winning tenant and identity per reference, no domain effects'

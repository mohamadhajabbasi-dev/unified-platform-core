#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0091_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 90 ]]
python3 - "$tmp/details.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0087_catalog_details_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/details.sql"
psql_ci <<'SQL'
INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES('a0870000-0000-0000-0000-000000000001','b0870000-0000-0000-0000-000000000001');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES('a0870000-0000-0000-0000-000000000001','c0910000-0000-0000-0000-000000000099','synthetic-consumer');
INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id)
 SELECT tenant_id,'c0910000-0000-0000-0000-000000000099',event_id FROM ops.outbox_events
 WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY event_id LIMIT 1;
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES('a0870000-0000-0000-0000-000000000001','c0910000-0000-0000-0000-000000000098','synthetic-connection','synthetic-adapter');
INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES('a0870000-0000-0000-0000-000000000001','c0910000-0000-0000-0000-000000000098','d0910000-0000-0000-0000-000000000098');
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM iam.user_auth_sessions)=1 AND (SELECT count(*) FROM ops.outbox_consumer_receipts)=1 AND (SELECT count(*) FROM ops.inbound_inbox)=1 AND (SELECT count(*) FROM catalog.variants WHERE tenant_id='a0870000-0000-0000-0000-000000000001')>=2")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND (schemaname,tablename)<>('ops','external_variant_mappings') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog') AND p.prokind='f' ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog') AND c.relkind='r' AND (n.nspname,c.relname)<>('ops','external_variant_mappings') ORDER BY n.nspname,c.relname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0091_dormant_external_variant_mapping.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings")" == 0 ]]
psql_ci < db/tests/0091_dormant_external_variant_mapping.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0091 upgrade: all prior rows including 0088/0089/0090, IAM/catalog/ops functions and ACLs preserved; no mapping backfill'
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_mapping_first';
BEGIN;
SET LOCAL statement_timeout='30s';
INSERT INTO ops.external_variant_mappings(tenant_id,connection_id,external_variant_id,variant_id)
 SELECT tenant_id,'c0910000-0000-0000-0000-000000000098','f0910000-0000-0000-0000-000000000098',variant_id FROM catalog.variants WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY variant_id LIMIT 1;
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_mapping_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings")" == 0 ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_mapping_second';
SET statement_timeout='30s';
INSERT INTO ops.external_variant_mappings(tenant_id,connection_id,external_variant_id,variant_id)
 SELECT tenant_id,'c0910000-0000-0000-0000-000000000098','f0910000-0000-0000-0000-000000000098',variant_id FROM catalog.variants WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY variant_id DESC LIMIT 1;
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_mapping_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then echo 'FAIL conflicting concurrent mapping accepted'; exit 1; fi
[[ "$blocked" == 1 ]]
grep -q '23505' "$tmp/second"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.external_variant_mappings")" == 1 ]]
[[ "$(psql_ci -c "SELECT m.variant_id=(SELECT variant_id FROM catalog.variants WHERE tenant_id=m.tenant_id ORDER BY variant_id LIMIT 1) FROM ops.external_variant_mappings m")" == t ]]
snapshot > "$tmp/after_race"
cmp "$tmp/before" "$tmp/after_race"
echo 'PASS dormant external mapping concurrency: actual unique-key lock, invisible uncommitted mapping, original canonical target preserved and conflicting target rejected'

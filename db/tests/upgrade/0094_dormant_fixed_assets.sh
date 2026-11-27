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
 [[ "$(basename "$migration")" == 0094_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 93 ]]
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
psql_ci <<'SQL'
INSERT INTO ops.external_variant_mappings(tenant_id,connection_id,external_variant_id,variant_id)
 SELECT tenant_id,'c0910000-0000-0000-0000-000000000098','f0910000-0000-0000-0000-000000000098',variant_id FROM catalog.variants WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY variant_id LIMIT 1;
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM ops.external_variant_mappings)=1 AND EXISTS(SELECT 1 FROM inventory.warehouses WHERE tenant_id='a0870000-0000-0000-0000-000000000001')")" == t ]]
psql_ci <<'SQL'
INSERT INTO procurement.procurement_requests(tenant_id,request_id,request_key,warehouse_id)
 SELECT tenant_id,'f0920000-0000-0000-0000-000000000098','f0920000-0000-0000-0000-000000000099',warehouse_id FROM inventory.warehouses WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY warehouse_id LIMIT 1;
INSERT INTO procurement.procurement_request_items(tenant_id,request_id,variant_id,requested_units)
 SELECT tenant_id,'f0920000-0000-0000-0000-000000000098',variant_id,5 FROM catalog.variants WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY variant_id LIMIT 1;
-- Synthetic committed historical request; not actual backup.
INSERT INTO ops.tenant_backup_jobs(tenant_id,job_id,request_key,requested_by) VALUES('a0870000-0000-0000-0000-000000000001','d0930000-0000-0000-0000-000000000098','d0930000-0000-0000-0000-000000000099','b0870000-0000-0000-0000-000000000001');
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM procurement.procurement_request_items)=1 AND (SELECT count(*) FROM ops.tenant_backup_jobs)=1")" == t ]]
psql_ci <<'SQL'
INSERT INTO ops.backup_snapshots(tenant_id,snapshot_id,job_id) VALUES('a0870000-0000-0000-0000-000000000001','e0930000-0000-0000-0000-000000000098','d0930000-0000-0000-0000-000000000098');
INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES('a0870000-0000-0000-0000-000000000001','f0930000-0000-0000-0000-000000000098','e0930000-0000-0000-0000-000000000098');
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM ops.backup_snapshots)=1 AND (SELECT count(*) FROM ops.restore_requests)=1")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND (schemaname,tablename)<>('inventory','stock_assets') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f' ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r'
 AND (n.nspname,c.relname)<>('inventory','stock_assets') ORDER BY n.nspname,c.relname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0094_dormant_fixed_assets.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_assets")" == 0 ]]
psql_ci < db/tests/0094_dormant_fixed_assets.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0094 upgrade: all prior rows including 0088-0093, functions and ACLs preserved; no fixed asset backfill'
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_asset_first';
BEGIN;
SET LOCAL statement_timeout='30s';
INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES('a0870000-0000-0000-0000-000000000001','equipment-race','Original synthetic equipment');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_asset_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_assets")" == 0 ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_asset_second';
SET statement_timeout='30s';
INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES('a0870000-0000-0000-0000-000000000001','equipment-race','Conflicting synthetic equipment');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_asset_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then echo 'FAIL conflicting concurrent asset accepted'; exit 1; fi
[[ "$blocked" == 1 ]]
grep -q '23505' "$tmp/second"
[[ "$(psql_ci -c "SELECT count(*)=1 AND min(display_name)='Original synthetic equipment' FROM inventory.stock_assets")" == t ]]
snapshot > "$tmp/after_race"
cmp "$tmp/before" "$tmp/after_race"
echo 'PASS dormant fixed asset concurrency: actual unique-key lock, invisible uncommitted asset, original identity preserved and competing duplicate rejected'

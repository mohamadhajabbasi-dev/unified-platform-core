#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?isolated CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0068_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 67 ]]
python3 - "$tmp/legacy.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0022_procurement.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
assert lines[-1].startswith(r'\echo PASS procurement:')
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/legacy.sql"
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_inv_a;
SELECT inventory.reserve_stock('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',1,'reorder-upgrade-held',clock_timestamp()+interval '1 day');
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM inventory.stock_ledger)>0 AND (SELECT count(*) FROM inventory.reservations)>0 AND (SELECT count(*) FROM procurement.purchase_orders)>0")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',
 schemaname||'.'||tablename,schemaname,tablename,
 CASE WHEN schemaname='ops' AND tablename='audit_events'
 THEN ' WHERE entity_type<>''inventory.reorder_policies'''
 WHEN schemaname='iam' AND tablename IN ('permissions','role_grants')
 THEN ' WHERE permission_key<>''inventory.reorder.write'''
 ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')
 AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='inventory' AND tablename='reorder_policies')
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0068_reorder_policy_config.sql
snapshot > "$tmp/after_migration"
cmp "$tmp/before" "$tmp/after_migration"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM inventory.reorder_policies) AND NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='inventory.reorder_policies') AND NOT EXISTS(SELECT 1 FROM iam.role_grants WHERE permission_key='inventory.reorder.write')")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants
 SELECT r.tenant_id,r.role_id,'inventory.reorder.write'
 FROM iam.roles r WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor';
SET SESSION AUTHORIZATION upc_inv_a;
SELECT inventory.set_reorder_policy('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',5,12);
SELECT inventory.set_reorder_policy('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',5,12);
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_writes"
cmp "$tmp/before" "$tmp/after_writes"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(reorder_point=5 AND suggested_units=12) FROM inventory.reorder_policies")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='inventory.reorder_policies'")" == t ]]
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM inventory.stock_ledger)=2 AND (SELECT count(*) FROM procurement.receipt_items)=2 AND (SELECT count(*) FROM inventory.reservations)>0")" == t ]]
echo 'PASS committed pre-0068 reorder upgrade: exact prior stock, reservations, purchasing, permissions, and catalog facts; no backfill or automatic procurement'

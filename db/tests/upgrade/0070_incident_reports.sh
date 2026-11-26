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
 [[ "$(basename "$migration")" == 0070_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 69 ]]
python3 - "$tmp/legacy.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0006_sales.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
assert lines[-1].startswith(r'\echo PASS sales:')
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/legacy.sql"
psql_ci <<'SQL'
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic reenable' FROM platform.modules WHERE module_key='sales';
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM sales.orders)>0 AND (SELECT count(*) FROM sales.payments)>0 AND (SELECT count(*) FROM inventory.stock_ledger)>0")" == t ]]
python3 - "$tmp/legacy_shipping.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0069_shipping_methods.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
assert lines[-1].startswith(r'\echo PASS dormant shipping methods:')
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/legacy_shipping.sql"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM sales.shipping_methods)=2 AND (SELECT count(*) FROM ops.audit_events WHERE entity_type='sales.shipping_methods')=2")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',
 schemaname||'.'||tablename,schemaname,tablename,
 CASE WHEN schemaname='ops' AND tablename='audit_events'
 THEN ' WHERE entity_type<>''ops.incidents'''
 WHEN schemaname='iam' AND tablename IN ('permissions','role_grants')
 THEN ' WHERE permission_key NOT IN (''ops.incidents.read'',''ops.incidents.write'')'
 ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')
 AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='ops' AND tablename='incidents')
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0070_incident_reports.sql
snapshot > "$tmp/after_migration"
cmp "$tmp/before" "$tmp/after_migration"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM ops.incidents) AND NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='ops.incidents') AND NOT EXISTS(SELECT 1 FROM iam.role_grants WHERE permission_key IN ('ops.incidents.read','ops.incidents.write'))")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants
 SELECT r.tenant_id,r.role_id,p.permission_key
 FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('ops.incidents.read','ops.incidents.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability');
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability');
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_writes"
cmp "$tmp/before" "$tmp/after_writes"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(report_key='d0700000-0000-0000-0000-000000000001' AND report_kind='availability') FROM ops.incidents")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='ops.incidents'")" == t ]]
echo 'PASS committed pre-0070 incident upgrade: exact prior orders, stock, shipping metadata, audit and all prior table rows; no backfill or activation'

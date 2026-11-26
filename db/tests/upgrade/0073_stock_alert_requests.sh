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
 [[ "$(basename "$migration")" == 0073_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 72 ]]
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
python3 - "$tmp/legacy_incident.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0070_incident_reports.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
assert lines[-1].startswith(r'\echo PASS incident report metadata:')
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/legacy_incident.sql"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM ops.incidents)=2 AND (SELECT count(*) FROM ops.audit_events WHERE entity_type='ops.incidents')=2")" == t ]]
psql_ci <<'SQL'
CREATE ROLE upc_backup_upgrade LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_backup_upgrade;
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0710000-0000-0000-0000-000000000001','test','backup-upgrade');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES('upc_backup_upgrade','b0710000-0000-0000-0000-000000000001',true);
SQL
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_backup_upgrade;
SELECT ops.request_tenant_backup('90000000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000001');
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic reenable' FROM platform.modules WHERE module_key IN ('crm','catalog');
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.tenant_backup_jobs")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('catalog.favorites.read','catalog.favorites.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT catalog.set_product_favorite('95000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001',true);
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic inventory reenable' FROM platform.modules WHERE module_key='inventory';
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM catalog.product_favorites")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',
 schemaname||'.'||tablename,schemaname,tablename,
 CASE WHEN schemaname='ops' AND tablename='audit_events' THEN ' WHERE entity_type<>''catalog.stock_alert_subscriptions'''
 WHEN schemaname='iam' AND tablename IN ('permissions','role_grants') THEN ' WHERE permission_key NOT IN (''catalog.stock_alerts.read'',''catalog.stock_alerts.write'')'
 ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='catalog' AND tablename='stock_alert_subscriptions')
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0073_stock_alert_requests.sql
snapshot > "$tmp/after_migration"
cmp "$tmp/before" "$tmp/after_migration"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) AND NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions') AND NOT EXISTS(SELECT 1 FROM iam.role_grants WHERE permission_key IN ('catalog.stock_alerts.read','catalog.stock_alerts.write'))")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('catalog.stock_alerts.read','catalog.stock_alerts.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT catalog.set_stock_alert_request('95000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',true);
SELECT catalog.set_stock_alert_request('95000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',true);
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_writes"
cmp "$tmp/before" "$tmp/after_writes"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(is_requested) FROM catalog.stock_alert_subscriptions")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions'")" == t ]]
echo 'PASS committed pre-0073 stock alert request upgrade: prior favorites, customer, catalog, stock, consent, orders, incidents, backup requests and all previous table rows preserved'

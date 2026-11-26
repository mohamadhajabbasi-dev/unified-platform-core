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
 [[ "$(basename "$migration")" == 0077_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 76 ]]
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
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('catalog.stock_alerts.read','catalog.stock_alerts.write','content.read','content.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT catalog.set_stock_alert_request('95000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',true);
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic content approval' FROM platform.modules WHERE module_key='content';
INSERT INTO content.articles(tenant_id,article_id,slug,title,body) VALUES('90000000-0000-0000-0000-000000000001','d0740000-0000-0000-0000-000000000010','synthetic-upgrade','Synthetic','Historical text');
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM catalog.stock_alert_subscriptions")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('content.revisions.read','content.revisions.capture');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT content.capture_article_revision('d0740000-0000-0000-0000-000000000010');
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM content.article_revisions")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('content.favorites.read','content.favorites.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT content.set_article_favorite('95000000-0000-0000-0000-000000000001','d0740000-0000-0000-0000-000000000010',true);
RESET SESSION AUTHORIZATION;
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES('90000000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000010','Synthetic second dossier');
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM content.article_favorites")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('crm.merge_reviews.read','crm.merge_reviews.write','crm.engagement.read','crm.engagement.write') ON CONFLICT DO NOTHING;
SET SESSION AUTHORIZATION upc_inv_a;
SELECT crm.request_customer_merge_review('95000000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000010');
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT count(*)=1 FROM crm.customer_merge_reviews")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',
 schemaname||'.'||tablename,schemaname,tablename,
 CASE WHEN schemaname='ops' AND tablename='audit_events' THEN ' WHERE entity_type<>''crm.sla_policies'''
 WHEN schemaname='iam' AND tablename IN ('permissions','role_grants') THEN ' WHERE permission_key NOT IN (''crm.sla.read'',''crm.sla.write'')'
 ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='crm' AND tablename='sla_policies')
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0077_sla_policies.sql
snapshot > "$tmp/after_migration"
cmp "$tmp/before" "$tmp/after_migration"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM crm.sla_policies) AND NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='crm.sla_policies') AND NOT EXISTS(SELECT 1 FROM iam.role_grants WHERE permission_key IN ('crm.sla.read','crm.sla.write'))")" == t ]]
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.tenant_id='90000000-0000-0000-0000-000000000001' AND r.role_key='inventory-editor' AND p.permission_key IN ('crm.sla.read','crm.sla.write');
SET SESSION AUTHORIZATION upc_inv_a;
SELECT crm.register_sla_policy('synthetic-upgrade',15,120);
SELECT crm.register_sla_policy('synthetic-upgrade',15,120);
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_writes"
cmp "$tmp/before" "$tmp/after_writes"
[[ "$(psql_ci -c "SELECT count(*)=1 FROM crm.sla_policies")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='crm.sla_policies'")" == t ]]
echo 'PASS committed pre-0077 SLA policy upgrade: customer merge review, customers, article favorites, revisions, orders, stock and all previous rows preserved'

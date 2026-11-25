#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?dedicated attribute upgrade CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0067_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 66 ]]
python3 - "$tmp/legacy.sql" <<'PY'
from pathlib import Path
import sys
lines=Path("db/tests/0004_catalog_pricing.sql").read_text().splitlines()
assert lines.count("ROLLBACK;")==1 and lines[-2]=="ROLLBACK;"
assert lines[-1].startswith(r"\echo PASS catalog:")
lines[-2]="COMMIT;"
Path(sys.argv[1]).write_text("\n".join(lines)+"\n")
PY
psql_ci < "$tmp/legacy.sql"
psql_ci <<'SQL'
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '80000000-0000-0000-0000-000000000001',module_id,true,'81000000-0000-0000-0000-000000000001','Synthetic upgrade re-enable' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_cat_b;
INSERT INTO catalog.categories(tenant_id,name) VALUES(iam.current_tenant_id(),'Synthetic category');
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT count(*)=2 FROM catalog.categories")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_cat_a;
INSERT INTO catalog.categories(tenant_id,name) VALUES(iam.current_tenant_id(),'Synthetic child');
SELECT catalog.set_category_parent((SELECT category_id FROM catalog.categories WHERE name='Synthetic child'),(SELECT category_id FROM catalog.categories WHERE name='Synthetic category'));
RESET SESSION AUTHORIZATION;
SQL
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_cat_a;
SELECT catalog.register_variant_barcode('83000000-0000-0000-0000-000000000001','00123');
RESET SESSION AUTHORIZATION;
SQL
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',schemaname||'.'||tablename,schemaname,tablename,
 CASE WHEN schemaname='ops' AND tablename='audit_events' THEN ' WHERE entity_type NOT IN (''catalog.attribute_definitions'',''catalog.variant_attribute_values'')' ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND NOT (schemaname='catalog' AND tablename IN ('attribute_definitions','variant_attribute_values')) ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0067_variant_attributes.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM catalog.attribute_definitions) AND NOT EXISTS(SELECT 1 FROM catalog.variant_attribute_values) AND NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type IN ('catalog.attribute_definitions','catalog.variant_attribute_values'))")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_cat_a;
SELECT catalog.register_attribute_definition('color','Color') AS attr \gset
SELECT catalog.set_variant_attribute_value('83000000-0000-0000-0000-000000000001',:'attr','Black');
SELECT catalog.set_variant_attribute_value('83000000-0000-0000-0000-000000000001',:'attr','White');
SELECT catalog.register_variant_barcode('83000000-0000-0000-0000-000000000001','00123');
SELECT catalog.set_category_parent((SELECT category_id FROM catalog.categories WHERE name='Synthetic child'),(SELECT category_id FROM catalog.categories WHERE name='Synthetic category'));
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM catalog.variant_attribute_values WHERE value_text='White' AND variant_id='83000000-0000-0000-0000-000000000001')
 OR (SELECT count(*) FROM catalog.variant_barcodes WHERE barcode_code='00123')<>1
 OR (SELECT amount FROM catalog.price_at('83000000-0000-0000-0000-000000000001','84000000-0000-0000-0000-000000000001','2026-01-15 00:00+00')) IS DISTINCT FROM 1000::numeric THEN RAISE EXCEPTION 'FAIL existing catalog or attribute operation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_registration"
cmp "$tmp/before" "$tmp/after_registration"
[[ "$(psql_ci -c "SELECT count(*)=3 FROM ops.audit_events WHERE entity_type IN ('catalog.attribute_definitions','catalog.variant_attribute_values')")" == t ]]
echo 'PASS committed pre-0067 attribute upgrade: exact old rows before/after migration and writes, barcode/category replay, original price read, no backfill'

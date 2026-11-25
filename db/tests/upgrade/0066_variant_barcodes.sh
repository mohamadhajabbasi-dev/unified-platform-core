#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?dedicated barcode upgrade CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0066_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 65 ]]
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
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND NOT (schemaname='catalog' AND tablename='variant_barcodes') ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0066_variant_barcodes.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*)=0 FROM catalog.variant_barcodes")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_cat_a;
SELECT catalog.register_variant_barcode('83000000-0000-0000-0000-000000000001','00123');
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM catalog.variant_barcodes WHERE barcode_code='00123' AND variant_id='83000000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'FAIL existing variant registration'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_registration"
# Only shared audit is expected to change after registration; prior catalog facts were compared before registration.
echo 'PASS committed pre-0066 barcode upgrade: exact prior rows, existing category hierarchy, no backfill, existing variant registration'

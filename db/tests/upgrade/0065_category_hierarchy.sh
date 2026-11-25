#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?dedicated category upgrade CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0065_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 64 ]]
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
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t)%s ORDER BY (to_jsonb(t)%s)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,
 CASE WHEN schemaname='catalog' AND tablename='categories' THEN '-''parent_category_id''' ELSE '' END,
 CASE WHEN schemaname='catalog' AND tablename='categories' THEN '-''parent_category_id''' ELSE '' END,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0065_category_hierarchy.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*)=2 AND bool_and(parent_category_id IS NULL) FROM catalog.categories")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_cat_a;
INSERT INTO catalog.categories(tenant_id,name) VALUES(iam.current_tenant_id(),'New root');
UPDATE catalog.categories SET name='Renamed root',is_active=false WHERE name='New root';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM catalog.categories WHERE name='Renamed root' AND NOT is_active AND parent_category_id IS NULL) THEN RAISE EXCEPTION 'FAIL old category write'; END IF;
 BEGIN INSERT INTO catalog.categories(tenant_id,name,parent_category_id) VALUES(iam.current_tenant_id(),'Bypass',NULL); RAISE EXCEPTION 'FAIL direct parent INSERT'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE catalog.categories SET parent_category_id=NULL WHERE name='Synthetic category'; RAISE EXCEPTION 'FAIL direct parent UPDATE'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SQL
echo 'PASS committed pre-0065 category upgrade: exact previous rows, unchanged product links and prices, roots preserved, original runtime writes'

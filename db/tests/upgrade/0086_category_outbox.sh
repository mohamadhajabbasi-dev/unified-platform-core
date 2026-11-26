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
 [[ "$(basename "$migration")" == 0086_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 85 ]]
python3 - "$tmp/stock.sql" "$tmp/price.sql" <<'PY'
from pathlib import Path
import sys
for src,dest in [('db/tests/0005_inventory.sql',sys.argv[1]),('db/tests/0085_catalog_outbox.sql',sys.argv[2])]:
    lines=Path(src).read_text().splitlines()
    assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
    lines[-2]='COMMIT;'
    Path(dest).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/price.sql"
psql_ci < "$tmp/stock.sql"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM inventory.stock_ledger)>0 AND (SELECT count(*) FROM inventory.reservations)>0 AND (SELECT count(*) FROM ops.outbox_events WHERE event_kind='catalog.price_list.changed')>0")" == t ]]
# Keep real committed historical tickets and users, not new feedback.
python3 - "$tmp/tickets.sql" <<'PY'
from pathlib import Path
import sys
prefix=Path('db/tests/0064_service_queues.sql').read_text().split('SET SESSION AUTHORIZATION')[0]
assert 'INSERT INTO crm.support_tickets' in prefix
Path(sys.argv[1]).write_text(prefix+'\nCOMMIT;\n')
PY
psql_ci < "$tmp/tickets.sql"
[[ "$(psql_ci -c "SELECT count(*)=2 FROM crm.support_tickets WHERE tenant_id IN ('a0640000-0000-0000-0000-000000000001','a0640000-0000-0000-0000-000000000002')")" == t ]]
python3 - "$tmp/methods.sql" "$tmp/feedback.sql" <<'PY'
from pathlib import Path
import sys
for src,dest in [('db/tests/0069_shipping_methods.sql',sys.argv[1]),('db/tests/0080_support_feedback.sql',sys.argv[2])]:
    lines=Path(src).read_text().splitlines()
    assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
    lines[-2]='COMMIT;'
    Path(dest).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/methods.sql"
psql_ci < "$tmp/feedback.sql"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM sales.shipping_methods)=2 AND (SELECT count(*) FROM crm.support_feedback)=2")" == t ]]
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM catalog.customer_price_decisions)>0 AND (SELECT count(*) FROM catalog.price_quantity_tiers)>0 AND (SELECT count(*) FROM catalog.products)>0 AND (SELECT count(*) FROM catalog.variants)>0")" == t ]]
psql_ci <<'SQL'
INSERT INTO catalog.categories(tenant_id,category_id,name) VALUES
 ('a0850000-0000-0000-0000-000000000001','c0850000-0000-0000-0000-000000000011','Historical root'),
 ('a0850000-0000-0000-0000-000000000001','c0850000-0000-0000-0000-000000000012','Historical child');
SET SESSION AUTHORIZATION upc_catbox_a;
SELECT catalog.set_category_parent('c0850000-0000-0000-0000-000000000012','c0850000-0000-0000-0000-000000000011');
INSERT INTO catalog.product_categories VALUES(iam.current_tenant_id(),'d0850000-0000-0000-0000-000000000001','c0850000-0000-0000-0000-000000000012');
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM catalog.categories WHERE parent_category_id IS NOT NULL)>0 AND (SELECT count(*) FROM catalog.product_categories)>0")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t%s;',
 schemaname||'.'||tablename,schemaname,tablename, '')
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0086_category_outbox.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0086_category_outbox.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM ops.outbox_events WHERE event_kind IN ('catalog.category.changed','catalog.product_category.changed'))")" == t ]]
echo 'PASS committed pre-0086 category outbox upgrade: existing hierarchy, links, audit, products, variants, decisions, tiers, price lists, stock, feedback, tickets, outbox and all previous rows preserved, no backfill and rollback verified'

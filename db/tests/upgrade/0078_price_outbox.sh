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
 [[ "$(basename "$migration")" == 0078_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 77 ]]
python3 - "$tmp/legacy.sql" "$tmp/sla.sql" <<'PY'
from pathlib import Path
import sys
for src,dest in [('db/tests/0004_catalog_pricing.sql',sys.argv[1]),('db/tests/0077_sla_policies.sql',sys.argv[2])]:
    lines=Path(src).read_text().splitlines()
    assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
    lines[-2]='COMMIT;'
    Path(dest).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/legacy.sql"
psql_ci < "$tmp/sla.sql"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM catalog.price_entries)>0 AND (SELECT count(*) FROM crm.sla_policies)>0")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',
 schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='ops' AND tablename='outbox_events')
 ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0078_price_outbox.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*)=0 FROM ops.outbox_events")" == t ]]
psql_ci < db/tests/0078_price_outbox.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
[[ "$(psql_ci -c "SELECT count(*)=0 FROM ops.outbox_events")" == t ]]
echo 'PASS committed pre-0078 price outbox upgrade: all previous rows unchanged, no historical backfill, new capture and rollback verified'

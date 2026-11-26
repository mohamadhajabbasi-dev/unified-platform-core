#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
export LC_ALL=C
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
[[ "$(psql_ci -qAt -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0084_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 83 ]]
psql_ci < db/tests/0083_price_tier_outbox.sql
bash db/tests/concurrency/price_tier_outbox.sh
echo 'PASS historical price-tier outbox contracts at 0083: unchanged SQL and concurrency assertions'

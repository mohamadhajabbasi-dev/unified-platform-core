#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
export LC_ALL=C
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
[[ "$(psql_ci -qAt -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0082_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 81 ]]
psql_ci < db/tests/0078_price_outbox.sql
psql_ci < db/tests/0079_inventory_outbox.sql
bash db/tests/concurrency/price_outbox.sh
bash db/tests/concurrency/inventory_outbox.sh
echo 'PASS historical outbox contracts at 0081: unchanged SQL and concurrency assertions for 0078 and 0079'

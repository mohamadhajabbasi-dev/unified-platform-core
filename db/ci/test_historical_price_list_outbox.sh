#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
export LC_ALL=C
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
[[ "$(psql_ci -qAt -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0083_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 82 ]]
psql_ci < db/tests/0082_price_list_outbox.sql
bash db/tests/concurrency/price_list_outbox.sh
echo 'PASS historical price-list outbox contracts at 0082: unchanged SQL and concurrency assertions'

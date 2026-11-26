#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
export LC_ALL=C
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
[[ "$(psql_ci -qAt -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0085_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 84 ]]
psql_ci < db/tests/0084_price_eligibility_outbox.sql
bash db/tests/concurrency/price_eligibility_outbox.sh
echo 'PASS historical price-eligibility outbox contracts at 0084: unchanged SQL and concurrency assertions'

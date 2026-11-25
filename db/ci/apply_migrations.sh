#!/usr/bin/env bash
# Full clean migration sequence shared by independent disposable CI jobs.
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
export LC_ALL=C
[[ "$(docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
for migration in db/migrations/*.sql; do
  echo "Applying $migration"
  docker exec -i "$PG_CONTAINER" psql -X -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 < "$migration"
done

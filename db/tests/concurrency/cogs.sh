#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci < db/tests/concurrency/cogs_fixture.sql
tenant=b6000000-0000-0000-0000-000000000001
warehouse=b6400000-0000-0000-0000-000000000001
variant=b6300000-0000-0000-0000-000000000001
asset=b6700000-0000-0000-0000-000000000001
expense=b6700000-0000-0000-0000-000000000003
other=b6700000-0000-0000-0000-000000000004
race() {
 local name=$1 statement=$2 ready=0 blocked=0 first second i
 psql_ci >"$tmp/first" 2>&1 <<SQL &
SET application_name='upc_cogs_${name}_first';
SET SESSION AUTHORIZATION upc_cogs_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$statement
SELECT pg_sleep(5);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_cogs_${name}_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 if [[ "$ready" != 1 ]]; then cat "$tmp/first"; wait "$first" || true; return 1; fi
 psql_ci >"$tmp/second" 2>&1 <<SQL &
SET application_name='upc_cogs_${name}_second';
SET SESSION AUTHORIZATION upc_cogs_a;
SET statement_timeout='25s';
$statement
SQL
 second=$!
 for i in {1..35}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_cogs_${name}_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first" || { cat "$tmp/first"; return 1; }
 wait "$second" || { cat "$tmp/second"; return 1; }
 [[ "$blocked" == 1 ]]
}
race capture "SELECT finance.capture_movement_costs('$warehouse','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 3 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
mid=$(psql_ci -c "SELECT movement_id FROM finance.movement_cost_facts WHERE tenant_id='$tenant' AND quantity_delta=-12")
[[ "$mid" =~ ^[0-9a-f-]{36}$ ]]
race post "SELECT finance.post_fifo_cogs('$mid','$asset','$expense');"
eid=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
[[ "$eid" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")" ]]
[[ "$(psql_ci -c "SELECT count(*)=3 AND sum(value_delta)=960 FROM finance.movement_cost_facts WHERE tenant_id='$tenant'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND sum(quantity)=12 AND sum(cost)=1240 FROM finance.fifo_cost_allocations WHERE tenant_id='$tenant' AND outgoing_movement_id='$mid'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM finance.journal_entries WHERE tenant_id='$tenant' AND cogs_movement_id='$mid'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND sum(amount)=0 AND sum(amount) FILTER(WHERE account_id='$expense')=1240 AND sum(amount) FILTER(WHERE account_id='$asset')=-1240 FROM finance.journal_lines WHERE tenant_id='$tenant' AND entry_id='$eid'")" == t ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
DO \$\$ BEGIN
 BEGIN PERFORM finance.post_fifo_cogs('$mid','$asset','$other'); RAISE EXCEPTION 'FAIL conflicting expense retry'; EXCEPTION WHEN unique_violation THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cogs_reader;
DO \$\$ BEGIN
 BEGIN PERFORM finance.post_fifo_cogs('$mid','$asset','$expense'); RAISE EXCEPTION 'FAIL unauthorized COGS'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cogs_b;
DO \$\$ BEGIN
 BEGIN PERFORM finance.post_fifo_cogs('$mid','$asset','$expense'); RAISE EXCEPTION 'FAIL cross-tenant COGS'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SQL
echo 'PASS COGS concurrency: actual competing capture and journal locks, exact retries, balanced one journal, permission and tenant gates'

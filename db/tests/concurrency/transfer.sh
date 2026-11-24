#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES ('a0000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000011','transfer-dest','Synthetic dest');
SET SESSION AUTHORIZATION upc_sale_a;
SELECT inventory.adjust_stock('a4000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000004',10,'transfer-race-seed','Synthetic');
RESET SESSION AUTHORIZATION;
SQL
src=a4000000-0000-0000-0000-000000000001
dst=a4000000-0000-0000-0000-000000000011
v=a3000000-0000-0000-0000-000000000004
deadline=$(psql_ci -c "SELECT clock_timestamp()+interval '1 hour'")
transfer() { echo "SELECT inventory.transfer_stock('$1','$2','$3','Synthetic',jsonb_build_array(jsonb_build_object('variant_id','$v','quantity',$4)));"; }
race() {
 local phase="$1" stmt1="$2" stmt2="$3" expect="$4" first second ready=0 blocked=0
 psql_ci >"$tmp/$phase-first" 2>&1 <<SQL &
SET application_name='upc_transfer_${phase}_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$stmt1
SELECT pg_sleep(5);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_transfer_${phase}_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$phase-second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_transfer_${phase}_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
$stmt2
SQL
 second=$!
 for i in {1..35}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_transfer_${phase}_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first" || { cat "$tmp/$phase-first"; return 1; }
 [[ "$blocked" == 1 ]]
 if [[ "$expect" == fail ]]; then
  if wait "$second"; then cat "$tmp/$phase-second"; return 1; fi
  grep -q '23514: Insufficient unreserved stock' "$tmp/$phase-second" || { cat "$tmp/$phase-second"; return 1; }
 else
  wait "$second" || { cat "$tmp/$phase-second"; return 1; }
 fi
}
race reserve "$(transfer race-out "$src" "$dst" 7)" "SELECT inventory.reserve_stock('$src','$v',4,'race-transfer-hold','$deadline');" fail
race opposite "$(transfer race-reverse "$dst" "$src" 2)" "$(transfer race-forward "$src" "$dst" 4)" success
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.warehouse_transfers WHERE request_key LIKE 'race-%'")" == 3 ]]
[[ "$(psql_ci -c "SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE variant_id='$v' AND warehouse_id='$src'")" == 1 ]]
[[ "$(psql_ci -c "SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE variant_id='$v' AND warehouse_id='$dst'")" == 9 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE variant_id='$v'")" == 0 ]]
echo 'PASS transfer concurrency: competing reservation rejected, opposite transfers serialize and conserve stock'

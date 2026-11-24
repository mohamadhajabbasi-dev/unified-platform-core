#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000021','a2000000-0000-0000-0000-000000000001','serial-race','Synthetic serial');
SET SESSION AUTHORIZATION upc_sale_a;
SELECT inventory.configure_tracking('a3000000-0000-0000-0000-000000000021','serial',false);
SELECT inventory.register_serial('a3000000-0000-0000-0000-000000000021','SYNTHETIC-RACE');
SELECT procurement.issue_purchase('serial-po-a',(SELECT counterparty_id FROM procurement.counterparties WHERE party_key='race-supplier'),
 'a4000000-0000-0000-0000-000000000001','IRR',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000021','quantity',1,'unit_cost',100)));
SELECT procurement.issue_purchase('serial-po-b',(SELECT counterparty_id FROM procurement.counterparties WHERE party_key='race-supplier'),
 'a4000000-0000-0000-0000-000000000011','IRR',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000021','quantity',1,'unit_cost',100)));
RESET SESSION AUTHORIZATION;
SQL
v=a3000000-0000-0000-0000-000000000021
src=a4000000-0000-0000-0000-000000000001
dst=a4000000-0000-0000-0000-000000000011
sid=$(psql_ci -c "SELECT serial_id FROM inventory.serial_numbers WHERE variant_id='$v'")
pa=$(psql_ci -c "SELECT purchase_id FROM procurement.purchase_orders WHERE request_key='serial-po-a'")
pb=$(psql_ci -c "SELECT purchase_id FROM procurement.purchase_orders WHERE request_key='serial-po-b'")
deadline=$(psql_ci -c "SELECT clock_timestamp()+interval '1 hour'")
receipt() { echo "SELECT procurement.receive_purchase_allocated('$1','$2','Synthetic',jsonb_build_array(jsonb_build_object('variant_id','$v','serial_id','$sid','quantity',1)));"; }
reserve() { echo "SELECT inventory.reserve_stock('$src','$v',1,'$1','$deadline');"; }

race() {
 local phase="$1" stmt1="$2" stmt2="$3" expect="$4" first second ready=0 blocked=0
 psql_ci >"$tmp/$phase-first" 2>&1 <<SQL &
SET application_name='upc_serial_${phase}_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$stmt1
SELECT pg_sleep(5);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_serial_${phase}_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$phase-second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_serial_${phase}_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
$stmt2
SQL
 second=$!
 for i in {1..35}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_serial_${phase}_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first" || { cat "$tmp/$phase-first"; return 1; }
 [[ "$blocked" == 1 ]]
 if [[ "$expect" != success ]]; then
  if wait "$second"; then cat "$tmp/$phase-second"; return 1; fi
  grep -q "$expect" "$tmp/$phase-second" || { cat "$tmp/$phase-second"; return 1; }
 else
  wait "$second" || { cat "$tmp/$phase-second"; return 1; }
 fi
}

race receipt "$(receipt "$pa" serial-receipt-a)" "$(receipt "$pb" serial-receipt-b)" '23514: Serial stock conflict'
[[ "$(psql_ci -c "SELECT count(*) FROM procurement.goods_receipts WHERE purchase_id IN ('$pa','$pb')")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_ledger WHERE serial_id='$sid'")" == 1 ]]
race reserve "$(reserve serial-hold-a)" "$(reserve serial-hold-b)" '23514: Insufficient unreserved stock'
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE variant_id='$v' AND state='active'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservation_allocations WHERE serial_id='$sid'")" == 1 ]]
hold=$(psql_ci -c "SELECT reservation_id FROM inventory.reservations WHERE request_key='serial-hold-a'")
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT inventory.release_reservation('$hold');
SQL
race transfer "$(reserve serial-hold-c)" "SELECT inventory.transfer_allocated('serial-steal','$src','$dst','Synthetic',jsonb_build_array(jsonb_build_object('variant_id','$v','serial_id','$sid','quantity',1)));" '23514: Insufficient unreserved stock'
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.warehouse_transfers WHERE request_key='serial-steal'")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE variant_id='$v' AND state='active'")" == 1 ]]
[[ "$(psql_ci -c "SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE serial_id='$sid' AND warehouse_id='$src'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_ledger WHERE serial_id='$sid' AND warehouse_id='$dst'")" == 0 ]]
echo 'PASS serial concurrency: competing cross-warehouse receipts, duplicate reservation and reserved serial transfer rejected with observed locks'

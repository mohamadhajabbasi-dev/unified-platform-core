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
 local second_statement=${3:-$2}
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
$second_statement
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
# Extend the same verified fixture and real lock-wait harness; no duplicated setup.
warehouse2=b6400000-0000-0000-0000-000000000003
customer=b6500000-0000-0000-0000-000000000001
pricelist=b6600000-0000-0000-0000-000000000001
tid=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT inventory.transfer_stock('cogs-race-transfer','$warehouse','$warehouse2','Synthetic transfer',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',3)));
SQL
)
[[ "$tid" =~ ^[0-9a-f-]{36}$ ]]
race transfer "SELECT finance.capture_transfer_costs('$tid','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 2 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM inventory.transfer_lines tl JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id WHERE tl.tenant_id='$tenant' AND tl.transfer_id='$tid' AND fo.quantity_delta=-3 AND fi.quantity_delta=3 AND fo.value_delta=-360 AND fi.value_delta=360")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=3 FROM finance.journal_entries WHERE tenant_id='$tenant'")" == t ]]
# Sell the transferred units; the reversal must restore their historical remote receipt cost.
oid2=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT sales.create_checkout('cogs-race-destination-sale','$customer','$warehouse2','$pricelist','in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',3,'expected_unit_price',1000)));
SQL
)
[[ "$oid2" =~ ^[0-9a-f-]{36}$ ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT sales.record_capture('$oid2','synthetic','acct','cogs-race-destination-payment',3000,'IRR',clock_timestamp());
SELECT sales.fulfill_order('$oid2');
SQL
[[ "$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.capture_movement_costs('$warehouse2','$variant');
SQL
)" == 1 ]]
mid2=$(psql_ci -c "SELECT cf.movement_id FROM finance.movement_cost_facts cf JOIN inventory.stock_ledger sl ON sl.tenant_id=cf.tenant_id AND sl.movement_id=cf.movement_id JOIN sales.order_items si ON si.tenant_id=sl.tenant_id AND si.reservation_id=sl.reservation_id WHERE si.tenant_id='$tenant' AND si.order_id='$oid2'")
[[ "$mid2" =~ ^[0-9a-f-]{36}$ ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.post_fifo_cogs('$mid2','$asset','$expense');
SELECT sales.receive_full_return('$oid2','cogs-race-destination-return','Inspected sellable');
DO \$\$ BEGIN
 BEGIN PERFORM finance.capture_movement_costs('$warehouse2','$variant'); RAISE EXCEPTION 'FAIL capture before reversal'; EXCEPTION WHEN check_violation THEN NULL; END;
END \$\$;
SQL
race reversal "SELECT finance.reverse_fifo_cogs('$mid2');"
rev=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
[[ "$rev" =~ ^[0-9a-f-]{36}$ ]]
[[ "$rev" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")" ]]
race return_capture "SELECT finance.capture_movement_costs('$warehouse2','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 1 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*)=7 AND sum(value_delta)=960 FROM finance.movement_cost_facts WHERE tenant_id='$tenant'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND sum(quantity)=3 AND sum(cost)=360 FROM finance.fifo_cost_allocations WHERE tenant_id='$tenant' AND outgoing_movement_id='$mid2'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM finance.journal_entries j JOIN finance.movement_cost_facts cf ON cf.tenant_id=j.tenant_id AND cf.movement_id=j.cogs_return_movement_id WHERE j.tenant_id='$tenant' AND j.entry_id='$rev' AND cf.warehouse_id='$warehouse2' AND cf.quantity_delta=3 AND cf.value_delta=360")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND sum(amount)=0 AND sum(amount) FILTER(WHERE account_id='$expense')=-360 AND sum(amount) FILTER(WHERE account_id='$asset')=360 FROM finance.journal_lines WHERE tenant_id='$tenant' AND entry_id='$rev'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=5 FROM finance.journal_entries WHERE tenant_id='$tenant'")" == t ]]
[[ "$(psql_ci -c "SELECT sum(amount) FILTER(WHERE account_id='$asset')=960 AND sum(amount) FILTER(WHERE account_id='$expense')=1240 FROM finance.journal_lines WHERE tenant_id='$tenant'")" == t ]]
[[ "$(psql_ci -c "SELECT sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse')=5 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse2')=3 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse')=600 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse2')=360 FROM finance.movement_cost_facts WHERE tenant_id='$tenant'")" == t ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_reader;
DO \$\$ BEGIN
 BEGIN PERFORM finance.capture_transfer_costs('$tid','$variant'); RAISE EXCEPTION 'FAIL unauthorized transfer capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.reverse_fifo_cogs('$mid2'); RAISE EXCEPTION 'FAIL unauthorized reversal'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cogs_b;
DO \$\$ BEGIN
 BEGIN PERFORM finance.reverse_fifo_cogs('$mid2'); RAISE EXCEPTION 'FAIL cross-tenant reversal'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SQL
# Same tenant, warehouse, roles and lock-wait harness; use existing unused physical
# variant and separate asset/expense accounts to isolate the moving-average scenario.
variant=b6300000-0000-0000-0000-000000000004
asset=b6700000-0000-0000-0000-000000000005
expense=b6700000-0000-0000-0000-000000000006
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
DO \$\$
DECLARE t uuid:=iam.current_tenant_id(); s uuid; po uuid; oid uuid;
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
BEGIN
 PERFORM finance.configure_valuation_preview('$variant','moving_average','IRR');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,'$asset','avg-inventory','Average inventory','asset','IRR'),(t,'$expense','avg-cogs','Average COGS','expense','IRR');
 s:=procurement.register_counterparty('avg-race-supplier',NULL,'Synthetic average');
 po:=procurement.issue_purchase('avg-race-po1',s,'$warehouse','IRR',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',10,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'avg-race-r1','delivery');
 PERFORM finance.record_supplier_invoice(po,'AVG-RACE-1',d,d+7,1000,'IRR',digest,'$asset','b6700000-0000-0000-0000-000000000002');
 po:=procurement.issue_purchase('avg-race-po2',s,'$warehouse','IRR',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',10,'unit_cost',120)));
 PERFORM procurement.receive_purchase(po,'avg-race-r2','delivery');
 PERFORM finance.record_supplier_invoice(po,'AVG-RACE-2',d,d+7,1200,'IRR',digest,'$asset','b6700000-0000-0000-0000-000000000002');
 oid:=sales.create_checkout('avg-race-sale','$customer','$warehouse','$pricelist','in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',12,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','avg-race-payment',12000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
END \$\$;
SQL
race avg_capture "SELECT finance.capture_movement_costs('$warehouse','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 3 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
mid=$(psql_ci -c "SELECT movement_id FROM finance.movement_cost_facts WHERE tenant_id='$tenant' AND variant_id='$variant' AND quantity_delta=-12 AND value_delta=-1320")
[[ "$mid" =~ ^[0-9a-f-]{36}$ ]]
race avg_post "SELECT finance.post_inventory_cogs('$mid','$asset','$expense','moving_average');"
eid=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
[[ "$eid" =~ ^[0-9a-f-]{36}$ ]]
[[ "$eid" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")" ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND sum(amount)=0 AND sum(amount) FILTER(WHERE account_id='$expense')=1320 AND sum(amount) FILTER(WHERE account_id='$asset')=-1320 FROM finance.journal_lines WHERE tenant_id='$tenant' AND entry_id='$eid'")" == t ]]
tid=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT inventory.transfer_stock('avg-race-transfer','$warehouse','$warehouse2','Synthetic average transfer',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',3)));
SQL
)
[[ "$tid" =~ ^[0-9a-f-]{36}$ ]]
race avg_transfer "SELECT finance.capture_transfer_costs('$tid','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 2 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM inventory.transfer_lines tl JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id WHERE tl.tenant_id='$tenant' AND tl.transfer_id='$tid' AND tl.variant_id='$variant' AND fo.value_delta=-330 AND fi.value_delta=330")" == t ]]
oid2=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT sales.create_checkout('avg-race-destination-sale','$customer','$warehouse2','$pricelist','in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',3,'expected_unit_price',1000)));
SQL
)
[[ "$oid2" =~ ^[0-9a-f-]{36}$ ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT sales.record_capture('$oid2','synthetic','acct','avg-race-destination-payment',3000,'IRR',clock_timestamp());
SELECT sales.fulfill_order('$oid2');
SQL
[[ "$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.capture_movement_costs('$warehouse2','$variant');
SQL
)" == 1 ]]
mid2=$(psql_ci -c "SELECT cf.movement_id FROM finance.movement_cost_facts cf JOIN inventory.stock_ledger sl ON sl.tenant_id=cf.tenant_id AND sl.movement_id=cf.movement_id JOIN sales.order_items si ON si.tenant_id=sl.tenant_id AND si.reservation_id=sl.reservation_id WHERE si.tenant_id='$tenant' AND si.order_id='$oid2' AND cf.value_delta=-330")
[[ "$mid2" =~ ^[0-9a-f-]{36}$ ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.post_inventory_cogs('$mid2','$asset','$expense','moving_average');
SELECT sales.receive_full_return('$oid2','avg-race-return','Inspected sellable');
DO \$\$ BEGIN
 BEGIN PERFORM finance.capture_movement_costs('$warehouse2','$variant'); RAISE EXCEPTION 'FAIL average capture before reversal'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.reverse_fifo_cogs('$mid2'); RAISE EXCEPTION 'FAIL average FIFO reversal mismatch'; EXCEPTION WHEN check_violation THEN NULL; END;
END \$\$;
SQL
race avg_reversal "SELECT finance.reverse_inventory_cogs('$mid2','moving_average');"
rev=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
[[ "$rev" =~ ^[0-9a-f-]{36}$ ]]
[[ "$rev" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")" ]]
race avg_return_capture "SELECT finance.capture_movement_costs('$warehouse2','$variant');"
[[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 1 ]]
[[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
[[ "$(psql_ci -c "SELECT count(*)=7 AND sum(value_delta)=880 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse')=5 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse2')=3 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse')=550 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse2')=330 FROM finance.movement_cost_facts WHERE tenant_id='$tenant' AND variant_id='$variant'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=0 FROM finance.fifo_cost_allocations WHERE tenant_id='$tenant' AND variant_id='$variant'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM finance.journal_entries j JOIN finance.movement_cost_facts cf ON cf.tenant_id=j.tenant_id AND cf.movement_id=j.cogs_return_movement_id WHERE j.tenant_id='$tenant' AND j.entry_id='$rev' AND cf.variant_id='$variant' AND cf.value_delta=330")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND sum(amount)=0 AND sum(amount) FILTER(WHERE account_id='$expense')=-330 AND sum(amount) FILTER(WHERE account_id='$asset')=330 FROM finance.journal_lines WHERE tenant_id='$tenant' AND entry_id='$rev'")" == t ]]
[[ "$(psql_ci -c "SELECT sum(amount) FILTER(WHERE account_id='$asset')=880 AND sum(amount) FILTER(WHERE account_id='$expense')=1320 FROM finance.journal_lines WHERE tenant_id='$tenant'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=10 FROM finance.journal_entries WHERE tenant_id='$tenant'")" == t ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.assert_inventory_cost_ready('$warehouse','$variant');
SELECT finance.assert_inventory_cost_ready('$warehouse2','$variant');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cogs_reader;
DO \$\$ BEGIN
 BEGIN PERFORM finance.reverse_inventory_cogs('$mid2','moving_average'); RAISE EXCEPTION 'FAIL unauthorized average reversal'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cogs_b;
DO \$\$ BEGIN
 BEGIN PERFORM finance.reverse_inventory_cogs('$mid2','moving_average'); RAISE EXCEPTION 'FAIL cross-tenant average reversal'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END \$\$;
RESET SESSION AUTHORIZATION;
SQL
# Two different entry points into one historical connected component must share the
# same variant lock, without duplicating facts or posting any transfer journals.
warehouse3=b6400000-0000-0000-0000-000000000004
psql_ci -c "INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES ('$tenant','$warehouse3','third','Synthetic chain destination')"
for method in fifo moving_average; do
 if [[ "$method" == fifo ]]; then
  variant=b6300000-0000-0000-0000-000000000001
  unit=120
  expected=960
 else
  variant=b6300000-0000-0000-0000-000000000004
  unit=110
  expected=880
 fi
 ids=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT inventory.transfer_stock('chain-bc-$method','$warehouse2','$warehouse3','Chain B to C',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',2)));
SELECT inventory.transfer_stock('chain-ca-$method','$warehouse3','$warehouse','Chain C to A',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',1)));
SELECT inventory.transfer_stock('chain-ab-$method','$warehouse','$warehouse2','Chain A to B',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',1)));
SQL
)
 mapfile -t chain_ids <<< "$ids"
 [[ "${#chain_ids[@]}" == 3 ]]
 for id in "${chain_ids[@]}"; do [[ "$id" =~ ^[0-9a-f-]{36}$ ]]; done
 tid1=${chain_ids[0]}
 tid3=${chain_ids[2]}
 race "chain_$method" "SELECT finance.capture_transfer_costs('$tid3','$variant');" "SELECT finance.capture_transfer_costs('$tid1','$variant');"
 [[ "$(grep -E '^[0-9]+$' "$tmp/first")" == 6 ]]
 [[ "$(grep -E '^[0-9]+$' "$tmp/second")" == 0 ]]
 [[ "$(psql_ci -c "SELECT count(*)=13 AND sum(value_delta)=$expected AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse')=5 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse2')=2 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse3')=1 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse')=5*$unit AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse2')=2*$unit AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse3')=$unit FROM finance.movement_cost_facts WHERE tenant_id='$tenant' AND variant_id='$variant'")" == t ]]
 # Bounded synthetic timing sample: 8 cycles = 24 transfers, 48 new cost facts.
 # The timeout is a CI regression ceiling, not a production latency target.
 psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
DO \$\$
BEGIN
 FOR i IN 1..8 LOOP
  PERFORM inventory.transfer_stock('chain-scale-ab-$method-'||i,'$warehouse','$warehouse2','Sample A to B',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',1)));
  PERFORM inventory.transfer_stock('chain-scale-bc-$method-'||i,'$warehouse2','$warehouse3','Sample B to C',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',1)));
  PERFORM inventory.transfer_stock('chain-scale-ca-$method-'||i,'$warehouse3','$warehouse','Sample C to A',jsonb_build_array(jsonb_build_object('variant_id','$variant','quantity',1)));
 END LOOP;
END \$\$;
SQL
 start_ms=$(date +%s%3N)
 result=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SET statement_timeout='60s';
SELECT finance.capture_transfer_costs('$tid1','$variant');
SQL
)
 capture_ms=$(( $(date +%s%3N) - start_ms ))
 [[ "$result" == 48 ]]
 start_ms=$(date +%s%3N)
 result=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SET statement_timeout='60s';
SELECT finance.capture_transfer_costs('$tid3','$variant');
SQL
)
 retry_ms=$(( $(date +%s%3N) - start_ms ))
 [[ "$result" == 0 ]]
 echo "CHAIN_TIMING method=$method transfers=24 new_facts=48 capture_ms=$capture_ms retry_ms=$retry_ms"
 [[ "$(psql_ci -c "SELECT count(*)=61 AND sum(value_delta)=$expected AND sum(quantity_delta)=8 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse')=5 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse2')=2 AND sum(quantity_delta) FILTER(WHERE warehouse_id='$warehouse3')=1 AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse')=5*$unit AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse2')=2*$unit AND sum(value_delta) FILTER(WHERE warehouse_id='$warehouse3')=$unit FROM finance.movement_cost_facts WHERE tenant_id='$tenant' AND variant_id='$variant'")" == t ]]
 [[ "$(psql_ci -c "SELECT count(*)=28 AND bool_and(fo.quantity_delta=-tl.quantity AND fi.quantity_delta=tl.quantity AND fo.value_delta=-fi.value_delta) FROM inventory.transfer_lines tl JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id WHERE tl.tenant_id='$tenant' AND tl.variant_id='$variant'")" == t ]]
 if [[ "$method" == moving_average ]]; then
  [[ "$(psql_ci -c "SELECT count(*)=0 FROM finance.fifo_cost_allocations WHERE tenant_id='$tenant' AND variant_id='$variant'")" == t ]]
 fi
 psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.assert_inventory_cost_ready('$warehouse','$variant');
SELECT finance.assert_inventory_cost_ready('$warehouse2','$variant');
SELECT finance.assert_inventory_cost_ready('$warehouse3','$variant');
SQL
done
[[ "$(psql_ci -c "SELECT count(*)=10 FROM finance.journal_entries WHERE tenant_id='$tenant'")" == t ]]
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_cogs_a;
SELECT finance.assert_tenant_inventory_cost_ready();
SQL
echo 'PASS COGS concurrency: twelve competing lock races (six FIFO, six moving average), distinct chain entry points, 48 extra transfer pairs, readiness and tenant isolation'




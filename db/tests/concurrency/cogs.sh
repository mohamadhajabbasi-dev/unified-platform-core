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
echo 'PASS COGS concurrency: five competing lock races (capture, posting, paired transfer, reversal, return capture), exact retries, remote receipt cost and balanced journals, permission and tenant gates'


#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_sale_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sale_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sale_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_sale_a,upc_sale_b,upc_sale_reader;
GRANT upc_checkout_offline TO upc_sale_a;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0000000-0000-0000-0000-000000000001','sale-a','Synthetic A'),
 ('a0000000-0000-0000-0000-000000000002','sale-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('a1000000-0000-0000-0000-000000000001','test','sale-a'),
 ('a1000000-0000-0000-0000-000000000002','test','sale-b'),
 ('a1000000-0000-0000-0000-000000000003','test','sale-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001'),
 ('a0000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002'),
 ('a0000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_sale_a','a0000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000001'),
 ('upc_sale_b','a0000000-0000-0000-0000-000000000002','a1000000-0000-0000-0000-000000000002'),
 ('upc_sale_reader','a0000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('a0000000-0000-0000-0000-000000000001','sales-race-editor'),
 ('a0000000-0000-0000-0000-000000000002','sales-race-editor'),
 ('a0000000-0000-0000-0000-000000000001','sales-race-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='sales-race-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE role_key='sales-race-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='a1000000-0000-0000-0000-000000000003' AND r.role_key='sales-race-reader')
 OR (m.user_id<>'a1000000-0000-0000-0000-000000000003' AND r.role_key='sales-race-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'a1000000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('sale-a','sale-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','A','physical'),
 ('a0000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','B','physical'),
 ('a0000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','stock-a','A'),
 ('a0000000-0000-0000-0000-000000000002','a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000002','stock-b','B'),
 ('a0000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000003','a2000000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','main','A'),
 ('a0000000-0000-0000-0000-000000000002','a4000000-0000-0000-0000-000000000002','main','B');

GRANT upc_payment_recorder TO upc_sale_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='sales-race-editor' AND (p.permission_key LIKE 'sales.%' OR p.permission_key IN ('crm.read','catalog.read'));
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'sales.read' FROM iam.roles WHERE role_key='sales-race-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'a1000000-0000-0000-0000-000000000001','Synthetic sales test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('sale-a','sale-b') AND m.module_key IN ('sales','crm','catalog');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('a0000000-0000-0000-0000-000000000002','a5000000-0000-0000-0000-000000000002','Synthetic customer B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000004','No stock','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000004','a2000000-0000-0000-0000-000000000004','no-stock','No stock');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('a0000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','original','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT 'a0000000-0000-0000-0000-000000000001',v.variant_id,'a6000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='a0000000-0000-0000-0000-000000000001';

SET SESSION AUTHORIZATION upc_sale_a;
SELECT inventory.adjust_stock('a4000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001',10,'receipt','Receipt');
RESET SESSION AUTHORIZATION;
SQL
deadline=$(psql_ci -c "SELECT clock_timestamp()+interval '1 hour'")
checkout="SELECT sales.create_checkout('concurrent-checkout','a5000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','in_person','$deadline',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000001','quantity',2,'expected_unit_price',1000)));"
race() {
 local phase="$1" statement="$2" ready=0 blocked=0 first second
 psql_ci >"$tmp/$phase-first" <<SQL &
SET application_name='upc_sales_${phase}_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$statement
SELECT pg_sleep(5);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_sales_${phase}_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$phase-second" <<SQL &
SET application_name='upc_sales_${phase}_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
$statement
SQL
 second=$!
 for i in {1..35}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_sales_${phase}_second' AND l.locktype='advisory' AND NOT l.granted")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$phase-first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$phase-second")
 [[ "$a" == "$b" ]]
 echo "$a"
}
order=$(race checkout "$checkout")
captured=$(psql_ci -c "SELECT clock_timestamp()")
payment=$(race capture "SELECT sales.record_capture('$order','synthetic','acct','concurrent-capture',2000,'IRR','$captured');")
[[ -n "$payment" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM sales.orders WHERE tenant_id='a0000000-0000-0000-0000-000000000001'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM sales.payments WHERE tenant_id='a0000000-0000-0000-0000-000000000001'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE tenant_id='a0000000-0000-0000-0000-000000000001'")" == 1 ]]

# 0058: actual competing runtime exact retries on existing canonical writer.
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT sales.fulfill_order('$order');
SQL
runtime_return=$(race full_return "SELECT sales.receive_full_return('$order','runtime-full-return','Synthetic sellable');")
tenant='a0000000-0000-0000-0000-000000000001'
[[ "$(psql_ci -c "SELECT count(*)=1 AND sum(received_quantity)=2 FROM sales.return_items WHERE tenant_id='$tenant' AND return_id='$runtime_return'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_ledger WHERE tenant_id='$tenant' AND adjustment_key LIKE 'sales-return:$runtime_return:%'")" == 1 ]]
# Actual different-key race on another fulfilled order. First commits;
# second waits on the exact order lock and must reject the returned state.
order=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT sales.create_checkout('return-conflict-order','a5000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000001','quantity',2,'expected_unit_price',1000)));
SQL
)
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT sales.record_capture('$order','synthetic','acct','return-conflict-payment',2000,'IRR',clock_timestamp());
SELECT sales.fulfill_order('$order');
SQL
# Use existing exact order-lock observer for both subsequent races.
cap_lock() {
 local app=$1 granted=$2 i
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='$app' AND l.locktype='advisory' AND l.mode='ExclusiveLock' AND l.granted=$granted AND l.classid=((hashtextextended(jsonb_build_array('sales-order','$tenant'::uuid,'$order'::uuid)::text,0)>>32)&4294967295)::oid AND l.objid=(hashtextextended(jsonb_build_array('sales-order','$tenant'::uuid,'$order'::uuid)::text,0)&4294967295)::oid AND l.objsubid=1")" == 1 ]]; then return 0; fi
  sleep 0.1
 done
 return 1
}
psql_ci >"$tmp/return-conflict-first" 2>&1 <<SQL &
SET application_name='upc_return_conflict_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT sales.receive_full_return('$order','return-conflict-first','Synthetic sellable');
SELECT pg_sleep(8);
COMMIT;
SQL
first=$!
cap_lock upc_return_conflict_first true
psql_ci >"$tmp/return-conflict-second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_return_conflict_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
SELECT sales.receive_full_return('$order','return-conflict-second','Synthetic sellable');
SQL
second=$!
cap_lock upc_return_conflict_second false
wait "$first" || { cat "$tmp/return-conflict-first"; exit 1; }
if wait "$second"; then echo 'FAIL second runtime return'; exit 1; fi
grep -q '23514: Only fulfilled orders can receive a full return' "$tmp/return-conflict-second"
[[ "$(psql_ci -c "SELECT count(*)=1 AND sum(received_quantity)=2 FROM sales.return_items WHERE tenant_id='$tenant' AND order_id='$order'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_ledger l JOIN sales.returns h ON h.tenant_id=l.tenant_id AND l.adjustment_key LIKE 'sales-return:'||h.return_id::text||':%' WHERE h.tenant_id='$tenant' AND h.order_id='$order'")" == 1 ]]
echo 'RETURN_WRITER_RACE same-key replay and different-key exclusion'
# 0057: preserve privileged aggregate cap race with a separate fulfilled
# synthetic order and incomplete fixture header, not a second live receipt.
order=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT sales.create_checkout('return-cap-struct-order','a5000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000001','quantity',2,'expected_unit_price',1000)));
SQL
)
psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
SELECT sales.record_capture('$order','synthetic','acct','return-cap-struct-payment',2000,'IRR',clock_timestamp());
SELECT sales.fulfill_order('$order');
SQL
return_id=$(psql_ci -c "INSERT INTO sales.returns(tenant_id,order_id,request_key,reason,received_by) VALUES('$tenant','$order','cap-struct-fixture','Synthetic structural only','a1000000-0000-0000-0000-000000000001') RETURNING return_id")
[[ "$return_id" =~ ^[0-9a-f-]{36}$ ]]
identity=$(psql_ci -c "SELECT l.movement_id||'|'||l.reservation_id FROM inventory.stock_ledger l JOIN sales.order_items i USING(tenant_id,reservation_id) WHERE i.tenant_id='$tenant' AND i.order_id='$order' AND l.quantity_delta=-2")
IFS='|' read -r movement reservation <<<"$identity"
[[ "$movement" =~ ^[0-9a-f-]{36}$ && "$reservation" =~ ^[0-9a-f-]{36}$ ]]
baseline=$(psql_ci -c "SELECT count(*)||'|'||sum(quantity_delta) FROM inventory.stock_ledger WHERE tenant_id='$tenant'")
[[ "$(psql_ci -c "SELECT count(*) FROM sales.return_items WHERE tenant_id='$tenant' AND order_id='$order'")" == 0 ]]
psql_ci >"$tmp/return-cap-first" 2>&1 <<SQL &
SET application_name='upc_return_cap_first';
BEGIN;
SET LOCAL statement_timeout='25s';
INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
VALUES('$tenant','$return_id','$order','$reservation','$movement',2,'sellable');
SELECT pg_sleep(8);
COMMIT;
SQL
cap_first=$!
cap_lock upc_return_cap_first true
psql_ci >"$tmp/return-cap-second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_return_cap_second';
SET statement_timeout='25s';
INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
VALUES('$tenant','$return_id','$order','$reservation','$movement',1,'damaged');
SQL
cap_second=$!
cap_lock upc_return_cap_second false
wait "$cap_first" || { cat "$tmp/return-cap-first"; exit 1; }
if wait "$cap_second"; then echo 'FAIL concurrent receipt exceeded sale'; exit 1; fi
grep -q '23514: Return receipt quantity exceeds original sale movement' "$tmp/return-cap-second"
[[ "$(psql_ci -c "SELECT count(*)=1 AND sum(received_quantity)=2 FROM sales.return_items WHERE tenant_id='$tenant' AND sale_movement_id='$movement'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)||'|'||sum(quantity_delta) FROM inventory.stock_ledger WHERE tenant_id='$tenant'")" == "$baseline" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM sales.refunds WHERE tenant_id='$tenant'")" == 0 ]]
echo 'RETURN_CAP_RACE competing inserts serialized on exact order lock; one committed and excess rejected'

echo 'PASS sales concurrency: actual competing checkout and capture locks, one order, one hold, one payment, atomic return quantity cap and runtime full-return races'

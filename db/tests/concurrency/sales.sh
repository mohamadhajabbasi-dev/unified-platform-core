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
echo 'PASS sales concurrency: actual competing checkout and capture locks, one order, one hold, one payment'

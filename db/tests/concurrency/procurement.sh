#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
INSERT INTO iam.role_grants SELECT tenant_id,role_id,permission_key FROM iam.roles CROSS JOIN iam.permissions
 WHERE role_key='sales-race-editor' AND permission_key LIKE 'procurement.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0000000-0000-0000-0000-000000000001',module_id,true,'a1000000-0000-0000-0000-000000000001','Synthetic procurement' FROM platform.modules WHERE module_key='procurement';
SET SESSION AUTHORIZATION upc_sale_a;
SELECT procurement.issue_purchase('race-po',procurement.register_counterparty('race-supplier',NULL,'Synthetic supplier'),
 'a4000000-0000-0000-0000-000000000001','IRR',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000001','quantity',5,'unit_cost',100)));
RESET SESSION AUTHORIZATION;
SQL
po=$(psql_ci -c "SELECT purchase_id FROM procurement.purchase_orders WHERE request_key='race-po'")
statement="SELECT procurement.receive_purchase('$po','race-receipt','synthetic-delivery');"
psql_ci >"$tmp/first" 2>&1 <<SQL &
SET application_name='upc_procurement_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$statement
SELECT pg_sleep(5);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_procurement_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<SQL &
SET application_name='upc_procurement_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
$statement
SQL
second=$!
blocked=0
for i in {1..35}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_procurement_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first" || { cat "$tmp/first"; exit 1; }
wait "$second" || { cat "$tmp/second"; exit 1; }
[[ "$blocked" == 1 ]]
[[ "$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM procurement.goods_receipts WHERE purchase_id='$po'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.stock_ledger WHERE adjustment_key LIKE 'purchase-receipt:%'")" == 1 ]]
[[ "$(psql_ci -c "SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE adjustment_key LIKE 'purchase-receipt:%'")" == 5 ]]
echo 'PASS procurement concurrency: actual competing receipt locks, one receipt and one stock movement'

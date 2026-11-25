#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
GRANT upc_price_customer_verifier TO upc_sale_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,permission_key FROM iam.roles CROSS JOIN iam.permissions
 WHERE role_key='sales-race-editor' AND permission_key IN ('catalog.price.write','catalog.price.eligibility.write','catalog.price.customer');
SET SESSION AUTHORIZATION upc_sale_a;
SELECT catalog.initialize_standard_prices('IRR');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT iam.current_tenant_id(),'a3000000-0000-0000-0000-000000000001',price_list_id,850,tstzrange('2020-01-01',NULL,'[)') FROM catalog.price_lists WHERE list_key='colleague';
SELECT catalog.decide_customer_price('a5000000-0000-0000-0000-000000000001','colleague',true,NULL,'Synthetic initial');
RESET SESSION AUTHORIZATION;
SQL
# The preceding sales suite now creates three orders/reservations. Assert
# that exact fixture contract, then compare complete ordered row snapshots.
tenant='a0000000-0000-0000-0000-000000000001'
[[ "$(psql_ci -c "SELECT count(*) FROM sales.orders WHERE tenant_id='$tenant'")" == 3 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE tenant_id='$tenant'")" == 3 ]]
snapshot_orders() {
 psql_ci -c "SELECT COALESCE(jsonb_agg(to_jsonb(o) ORDER BY o.order_id),'[]'::jsonb) FROM sales.orders o WHERE o.tenant_id='$tenant'"
}
snapshot_reservations() {
 psql_ci -c "SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.reservation_id),'[]'::jsonb) FROM inventory.reservations r WHERE r.tenant_id='$tenant'"
}
orders_before=$(snapshot_orders)
reservations_before=$(snapshot_reservations)
assert_no_checkout_change() {
 [[ "$(snapshot_orders)" == "$orders_before" ]] || { echo 'FAIL stale checkout changed order rows'; return 1; }
 [[ "$(snapshot_reservations)" == "$reservations_before" ]] || { echo 'FAIL stale checkout changed reservation rows'; return 1; }
}
deadline=$(psql_ci -c "SELECT clock_timestamp()+interval '1 hour'")
race_stale() {
 local phase="$1" mutation="$2" expected="$3" first second ready=0 blocked=0
 psql_ci >"$tmp/$phase-first" 2>&1 <<SQL &
SET application_name='upc_pricing_${phase}_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='30s';
$mutation
SELECT pg_sleep(5);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_pricing_${phase}_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$phase-second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_pricing_${phase}_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='30s';
SELECT sales.create_checkout('stale-$phase','a5000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000001','a6000000-0000-0000-0000-000000000001','in_person','$deadline',jsonb_build_array(jsonb_build_object('variant_id','a3000000-0000-0000-0000-000000000001','quantity',1,'expected_unit_price',$expected)));
SQL
 second=$!
 for i in {1..35}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_pricing_${phase}_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first" || { cat "$tmp/$phase-first"; return 1; }
 if wait "$second"; then cat "$tmp/$phase-second"; echo "FAIL stale checkout"; return 1; fi
 [[ "$blocked" == 1 ]]
 grep -q '23514: Price changed' "$tmp/$phase-second" || { cat "$tmp/$phase-second"; return 1; }
 assert_no_checkout_change
}
race_stale revoke "SELECT catalog.decide_customer_price('a5000000-0000-0000-0000-000000000001','colleague',false,NULL,'Synthetic revoke');" 850
race_stale change "UPDATE catalog.price_entries SET valid_during=tstzrange(lower(valid_during),clock_timestamp(),'[)') WHERE variant_id='a3000000-0000-0000-0000-000000000001' AND price_list_id='a6000000-0000-0000-0000-000000000001'; INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) SELECT tenant_id,variant_id,price_list_id,1100,tstzrange(upper(valid_during),NULL,'[)') FROM catalog.price_entries WHERE variant_id='a3000000-0000-0000-0000-000000000001' AND price_list_id='a6000000-0000-0000-0000-000000000001';" 1000
assert_no_checkout_change
[[ "$(psql_ci -c "SELECT count(*) FROM sales.orders WHERE tenant_id='$tenant'")" == 3 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM inventory.reservations WHERE tenant_id='$tenant'")" == 3 ]]
echo 'PASS pricing concurrency: observed competing locks, stale checkout rejected after eligibility revoke and price change, no new hold'

#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_reorder_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_reorder_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0680000-0000-0000-0000-000000000099','reorder-race','Synthetic reorder race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0680000-0000-0000-0000-000000000099','test','reorder-race');
INSERT INTO iam.memberships VALUES('a0680000-0000-0000-0000-000000000099','b0680000-0000-0000-0000-000000000099',now());
INSERT INTO iam.db_principals VALUES('upc_reorder_race','a0680000-0000-0000-0000-000000000099','b0680000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0680000-0000-0000-0000-000000000099','c0680000-0000-0000-0000-000000000099','reorder-race');
INSERT INTO iam.role_grants SELECT 'a0680000-0000-0000-0000-000000000099','c0680000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('inventory.read','inventory.reorder.write');
INSERT INTO iam.membership_roles VALUES('a0680000-0000-0000-0000-000000000099','b0680000-0000-0000-0000-000000000099','c0680000-0000-0000-0000-000000000099');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0680000-0000-0000-0000-000000000099',module_id,true,'b0680000-0000-0000-0000-000000000099','Synthetic test' FROM platform.modules WHERE module_key='inventory';
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name)
 VALUES('a0680000-0000-0000-0000-000000000099','f0680000-0000-0000-0000-000000000099','race','Synthetic');
INSERT INTO catalog.products(tenant_id,product_id,name,kind)
 VALUES('a0680000-0000-0000-0000-000000000099','d0680000-0000-0000-0000-000000000099','Synthetic','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name)
 VALUES('a0680000-0000-0000-0000-000000000099','e0680000-0000-0000-0000-000000000099','d0680000-0000-0000-0000-000000000099','reorder-race','Synthetic');
SQL
w=f0680000-0000-0000-0000-000000000099
v=e0680000-0000-0000-0000-000000000099
race() {
 local label="$1" first_args="$2" second_args="$3"
 local first second ready=0 blocked=0 first_id second_id
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_reorder_${label}_first';
SET SESSION AUTHORIZATION upc_reorder_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT inventory.set_reorder_policy('$w','$v',$first_args);
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_reorder_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]] || { cat "$tmp/$label.first"; exit 1; }
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_reorder_${label}_second';
SET SESSION AUTHORIZATION upc_reorder_race;
SET statement_timeout='25s';
SELECT inventory.set_reorder_policy('$w','$v',$second_args);
SQL
 second=$!
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_reorder_${label}_second' AND wait_event_type='Lock' AND wait_event='advisory' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"; wait "$second"
 [[ "$blocked" == 1 ]] || { cat "$tmp/$label.second"; exit 1; }
 first_id=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first" | head -1)
 second_id=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second" | head -1)
 [[ "$first_id" == "$second_id" ]] || exit 1
}
race create "0,5" "0,5"
race update "3,7" "4,8"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(reorder_point=4 AND suggested_units=8) FROM inventory.reorder_policies WHERE tenant_id='a0680000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE tenant_id='a0680000-0000-0000-0000-000000000099' AND entity_type='inventory.reorder_policies' AND event_type='insert'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM ops.audit_events WHERE tenant_id='a0680000-0000-0000-0000-000000000099' AND entity_type='inventory.reorder_policies' AND event_type='update'")" == t ]]
[[ "$(psql_ci -c "SELECT NOT EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id='a0680000-0000-0000-0000-000000000099') AND NOT EXISTS(SELECT 1 FROM procurement.purchase_orders WHERE tenant_id='a0680000-0000-0000-0000-000000000099')")" == t ]]
echo 'PASS reorder configuration concurrency: actual advisory waits, one policy, serialized differing updates, exact audit, no stock or procurement effect'

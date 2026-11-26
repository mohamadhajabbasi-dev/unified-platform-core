#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_stock_alert_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_stock_alert_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0730000-0000-0000-0000-000000000099','stock-alert-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0730000-0000-0000-0000-000000000099','test','stock-alert-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0730000-0000-0000-0000-000000000099','b0730000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_stock_alert_race','a0730000-0000-0000-0000-000000000099','b0730000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0730000-0000-0000-0000-000000000099','c0730000-0000-0000-0000-000000000099','stock-alert-race');
INSERT INTO iam.role_grants SELECT 'a0730000-0000-0000-0000-000000000099','c0730000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('crm.read','catalog.read','inventory.read','catalog.stock_alerts.read','catalog.stock_alerts.write');
INSERT INTO iam.membership_roles VALUES('a0730000-0000-0000-0000-000000000099','b0730000-0000-0000-0000-000000000099','c0730000-0000-0000-0000-000000000099');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES('a0730000-0000-0000-0000-000000000099','d0730000-0000-0000-0000-000000000099','Synthetic');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES('a0730000-0000-0000-0000-000000000099','f0730000-0000-0000-0000-000000000099','Synthetic','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES('a0730000-0000-0000-0000-000000000099','e0730000-0000-0000-0000-000000000099','f0730000-0000-0000-0000-000000000099','stock-alert-1','Synthetic');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason) SELECT 'a0730000-0000-0000-0000-000000000099',module_id,true,'b0730000-0000-0000-0000-000000000099','Synthetic' FROM platform.modules WHERE module_key IN ('crm','catalog','inventory');
SQL
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_stock_alert_first';
SET SESSION AUTHORIZATION upc_stock_alert_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000099','e0730000-0000-0000-0000-000000000099',true);
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_stock_alert_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_stock_alert_second';
SET SESSION AUTHORIZATION upc_stock_alert_race;
SET statement_timeout='25s';
SELECT catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000099','e0730000-0000-0000-0000-000000000099',true);
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name='upc_stock_alert_second' AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(is_requested) FROM catalog.stock_alert_subscriptions WHERE tenant_id='a0730000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE tenant_id='a0730000-0000-0000-0000-000000000099' AND entity_type='catalog.stock_alert_subscriptions'")" == t ]]
# Second actual contention: a removal holds its transaction while reactivation waits.
psql_ci >"$tmp/remove" 2>&1 <<'SQL' &
SET application_name='upc_stock_alert_remove';
SET SESSION AUTHORIZATION upc_stock_alert_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000099','e0730000-0000-0000-0000-000000000099',false);
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_stock_alert_remove' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/reactivate" 2>&1 <<'SQL' &
SET application_name='upc_stock_alert_reactivate';
SET SESSION AUTHORIZATION upc_stock_alert_race;
SET statement_timeout='25s';
SELECT catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000099','e0730000-0000-0000-0000-000000000099',true);
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name='upc_stock_alert_reactivate' AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
[[ "$a" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/remove")" ]]
[[ "$a" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/reactivate")" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(is_requested) FROM catalog.stock_alert_subscriptions WHERE tenant_id='a0730000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=3 AND count(*) FILTER(WHERE e.event_type='insert')=1 AND count(*) FILTER(WHERE e.event_type='update')=2 AND bool_and(e.actor_user_id='b0730000-0000-0000-0000-000000000099' AND e.entity_id=f.subscription_id) FROM ops.audit_events e JOIN catalog.stock_alert_subscriptions f USING(tenant_id) WHERE e.tenant_id='a0730000-0000-0000-0000-000000000099' AND e.entity_type='catalog.stock_alert_subscriptions'")" == t ]]
echo 'PASS stock alert request concurrency: observed two actual advisory waits, same ID, serialized remove/reactivate, one relation and three audits'

#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_merge_review_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_merge_review_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0760000-0000-0000-0000-000000000099','merge-review-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0760000-0000-0000-0000-000000000099','test','merge-review-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0760000-0000-0000-0000-000000000099','b0760000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_merge_review_race','a0760000-0000-0000-0000-000000000099','b0760000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0760000-0000-0000-0000-000000000099','c0760000-0000-0000-0000-000000000099','merge-review-race');
INSERT INTO iam.role_grants SELECT 'a0760000-0000-0000-0000-000000000099','c0760000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('crm.read','crm.merge_reviews.read','crm.merge_reviews.write');
INSERT INTO iam.membership_roles VALUES('a0760000-0000-0000-0000-000000000099','b0760000-0000-0000-0000-000000000099','c0760000-0000-0000-0000-000000000099');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES('a0760000-0000-0000-0000-000000000099','d0760000-0000-0000-0000-000000000098','Synthetic A'),('a0760000-0000-0000-0000-000000000099','d0760000-0000-0000-0000-000000000099','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason) SELECT 'a0760000-0000-0000-0000-000000000099',module_id,true,'b0760000-0000-0000-0000-000000000099','Synthetic' FROM platform.modules WHERE module_key='crm';
SQL
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_merge_review_first';
SET SESSION AUTHORIZATION upc_merge_review_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000098','d0760000-0000-0000-0000-000000000099');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_merge_review_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_merge_review_second';
SET SESSION AUTHORIZATION upc_merge_review_race;
SET statement_timeout='25s';
SELECT crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000099','d0760000-0000-0000-0000-000000000098');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name='upc_merge_review_second' AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(customer_low_id='d0760000-0000-0000-0000-000000000098' AND customer_high_id='d0760000-0000-0000-0000-000000000099') FROM crm.customer_merge_reviews WHERE tenant_id='a0760000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM crm.customers WHERE tenant_id='a0760000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(e.entity_id=v.review_id AND e.actor_user_id='b0760000-0000-0000-0000-000000000099' AND e.event_type='insert') FROM ops.audit_events e JOIN crm.customer_merge_reviews v USING(tenant_id) WHERE e.tenant_id='a0760000-0000-0000-0000-000000000099' AND e.entity_type='crm.customer_merge_reviews'")" == t ]]
echo 'PASS customer merge review concurrency: observed advisory wait for reversed pair, one stable request and one audit, both customers retained'

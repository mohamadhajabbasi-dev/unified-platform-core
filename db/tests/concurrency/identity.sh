#!/usr/bin/env bash
set -euo pipefail
# Only the disposable CI container; no host connection strings.
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_concurrent_test LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime,upc_identity_writer TO upc_concurrent_test;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES ('70000000-0000-0000-0000-000000000001','concurrency-test','Synthetic concurrency');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES ('71000000-0000-0000-0000-000000000001','test','concurrency');
INSERT INTO iam.memberships VALUES ('70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001',now());
INSERT INTO iam.db_principals VALUES ('upc_concurrent_test','70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','writer');
INSERT INTO iam.role_grants VALUES ('70000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001','crm.write');
INSERT INTO iam.membership_roles VALUES ('70000000-0000-0000-0000-000000000001','71000000-0000-0000-0000-000000000001','72000000-0000-0000-0000-000000000001');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '70000000-0000-0000-0000-000000000001',module_id,true,'71000000-0000-0000-0000-000000000001','Synthetic test' FROM platform.modules WHERE module_key='crm';
SQL
# Hold first transaction open; observe its actual advisory lock before starting contender.
psql_ci >"$tmp/first" <<'SQL' &
SET application_name='upc_concurrency_first';
SET SESSION AUTHORIZATION upc_concurrent_test;
BEGIN;
SET LOCAL statement_timeout='20s';
SELECT crm.resolve_verified_customer('channel','test','concurrent-key','Synthetic');
SELECT pg_sleep(4);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_concurrency_first' AND l.locktype='advisory' AND l.granted")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" <<'SQL' &
SET application_name='upc_concurrency_second';
SET SESSION AUTHORIZATION upc_concurrent_test;
SET statement_timeout='20s';
SELECT crm.resolve_verified_customer('channel','test','concurrent-key','Synthetic');
SQL
second=$!
blocked=0
for i in {1..30}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_concurrency_second' AND l.locktype='advisory' AND NOT l.granted")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM crm.customers WHERE tenant_id='70000000-0000-0000-0000-000000000001'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM crm.customer_identifiers WHERE tenant_id='70000000-0000-0000-0000-000000000001'")" == 1 ]]
echo 'PASS concurrency: observed advisory lock contention, same customer ID, one profile and identity'
# All fixtures disappear when CI destroys the service container.

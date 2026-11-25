#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_location_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_location_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0610000-0000-0000-0000-000000000099','location-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0610000-0000-0000-0000-000000000099','test','location-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0610000-0000-0000-0000-000000000099','b0610000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_location_race','a0610000-0000-0000-0000-000000000099','b0610000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0610000-0000-0000-0000-000000000099','c0610000-0000-0000-0000-000000000099','location-race');
INSERT INTO iam.role_grants VALUES
 ('a0610000-0000-0000-0000-000000000099','c0610000-0000-0000-0000-000000000099','tenant.locations.read'),
 ('a0610000-0000-0000-0000-000000000099','c0610000-0000-0000-0000-000000000099','tenant.locations.write');
INSERT INTO iam.membership_roles VALUES('a0610000-0000-0000-0000-000000000099','b0610000-0000-0000-0000-000000000099','c0610000-0000-0000-0000-000000000099');
SQL
# An actual competing unique-index insert must wait for the first transaction.
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_loc_first';
SET SESSION AUTHORIZATION upc_location_race;
BEGIN;
SET LOCAL statement_timeout='25s';
INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind)
 VALUES(iam.current_tenant_id(),'same-key','First','branch') RETURNING location_id;
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_loc_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_loc_second';
SET SESSION AUTHORIZATION upc_location_race;
SET statement_timeout='25s';
INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind)
 VALUES(iam.current_tenant_id(),'same-key','Second','store');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity b JOIN pg_stat_activity a ON a.pid=ANY(pg_blocking_pids(b.pid)) WHERE b.application_name='upc_loc_second' AND a.application_name='upc_loc_first' AND b.wait_event_type='Lock'")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then cat "$tmp/second"; exit 1; fi
[[ "$blocked" == 1 ]]
grep -Eq '23505.*duplicate key' "$tmp/second"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(display_name='First') FROM core.business_locations WHERE tenant_id='a0610000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(e.entity_id=l.location_id AND e.actor_user_id='b0610000-0000-0000-0000-000000000099' AND e.event_type='insert') FROM ops.audit_events e JOIN core.business_locations l USING(tenant_id) WHERE e.tenant_id='a0610000-0000-0000-0000-000000000099' AND e.entity_type='core.business_locations'")" == t ]]
echo 'PASS business location concurrency: observed competing unique-index lock, SQLSTATE 23505, one location and one exact audit'

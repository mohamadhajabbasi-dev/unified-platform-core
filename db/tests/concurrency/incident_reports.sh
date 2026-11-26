#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_incident_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_incident_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0700000-0000-0000-0000-000000000099','incident-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0700000-0000-0000-0000-000000000099','test','incident-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0700000-0000-0000-0000-000000000099','b0700000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_incident_race','a0700000-0000-0000-0000-000000000099','b0700000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0700000-0000-0000-0000-000000000099','c0700000-0000-0000-0000-000000000099','incident-race');
INSERT INTO iam.role_grants VALUES
 ('a0700000-0000-0000-0000-000000000099','c0700000-0000-0000-0000-000000000099','ops.incidents.read'),
 ('a0700000-0000-0000-0000-000000000099','c0700000-0000-0000-0000-000000000099','ops.incidents.write');
INSERT INTO iam.membership_roles VALUES('a0700000-0000-0000-0000-000000000099','b0700000-0000-0000-0000-000000000099','c0700000-0000-0000-0000-000000000099');
SQL
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_incident_first';
SET SESSION AUTHORIZATION upc_incident_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_incident_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_incident_second';
SET SESSION AUTHORIZATION upc_incident_race;
SET statement_timeout='25s';
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability');
SQL
second=$!
psql_ci >"$tmp/conflict" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_incident_conflict';
SET SESSION AUTHORIZATION upc_incident_race;
SET statement_timeout='25s';
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','security');
SQL
conflict=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name IN ('upc_incident_second','upc_incident_conflict') AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 2 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
if wait "$conflict"; then cat "$tmp/conflict"; exit 1; fi
[[ "$blocked" == 1 ]]
grep -Eq '23505.*Incident report key conflict' "$tmp/conflict"
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(report_kind='availability') FROM ops.incidents WHERE tenant_id='a0700000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(e.entity_id=s.incident_id AND e.actor_user_id='b0700000-0000-0000-0000-000000000099' AND e.event_type='insert') FROM ops.audit_events e JOIN ops.incidents s USING(tenant_id) WHERE e.tenant_id='a0700000-0000-0000-0000-000000000099' AND e.entity_type='ops.incidents'")" == t ]]
echo 'PASS incident report concurrency: two observed advisory waiters, exact retry same ID, conflict 23505, one incident report and one audit'

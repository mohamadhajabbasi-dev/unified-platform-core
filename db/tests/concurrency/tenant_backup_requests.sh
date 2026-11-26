#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_backup_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_backup_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0710000-0000-0000-0000-000000000099','backup-race-a','Synthetic race A'),('a0710000-0000-0000-0000-000000000098','backup-race-b','Synthetic race B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0710000-0000-0000-0000-000000000099','test','backup-race');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES('upc_backup_race','b0710000-0000-0000-0000-000000000099',true);
SQL
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_backup_first';
SET SESSION AUTHORIZATION upc_backup_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT ops.request_tenant_backup('a0710000-0000-0000-0000-000000000099','d0710000-0000-0000-0000-000000000001');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_backup_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_backup_second';
SET SESSION AUTHORIZATION upc_backup_race;
SET statement_timeout='25s';
SELECT ops.request_tenant_backup('a0710000-0000-0000-0000-000000000099','d0710000-0000-0000-0000-000000000001');
SQL
second=$!
psql_ci >"$tmp/conflict" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_backup_conflict';
SET SESSION AUTHORIZATION upc_backup_race;
SET statement_timeout='25s';
SELECT ops.request_tenant_backup('a0710000-0000-0000-0000-000000000098','d0710000-0000-0000-0000-000000000001');
SQL
conflict=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name IN ('upc_backup_second','upc_backup_conflict') AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 2 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
if wait "$conflict"; then cat "$tmp/conflict"; exit 1; fi
[[ "$blocked" == 1 ]]
grep -Eq '23505.*Backup request key conflict' "$tmp/conflict"
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(tenant_id='a0710000-0000-0000-0000-000000000099' AND requested_by='b0710000-0000-0000-0000-000000000099') FROM ops.tenant_backup_jobs WHERE request_key='d0710000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(e.entity_id=b.job_id AND e.actor_user_id=b.requested_by AND e.event_type='insert') FROM ops.audit_events e JOIN ops.tenant_backup_jobs b USING(tenant_id) WHERE b.request_key='d0710000-0000-0000-0000-000000000001' AND e.entity_type='ops.tenant_backup_jobs'")" == t ]]
echo 'PASS tenant backup request concurrency: two observed advisory waiters, exact retry, cross-tenant conflict 23505, one request and one audit'

#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_queue_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_queue_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0640000-0000-0000-0000-000000000099','queue-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0640000-0000-0000-0000-000000000099','test','queue-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0640000-0000-0000-0000-000000000099','b0640000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_queue_race','a0640000-0000-0000-0000-000000000099','b0640000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0640000-0000-0000-0000-000000000099','c0640000-0000-0000-0000-000000000099','queue-race');
INSERT INTO iam.role_grants SELECT 'a0640000-0000-0000-0000-000000000099','c0640000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('crm.engagement.read','crm.engagement.write','crm.queues.write');
INSERT INTO iam.membership_roles VALUES('a0640000-0000-0000-0000-000000000099','b0640000-0000-0000-0000-000000000099','c0640000-0000-0000-0000-000000000099');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES('a0640000-0000-0000-0000-000000000099','d0640000-0000-0000-0000-000000000099','Synthetic');
INSERT INTO crm.support_tickets(tenant_id,ticket_id,ticket_key,customer_id,subject) VALUES('a0640000-0000-0000-0000-000000000099','e0640000-0000-0000-0000-000000000099','RACE','d0640000-0000-0000-0000-000000000099','Synthetic');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0640000-0000-0000-0000-000000000099',module_id,true,'b0640000-0000-0000-0000-000000000099','Synthetic approval' FROM platform.modules WHERE module_key='crm';
SQL
race() {
 local label="$1" query="$2" conflict_query="${3:-}" second_query="${4:-$2}" first second conflict ready=0 blocked=0 expected=1
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_queue_${label}_first';
SET SESSION AUTHORIZATION upc_queue_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT $query;
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_queue_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_queue_${label}_second';
SET SESSION AUTHORIZATION upc_queue_race;
SET statement_timeout='25s';
SELECT $second_query;
SQL
 second=$!
 if [[ -n "$conflict_query" ]]; then
  expected=2
  psql_ci >"$tmp/$label.conflict" 2>&1 <<SQL &
\\set VERBOSITY verbose
SET application_name='upc_queue_${label}_conflict';
SET SESSION AUTHORIZATION upc_queue_race;
SET statement_timeout='25s';
SELECT $conflict_query;
SQL
  conflict=$!
 fi
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('upc_queue_${label}_second','upc_queue_${label}_conflict') AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == "$expected" ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 if [[ -n "$conflict_query" ]]; then
  if wait "$conflict"; then cat "$tmp/$label.conflict"; exit 1; fi
  grep -Eq '23505.*Queue key conflict' "$tmp/$label.conflict"
 fi
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second")
 [[ "$a" == "$b" ]]
}
race create "crm.register_service_queue('same-key','Synthetic')" "crm.register_service_queue('same-key','Different')"
q=$(grep -E '^[0-9a-f-]{36}$' "$tmp/create.first")
q2=$(psql_ci -c "SET SESSION AUTHORIZATION upc_queue_race; SELECT crm.register_service_queue('second','Synthetic second')")
ticket=e0640000-0000-0000-0000-000000000099
race assign "crm.set_ticket_queue('$ticket','$q')"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(queue_id='$q') FROM crm.support_tickets WHERE ticket_id='$ticket'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='crm.support_tickets' AND entity_id='$ticket'")" == t ]]
race oppose "crm.set_ticket_queue('$ticket','$q2')" "" "crm.set_ticket_queue('$ticket',NULL)"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(queue_id IS NULL) FROM crm.support_tickets WHERE ticket_id='$ticket'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=3 FROM ops.audit_events WHERE entity_type='crm.support_tickets' AND entity_id='$ticket' AND event_type='update'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM crm.service_queues WHERE tenant_id='a0640000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM ops.audit_events WHERE tenant_id='a0640000-0000-0000-0000-000000000099' AND entity_type='crm.service_queues' AND event_type='insert'")" == t ]]
echo 'PASS CRM queue concurrency: observed create and ticket locks, exact replay, serialized opposing assignments and exact audit'

#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_tag_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_tag_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0630000-0000-0000-0000-000000000099','tag-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0630000-0000-0000-0000-000000000099','test','tag-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0630000-0000-0000-0000-000000000099','b0630000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_tag_race','a0630000-0000-0000-0000-000000000099','b0630000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0630000-0000-0000-0000-000000000099','c0630000-0000-0000-0000-000000000099','tag-race');
INSERT INTO iam.role_grants SELECT 'a0630000-0000-0000-0000-000000000099','c0630000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('crm.read','crm.tags.read','crm.tags.write');
INSERT INTO iam.membership_roles VALUES('a0630000-0000-0000-0000-000000000099','b0630000-0000-0000-0000-000000000099','c0630000-0000-0000-0000-000000000099');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES('a0630000-0000-0000-0000-000000000099','d0630000-0000-0000-0000-000000000099','Synthetic');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0630000-0000-0000-0000-000000000099',module_id,true,'b0630000-0000-0000-0000-000000000099','Synthetic approval' FROM platform.modules WHERE module_key='crm';
SQL
race() {
 local label="$1" query="$2" conflict_query="${3:-}" first second conflict ready=0 blocked=0 expected=1
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_tag_${label}_first';
SET SESSION AUTHORIZATION upc_tag_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT $query;
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_tag_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_tag_${label}_second';
SET SESSION AUTHORIZATION upc_tag_race;
SET statement_timeout='25s';
SELECT $query;
SQL
 second=$!
 if [[ -n "$conflict_query" ]]; then
  expected=2
  psql_ci >"$tmp/$label.conflict" 2>&1 <<SQL &
\\set VERBOSITY verbose
SET application_name='upc_tag_${label}_conflict';
SET SESSION AUTHORIZATION upc_tag_race;
SET statement_timeout='25s';
SELECT $conflict_query;
SQL
  conflict=$!
 fi
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('upc_tag_${label}_second','upc_tag_${label}_conflict') AND wait_event_type='Lock' AND wait_event='advisory' AND cardinality(pg_blocking_pids(pid))>0")" == "$expected" ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 if [[ -n "$conflict_query" ]]; then
  if wait "$conflict"; then cat "$tmp/$label.conflict"; exit 1; fi
  grep -Eq '23505.*Tag key conflict' "$tmp/$label.conflict"
 fi
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second")
 [[ "$a" == "$b" ]]
}
race create "crm.register_customer_tag('same-key','Synthetic')" "crm.register_customer_tag('same-key','Different')"
tag=$(grep -E '^[0-9a-f-]{36}$' "$tmp/create.first")
race attach "crm.set_customer_tag('d0630000-0000-0000-0000-000000000099','$tag',true)"
[[ "$(psql_ci -c "SELECT count(*)=1 FROM crm.customer_tags WHERE tenant_id='a0630000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(is_active) FROM crm.customer_tag_links WHERE tenant_id='a0630000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND count(DISTINCT entity_id)=2 FROM ops.audit_events WHERE tenant_id='a0630000-0000-0000-0000-000000000099' AND entity_type LIKE 'crm.customer_tag%' AND event_type='insert'")" == t ]]
echo 'PASS CRM tag concurrency: observed create and attach advisory waits, same IDs, conflicting payload rejected, one tag/link and exact audit counts'

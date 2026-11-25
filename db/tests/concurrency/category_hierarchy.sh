#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_tree_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_tree_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0650000-0000-0000-0000-000000000099','tree-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0650000-0000-0000-0000-000000000099','test','tree-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0650000-0000-0000-0000-000000000099','b0650000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_tree_race','a0650000-0000-0000-0000-000000000099','b0650000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0650000-0000-0000-0000-000000000099','c0650000-0000-0000-0000-000000000099','tree-race');
INSERT INTO iam.role_grants SELECT 'a0650000-0000-0000-0000-000000000099','c0650000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('catalog.read','catalog.write');
INSERT INTO iam.membership_roles VALUES('a0650000-0000-0000-0000-000000000099','b0650000-0000-0000-0000-000000000099','c0650000-0000-0000-0000-000000000099');
INSERT INTO catalog.categories(tenant_id,category_id,name) VALUES
 ('a0650000-0000-0000-0000-000000000099','d0650000-0000-0000-0000-000000000001','A'),
 ('a0650000-0000-0000-0000-000000000099','d0650000-0000-0000-0000-000000000002','B'),
 ('a0650000-0000-0000-0000-000000000099','d0650000-0000-0000-0000-000000000003','C');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0650000-0000-0000-0000-000000000099',module_id,true,'b0650000-0000-0000-0000-000000000099','Synthetic approval' FROM platform.modules WHERE module_key='catalog';
SQL
race() {
 local label="$1" query="$2" conflict_query="${3:-}" second_query="${4:-$2}" first second conflict ready=0 blocked=0 expected=1
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_tree_${label}_first';
SET SESSION AUTHORIZATION upc_tree_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT $query;
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_tree_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_tree_${label}_second';
SET SESSION AUTHORIZATION upc_tree_race;
SET statement_timeout='25s';
SELECT $second_query;
SQL
 second=$!
 if [[ -n "$conflict_query" ]]; then
  expected=2
  psql_ci >"$tmp/$label.conflict" 2>&1 <<SQL &
\\set VERBOSITY verbose
SET application_name='upc_tree_${label}_conflict';
SET SESSION AUTHORIZATION upc_tree_race;
SET statement_timeout='25s';
SELECT $conflict_query;
SQL
  conflict=$!
 fi
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('upc_tree_${label}_second','upc_tree_${label}_conflict') AND wait_event_type='Lock' AND wait_event='advisory' AND cardinality(pg_blocking_pids(pid))>0")" == "$expected" ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 if [[ -n "$conflict_query" ]]; then
  if wait "$conflict"; then cat "$tmp/$label.conflict"; exit 1; fi
  grep -Eq '23514.*Category cycle or invalid ancestry' "$tmp/$label.conflict"
 fi
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second")
 [[ "$a" == "$b" ]]
}
a=d0650000-0000-0000-0000-000000000001
b=d0650000-0000-0000-0000-000000000002
c=d0650000-0000-0000-0000-000000000003
race first "catalog.set_category_parent('$a','$b')" "catalog.set_category_parent('$b','$a')"
race second "catalog.set_category_parent('$b','$c')" "catalog.set_category_parent('$c','$a')"
[[ "$(psql_ci -c "SELECT count(*)=3 AND count(*) FILTER(WHERE parent_category_id IS NULL)=1 FROM catalog.categories WHERE tenant_id='a0650000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM catalog.categories WHERE category_id='$a' AND parent_category_id='$b'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM catalog.categories WHERE category_id='$b' AND parent_category_id='$c'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM ops.audit_events WHERE tenant_id='a0650000-0000-0000-0000-000000000099' AND entity_type='catalog.categories' AND event_type='update'")" == t ]]
echo 'PASS category concurrency: actual tenant graph advisory waits, exact replay, two-edge and three-edge cycle rejection, exact committed audit'

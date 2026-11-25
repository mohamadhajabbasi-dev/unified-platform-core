#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_attr_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_attr_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0670000-0000-0000-0000-000000000099','attr-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0670000-0000-0000-0000-000000000099','test','attr-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0670000-0000-0000-0000-000000000099','b0670000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_attr_race','a0670000-0000-0000-0000-000000000099','b0670000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0670000-0000-0000-0000-000000000099','c0670000-0000-0000-0000-000000000099','attr-race');
INSERT INTO iam.role_grants SELECT 'a0670000-0000-0000-0000-000000000099','c0670000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('catalog.read','catalog.write');
INSERT INTO iam.membership_roles VALUES('a0670000-0000-0000-0000-000000000099','b0670000-0000-0000-0000-000000000099','c0670000-0000-0000-0000-000000000099');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES('a0670000-0000-0000-0000-000000000099','d0670000-0000-0000-0000-000000000099','Synthetic','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0670000-0000-0000-0000-000000000099','e0670000-0000-0000-0000-000000000001','d0670000-0000-0000-0000-000000000099','A','A'),
 ('a0670000-0000-0000-0000-000000000099','e0670000-0000-0000-0000-000000000002','d0670000-0000-0000-0000-000000000099','B','B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0670000-0000-0000-0000-000000000099',module_id,true,'b0670000-0000-0000-0000-000000000099','Synthetic approval' FROM platform.modules WHERE module_key='catalog';
SQL
race() {
 local label="$1" query="$2" conflict_query="${3:-}" second_query="${4:-$2}" first second conflict ready=0 blocked=0 expected=1
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_attr_${label}_first';
SET SESSION AUTHORIZATION upc_attr_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT $query;
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_attr_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_attr_${label}_second';
SET SESSION AUTHORIZATION upc_attr_race;
SET statement_timeout='25s';
SELECT $second_query;
SQL
 second=$!
 if [[ -n "$conflict_query" ]]; then
  expected=2
  psql_ci >"$tmp/$label.conflict" 2>&1 <<SQL &
\\set VERBOSITY verbose
SET application_name='upc_attr_${label}_conflict';
SET SESSION AUTHORIZATION upc_attr_race;
SET statement_timeout='25s';
SELECT $conflict_query;
SQL
  conflict=$!
 fi
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('upc_attr_${label}_second','upc_attr_${label}_conflict') AND wait_event_type='Lock' AND wait_event='advisory' AND cardinality(pg_blocking_pids(pid))>0")" == "$expected" ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 if [[ -n "$conflict_query" ]]; then
  if wait "$conflict"; then cat "$tmp/$label.conflict"; exit 1; fi
  grep -Eq '23505.*Attribute key conflict' "$tmp/$label.conflict"
 fi
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second")
 [[ "$a" == "$b" ]]
}
race define "catalog.register_attribute_definition('color','Color')" "catalog.register_attribute_definition('color','Different')"
attr=$(grep -E '^[0-9a-f-]{36}$' "$tmp/define.first")
v=e0670000-0000-0000-0000-000000000001
race assign "catalog.set_variant_attribute_value('$v','$attr','Black')"
id=$(grep -E '^[0-9a-f-]{36}$' "$tmp/assign.first")
race update "catalog.set_variant_attribute_value('$v','$attr','Blue')" "" "catalog.set_variant_attribute_value('$v','$attr','White')"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(assignment_id='$id' AND variant_id='$v' AND attribute_id='$attr' AND value_text='White') FROM catalog.variant_attribute_values WHERE tenant_id='a0670000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM catalog.attribute_definitions WHERE tenant_id='a0670000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE entity_type='catalog.attribute_definitions' AND entity_id='$attr' AND event_type='insert'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=3 AND count(*) FILTER(WHERE event_type='insert')=1 AND count(*) FILTER(WHERE event_type='update')=2 FROM ops.audit_events WHERE entity_type='catalog.variant_attribute_values' AND entity_id='$id'")" == t ]]
echo 'PASS attribute concurrency: observed definition/assignment advisory waits, exact retries, key conflict, serialized differing updates and exact audit'

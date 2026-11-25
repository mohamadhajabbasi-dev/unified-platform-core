#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_bar_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_bar_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0660000-0000-0000-0000-000000000099','bar-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0660000-0000-0000-0000-000000000099','test','bar-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0660000-0000-0000-0000-000000000099','b0660000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_bar_race','a0660000-0000-0000-0000-000000000099','b0660000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0660000-0000-0000-0000-000000000099','c0660000-0000-0000-0000-000000000099','bar-race');
INSERT INTO iam.role_grants SELECT 'a0660000-0000-0000-0000-000000000099','c0660000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('catalog.read','catalog.write');
INSERT INTO iam.membership_roles VALUES('a0660000-0000-0000-0000-000000000099','b0660000-0000-0000-0000-000000000099','c0660000-0000-0000-0000-000000000099');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES('a0660000-0000-0000-0000-000000000099','d0660000-0000-0000-0000-000000000099','Synthetic','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0660000-0000-0000-0000-000000000099','e0660000-0000-0000-0000-000000000001','d0660000-0000-0000-0000-000000000099','A','A'),
 ('a0660000-0000-0000-0000-000000000099','e0660000-0000-0000-0000-000000000002','d0660000-0000-0000-0000-000000000099','B','B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0660000-0000-0000-0000-000000000099',module_id,true,'b0660000-0000-0000-0000-000000000099','Synthetic approval' FROM platform.modules WHERE module_key='catalog';
SQL
race() {
 local label="$1" query="$2" conflict_query="${3:-}" first second conflict ready=0 blocked=0 expected=1
 psql_ci >"$tmp/$label.first" 2>&1 <<SQL &
SET application_name='upc_bar_${label}_first';
SET SESSION AUTHORIZATION upc_bar_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT $query;
SELECT pg_sleep(6);
COMMIT;
SQL
 first=$!
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_bar_${label}_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 psql_ci >"$tmp/$label.second" 2>&1 <<SQL &
SET application_name='upc_bar_${label}_second';
SET SESSION AUTHORIZATION upc_bar_race;
SET statement_timeout='25s';
SELECT $query;
SQL
 second=$!
 if [[ -n "$conflict_query" ]]; then
  expected=2
  psql_ci >"$tmp/$label.conflict" 2>&1 <<SQL &
\\set VERBOSITY verbose
SET application_name='upc_bar_${label}_conflict';
SET SESSION AUTHORIZATION upc_bar_race;
SET statement_timeout='25s';
SELECT $conflict_query;
SQL
  conflict=$!
 fi
 for i in {1..40}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name IN ('upc_bar_${label}_second','upc_bar_${label}_conflict') AND wait_event_type='Lock' AND wait_event='advisory' AND cardinality(pg_blocking_pids(pid))>0")" == "$expected" ]]; then blocked=1; break; fi
  sleep 0.1
 done
 wait "$first"
 wait "$second"
 if [[ -n "$conflict_query" ]]; then
  if wait "$conflict"; then cat "$tmp/$label.conflict"; exit 1; fi
  grep -Eq '23505.*Barcode code conflict' "$tmp/$label.conflict"
 fi
 [[ "$blocked" == 1 ]]
 local a b
 a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.first")
 b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/$label.second")
 [[ "$a" == "$b" ]]
}
race create "catalog.register_variant_barcode('e0660000-0000-0000-0000-000000000001','00042')" "catalog.register_variant_barcode('e0660000-0000-0000-0000-000000000002','00042')"
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(variant_id='e0660000-0000-0000-0000-000000000001' AND barcode_code='00042') FROM catalog.variant_barcodes WHERE tenant_id='a0660000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE tenant_id='a0660000-0000-0000-0000-000000000099' AND entity_type='catalog.variant_barcodes' AND event_type='insert'")" == t ]]
echo 'PASS barcode concurrency: observed exact code advisory waits, identical retry ID, conflicting variant rejected and one audit'

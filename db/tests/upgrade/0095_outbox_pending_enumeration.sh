#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0094_dormant_fixed_assets.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 AND (n.nspname,p.proname)<>('ops','pending_outbox_events') ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0095_outbox_pending_enumeration.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0095_outbox_pending_enumeration.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0095 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0950000-0000-0000-0000-000000000003','late-commit','Synthetic late commit');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003','late-test');
SQL
# A records first but remains uncommitted while B commits and gets a synthetic receipt.
psql_ci > "$tmp/early" 2>&1 <<'SQL' &
SET application_name='upc_pending_early';
BEGIN;
SET LOCAL statement_timeout='40s';
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES('a0950000-0000-0000-0000-000000000003','d0950000-0000-0000-0000-000000000011','Early synthetic');
SELECT pg_sleep(12);
COMMIT;
SQL
early=$!
ready=0
for i in {1..50}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_pending_early' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',500)")" == 0 ]]
psql_ci <<'SQL'
BEGIN;
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES('a0950000-0000-0000-0000-000000000003','d0950000-0000-0000-0000-000000000012','Later synthetic');
COMMIT;
SQL
[[ "$(psql_ci -c "SELECT count(*) FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',500)")" == 1 ]]
psql_ci <<'SQL'
INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id)
 SELECT 'a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',p.event_id
 FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',500) p;
SQL
[[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_pending_early' AND wait_event='PgSleep'")" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',500)")" == 0 ]]
wait "$early"
[[ "$(psql_ci -c "SELECT count(*)=1 AND min(p.recorded_at)<(SELECT e.recorded_at FROM ops.outbox_events e JOIN ops.outbox_consumer_receipts r USING(tenant_id,event_id) WHERE r.tenant_id='a0950000-0000-0000-0000-000000000003' AND r.consumer_id='c0950000-0000-0000-0000-000000000003') FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000003','c0950000-0000-0000-0000-000000000003',500) p")" == t ]]
echo 'PASS late commit enumeration: earlier-recorded event remains pending after later-recorded event committed and received'

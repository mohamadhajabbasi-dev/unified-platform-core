#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0089_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 88 ]]
python3 - "$tmp/identity.sql" "$tmp/details.sql" <<'PY'
from pathlib import Path
import sys
prefix=Path('db/tests/0001_core_crm.sql').read_text().split('SET SESSION AUTHORIZATION')[0]
assert 'INSERT INTO iam.db_principals' in prefix
Path(sys.argv[1]).write_text(prefix+'\nCOMMIT;\n')
lines=Path('db/tests/0087_catalog_details_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[2]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/identity.sql"
psql_ci < "$tmp/details.sql"
psql_ci -c "INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001')"
[[ "$(psql_ci -c "SELECT EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001') AND (SELECT count(*) FROM iam.user_auth_sessions)=1")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND (schemaname,tablename) NOT IN (('ops','outbox_consumers'),('ops','outbox_consumer_receipts')) ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam') AND p.prokind='f' ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='ops' AND c.relkind='r' AND c.relname NOT IN ('outbox_consumers','outbox_consumer_receipts') ORDER BY c.relname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0089_dormant_outbox_receipts.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT (SELECT count(*) FROM ops.outbox_consumers)=0 AND (SELECT count(*) FROM ops.outbox_consumer_receipts)=0")" == t ]]
psql_ci < db/tests/0089_dormant_outbox_receipts.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0089 upgrade: prior rows including 0088 session metadata, existing outbox/IAM functions and ACLs preserved; no receipt backfill'
psql_ci -c "INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES('a0870000-0000-0000-0000-000000000001','c0890000-0000-0000-0000-000000000099','race-test')"
# Synthetic bootstrap-only race; no actual acknowledgement or delivery worker.
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_receipt_first';
BEGIN;
SET LOCAL statement_timeout='30s';
INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id)
 SELECT tenant_id,'c0890000-0000-0000-0000-000000000099',event_id FROM ops.outbox_events
 WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY event_id LIMIT 1;
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_receipt_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts")" == 0 ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_receipt_second';
SET statement_timeout='30s';
INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id)
 SELECT tenant_id,'c0890000-0000-0000-0000-000000000099',event_id FROM ops.outbox_events
 WHERE tenant_id='a0870000-0000-0000-0000-000000000001' ORDER BY event_id LIMIT 1;
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_receipt_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then echo 'FAIL duplicate concurrent receipt accepted'; exit 1; fi
[[ "$blocked" == 1 ]]
grep -q '23505' "$tmp/second"
[[ "$(psql_ci -c "SELECT count(*) FROM ops.outbox_consumer_receipts")" == 1 ]]
snapshot > "$tmp/after_race"
cmp "$tmp/before" "$tmp/after_race"
echo 'PASS dormant outbox receipt concurrency: actual unique-key lock, invisible uncommitted receipt, one committed receipt and rejected duplicate'

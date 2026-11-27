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
 [[ "$(basename "$migration")" == 0088_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 87 ]]
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
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND (schemaname,tablename)<>('iam','user_auth_sessions') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='iam' AND p.prokind='f' ORDER BY p.proname,pg_get_function_identity_arguments(p.oid);
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0088_dormant_auth_sessions.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*) FROM iam.user_auth_sessions")" == 0 ]]
psql_ci < db/tests/0088_dormant_auth_sessions.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0088 upgrade: all previous rows, existing IAM function definitions and ACLs preserved; no session backfill'
# Synthetic bootstrap race only; no runtime writer or trust policy.
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_authmeta_first';
BEGIN;
SET LOCAL statement_timeout='30s';
INSERT INTO iam.user_auth_sessions(tenant_id,user_id,session_id) VALUES('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','c0880000-0000-0000-0000-000000000099');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_authmeta_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM iam.user_auth_sessions")" == 0 ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_authmeta_second';
SET statement_timeout='30s';
INSERT INTO iam.user_auth_sessions(tenant_id,user_id,session_id) VALUES('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','c0880000-0000-0000-0000-000000000099');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_authmeta_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then echo 'FAIL duplicate concurrent insert accepted'; exit 1; fi
[[ "$blocked" == 1 ]]
grep -q '23505' "$tmp/second"
[[ "$(psql_ci -c "SELECT count(*) FROM iam.user_auth_sessions")" == 1 ]]
snapshot > "$tmp/after_race"
cmp "$tmp/before" "$tmp/after_race"
echo 'PASS dormant auth session concurrency: observed actual unique-key lock, invisible uncommitted row, one committed metadata row and rejected duplicate'

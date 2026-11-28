#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
bash db/tests/upgrade/0101_dormant_webhook_registration.sh
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%' AND (schemaname,tablename)<>('ops','notifications') ORDER BY schemaname,tablename
\gexec
SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),pg_get_functiondef(p.oid),p.proowner,p.proacl
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND p.prokind='f'
 ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);
SELECT n.nspname,c.relname,c.relacl,c.relrowsecurity,c.relforcerowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN ('ops','iam','catalog','inventory','procurement','finance','sales') AND c.relkind='r' AND (n.nspname,c.relname)<>('ops','notifications') ORDER BY n.nspname,c.relname;
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check FROM pg_policies ORDER BY schemaname,tablename,policyname;
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0102_dormant_notification_intent.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
psql_ci < db/tests/0102_dormant_notification_intent.sql
snapshot > "$tmp/after_test"
cmp "$tmp/before" "$tmp/after_test"
echo 'PASS committed pre-0102 upgrade: previous rows, functions, ACLs and RLS policies unchanged'
psql_ci <<'SQL'
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1020000-0000-0000-0000-000000000001','notification-test-a','Synthetic A'),
 ('a1020000-0000-0000-0000-000000000002','notification-test-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1020000-0000-0000-0000-000000000001','test','notifmeta-a'),
 ('b1020000-0000-0000-0000-000000000002','test','notifmeta-b'),
 ('b1020000-0000-0000-0000-000000000003','test','notifmeta-platform'),
 ('b1020000-0000-0000-0000-000000000004','test','notifmeta-extra');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a1020000-0000-0000-0000-000000000001','b1020000-0000-0000-0000-000000000001'),
 ('a1020000-0000-0000-0000-000000000002','b1020000-0000-0000-0000-000000000002'),
 ('a1020000-0000-0000-0000-000000000001','b1020000-0000-0000-0000-000000000004'),
 ('a1020000-0000-0000-0000-000000000002','b1020000-0000-0000-0000-000000000001');
-- Synthetic event fixtures only; no capture or delivery behavior implied.
INSERT INTO ops.outbox_events(tenant_id,event_id,event_kind) VALUES
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000001','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000001','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000002','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000011','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000011','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000012','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000012','catalog.price_entry.changed');
SQL
a='a1020000-0000-0000-0000-000000000001'
b='a1020000-0000-0000-0000-000000000002'
u='b1020000-0000-0000-0000-000000000001'
ux='b1020000-0000-0000-0000-000000000004'
snapshot > "$tmp/before_races"
for scenario in rollback commit; do
 if [[ "$scenario" == rollback ]]; then outcome=ROLLBACK; e='c1020000-0000-0000-0000-000000000011'; else outcome=COMMIT; e='c1020000-0000-0000-0000-000000000012'; fi
 insert_a="INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES('$a','$e','$u') RETURNING user_id"
 where="tenant_id='$a' AND event_id='$e' AND user_id='$u'"
 psql_ci > "$tmp/first-$scenario" 2>&1 <<SQL &
SET application_name='upc_notification_first';
BEGIN;
SET LOCAL statement_timeout='40s';
$insert_a;
SELECT pg_sleep(12);
$outcome;
SQL
 first=$!
 ready=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_notification_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
  sleep 0.1
 done
 [[ "$ready" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.notifications WHERE $where")" == 0 ]]
 psql_ci > "$tmp/second-$scenario" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_notification_second';
SET statement_timeout='40s';
$insert_a;
SQL
 second=$!
 blocked=0
 for i in {1..50}; do
  if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a JOIN pg_stat_activity b ON b.pid=ANY(pg_blocking_pids(a.pid)) WHERE a.application_name='upc_notification_second' AND b.application_name='upc_notification_first'")" == 1 ]]; then blocked=1; break; fi
  sleep 0.1
 done
 [[ "$blocked" == 1 ]]
 psql_ci -c "SET statement_timeout='3s'; INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES('$a','$e','$ux'),('$b','$e','$u')"
 wait "$first"
 if [[ "$scenario" == commit ]]; then
  if wait "$second"; then echo 'FAIL duplicate notification intent accepted'; exit 1; fi
  grep -q '23505:' "$tmp/second-$scenario"
 else
  wait "$second"
  grep -qx "$u" "$tmp/second-$scenario"
 fi
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.notifications WHERE $where")" == 1 ]]
 [[ "$(psql_ci -c "SELECT count(*) FROM ops.notifications WHERE tenant_id IN('$a','$b') AND event_id='$e'")" == 3 ]]
done
[[ "$(psql_ci -c "SELECT count(*) FROM ops.notifications WHERE tenant_id IN('$a','$b')")" == 6 ]]
snapshot > "$tmp/after_races"
cmp "$tmp/before_races" "$tmp/after_races"
echo 'PASS concurrent dormant notification intents: actual duplicate blockers in commit and rollback, independent recipient and tenant inserts, one intent per scope and all prior facts unchanged'

#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service container required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
CREATE ROLE upc_revision_race LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_revision_race;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES('a0740000-0000-0000-0000-000000000099','revision-race','Synthetic race');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0740000-0000-0000-0000-000000000099','test','revision-race');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('a0740000-0000-0000-0000-000000000099','b0740000-0000-0000-0000-000000000099');
INSERT INTO iam.db_principals VALUES('upc_revision_race','a0740000-0000-0000-0000-000000000099','b0740000-0000-0000-0000-000000000099');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES('a0740000-0000-0000-0000-000000000099','c0740000-0000-0000-0000-000000000099','revision-race');
INSERT INTO iam.role_grants SELECT 'a0740000-0000-0000-0000-000000000099','c0740000-0000-0000-0000-000000000099',permission_key FROM iam.permissions WHERE permission_key IN ('content.read','content.write','content.revisions.read','content.revisions.capture');
INSERT INTO iam.membership_roles VALUES('a0740000-0000-0000-0000-000000000099','b0740000-0000-0000-0000-000000000099','c0740000-0000-0000-0000-000000000099');
INSERT INTO content.articles(tenant_id,article_id,slug,title,body) VALUES('a0740000-0000-0000-0000-000000000099','d0740000-0000-0000-0000-000000000099','synthetic-race','Synthetic','Initial');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason) SELECT 'a0740000-0000-0000-0000-000000000099',module_id,true,'b0740000-0000-0000-0000-000000000099','Synthetic' FROM platform.modules WHERE module_key='content';
SQL
psql_ci >"$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_revision_first';
SET SESSION AUTHORIZATION upc_revision_race;
BEGIN;
SET LOCAL statement_timeout='25s';
SELECT content.capture_article_revision('d0740000-0000-0000-0000-000000000099');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_revision_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_revision_second';
SET SESSION AUTHORIZATION upc_revision_race;
SET statement_timeout='25s';
SELECT content.capture_article_revision('d0740000-0000-0000-0000-000000000099');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity a WHERE a.application_name='upc_revision_second' AND a.wait_event_type='Lock' AND a.wait_event='advisory' AND cardinality(pg_blocking_pids(a.pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
a=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
b=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ "$a" == "$b" ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM content.article_revisions WHERE tenant_id='a0740000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.audit_events WHERE tenant_id='a0740000-0000-0000-0000-000000000099' AND entity_type='content.article_revisions'")" == t ]]
# Capture after a committed editor change gives a distinct immutable version.
psql_ci >"$tmp/changed" 2>&1 <<'SQL'
SET SESSION AUTHORIZATION upc_revision_race;
UPDATE content.articles SET body='Changed' WHERE article_id='d0740000-0000-0000-0000-000000000099';
SELECT content.capture_article_revision('d0740000-0000-0000-0000-000000000099');
SQL
[[ "$a" != "$(grep -E '^[0-9a-f-]{36}$' "$tmp/changed")" ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND count(*) FILTER(WHERE snapshot->>'body'='Initial')=1 AND count(*) FILTER(WHERE snapshot->>'body'='Changed')=1 FROM content.article_revisions WHERE tenant_id='a0740000-0000-0000-0000-000000000099'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 AND count(DISTINCT e.entity_id)=2 AND bool_and(e.actor_user_id='b0740000-0000-0000-0000-000000000099' AND e.event_type='insert') FROM ops.audit_events e JOIN content.article_revisions r ON r.tenant_id=e.tenant_id AND r.revision_id=e.entity_id WHERE e.tenant_id='a0740000-0000-0000-0000-000000000099' AND e.entity_type='content.article_revisions'")" == t ]]
echo 'PASS article revision concurrency: actual advisory wait, one identical snapshot and audit; changed committed text produces distinct immutable snapshot'

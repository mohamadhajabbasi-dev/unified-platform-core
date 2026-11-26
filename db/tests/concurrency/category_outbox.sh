#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/fixture.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0086_category_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/fixture.sql"
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_categorybox_first';
SET SESSION AUTHORIZATION upc_categorybox_a;
BEGIN;
SET LOCAL statement_timeout='30s';
SELECT catalog.set_category_parent('c0860000-0000-0000-0000-000000000012',NULL);
DELETE FROM catalog.product_categories WHERE category_id='c0860000-0000-0000-0000-000000000012';
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_categorybox_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=25 FROM ops.outbox_events WHERE tenant_id='a0860000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT EXISTS(SELECT 1 FROM catalog.categories WHERE category_id='c0860000-0000-0000-0000-000000000012' AND parent_category_id='c0860000-0000-0000-0000-000000000011') AND EXISTS(SELECT 1 FROM catalog.product_categories WHERE category_id='c0860000-0000-0000-0000-000000000012')")" == t ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_categorybox_second';
SET SESSION AUTHORIZATION upc_categorybox_a;
SET statement_timeout='30s';
SELECT catalog.set_category_parent('c0860000-0000-0000-0000-000000000012',NULL);
DELETE FROM catalog.product_categories WHERE category_id='c0860000-0000-0000-0000-000000000012';
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_categorybox_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=27 FROM ops.outbox_events WHERE tenant_id='a0860000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=11 FROM ops.outbox_events WHERE tenant_id='a0860000-0000-0000-0000-000000000002'")" == t ]]
[[ "$(psql_ci -c "SELECT EXISTS(SELECT 1 FROM catalog.categories WHERE category_id='c0860000-0000-0000-0000-000000000012' AND parent_category_id IS NULL) AND NOT EXISTS(SELECT 1 FROM catalog.product_categories WHERE category_id='c0860000-0000-0000-0000-000000000012') AND (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0860000-0000-0000-0000-000000000001' AND event_kind='catalog.category.changed')=5 AND (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0860000-0000-0000-0000-000000000001' AND event_kind='catalog.product_category.changed')=4 AND (SELECT count(*) FROM ops.audit_events WHERE tenant_id='a0860000-0000-0000-0000-000000000001' AND entity_type='catalog.categories')=2")" == t ]]
echo 'PASS category outbox concurrency: actual hierarchy lock, invisible uncommitted detach and unlink, exact retry emits one per source and one audit'

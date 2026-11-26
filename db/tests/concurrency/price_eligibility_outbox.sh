#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/fixture.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0084_price_eligibility_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/fixture.sql"
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_eligbox_first';
SET SESSION AUTHORIZATION upc_eligbox_a;
BEGIN;
SET LOCAL statement_timeout='30s';
SELECT catalog.decide_customer_price('d0840000-0000-0000-0000-000000000021','wholesale',true,NULL,'Concurrent approval');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_eligbox_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=11 FROM ops.outbox_events WHERE tenant_id='a0840000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=2 FROM catalog.customer_price_decisions WHERE tenant_id='a0840000-0000-0000-0000-000000000001'")" == t ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_eligbox_second';
SET SESSION AUTHORIZATION upc_eligbox_a;
SET statement_timeout='30s';
SELECT catalog.decide_customer_price('d0840000-0000-0000-0000-000000000021','wholesale',false,NULL,'Concurrent revoke');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_eligbox_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=13 FROM ops.outbox_events WHERE tenant_id='a0840000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=6 FROM ops.outbox_events WHERE tenant_id='a0840000-0000-0000-0000-000000000002'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=4 AND (array_agg(approved ORDER BY decision_id DESC))[1:2]=ARRAY[false,true] FROM catalog.customer_price_decisions WHERE tenant_id='a0840000-0000-0000-0000-000000000001'")" == t ]]
echo 'PASS price-eligibility outbox concurrency: actual pricing lock, invisible uncommitted approval and event, two ordered decisions and two events'

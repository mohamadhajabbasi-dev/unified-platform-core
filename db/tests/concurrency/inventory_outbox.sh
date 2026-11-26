#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/fixture.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0079_inventory_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/fixture.sql"
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_stockbox_first';
SET SESSION AUTHORIZATION upc_stockbox_a;
BEGIN;
SET LOCAL statement_timeout='30s';
SELECT inventory.adjust_stock('e0790000-0000-0000-0000-000000000001','d0790000-0000-0000-0000-000000000001',2,'race-stock','Race');
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_stockbox_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=6 FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=0 FROM inventory.stock_ledger WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND adjustment_key='race-stock'")" == t ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
SET application_name='upc_stockbox_second';
SET SESSION AUTHORIZATION upc_stockbox_a;
SET statement_timeout='30s';
SELECT inventory.adjust_stock('e0790000-0000-0000-0000-000000000001','d0790000-0000-0000-0000-000000000001',2,'race-stock','Race');
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_stockbox_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
id1=$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")
id2=$(grep -E '^[0-9a-f-]{36}$' "$tmp/second")
[[ -n "$id1" && "$id1" == "$id2" ]]
[[ "$(psql_ci -c "SELECT count(*)=3 FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND event_kind='inventory.stock_ledger.changed'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=7 FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000002'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(quantity_delta=2) FROM inventory.stock_ledger WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND adjustment_key='race-stock'")" == t ]]
echo 'PASS inventory outbox concurrency: observed lock contention, invisible uncommitted stock and event, exact retry one movement and one event'

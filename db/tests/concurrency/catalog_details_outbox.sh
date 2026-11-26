#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/fixture.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0087_catalog_details_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/fixture.sql"
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_detailbox_first';
SET SESSION AUTHORIZATION upc_detailbox_a;
BEGIN;
SET LOCAL statement_timeout='30s';
UPDATE catalog.product_media SET display_order=5 WHERE media_id='c0870000-0000-0000-0000-000000000051';
UPDATE catalog.brands SET name='Concurrent brand' WHERE brand_id='c0870000-0000-0000-0000-000000000031';
UPDATE catalog.measure_units SET quantity_precision=4 WHERE unit_id='c0870000-0000-0000-0000-000000000041';
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_detailbox_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=33 FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT EXISTS(SELECT 1 FROM catalog.product_media WHERE media_id='c0870000-0000-0000-0000-000000000051' AND display_order=1) AND EXISTS(SELECT 1 FROM catalog.brands WHERE brand_id='c0870000-0000-0000-0000-000000000031' AND name='Renamed brand') AND EXISTS(SELECT 1 FROM catalog.measure_units WHERE unit_id='c0870000-0000-0000-0000-000000000041' AND quantity_precision=2)")" == t ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_detailbox_second';
SET SESSION AUTHORIZATION upc_detailbox_a;
SET statement_timeout='30s';
UPDATE catalog.product_media SET display_order=5 WHERE media_id='c0870000-0000-0000-0000-000000000051';
UPDATE catalog.brands SET name='Concurrent brand' WHERE brand_id='c0870000-0000-0000-0000-000000000031';
UPDATE catalog.measure_units SET quantity_precision=4 WHERE unit_id='c0870000-0000-0000-0000-000000000041';
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_detailbox_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
wait "$second"
[[ "$blocked" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=36 FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=16 FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000002'")" == t ]]
[[ "$(psql_ci -c "SELECT EXISTS(SELECT 1 FROM catalog.product_media WHERE media_id='c0870000-0000-0000-0000-000000000051' AND display_order=5) AND EXISTS(SELECT 1 FROM catalog.brands WHERE brand_id='c0870000-0000-0000-0000-000000000031' AND name='Concurrent brand') AND EXISTS(SELECT 1 FROM catalog.measure_units WHERE unit_id='c0870000-0000-0000-0000-000000000041' AND quantity_precision=4) AND (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001' AND event_kind='catalog.brand.changed')=3 AND (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001' AND event_kind='catalog.measure_unit.changed')=3 AND (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0870000-0000-0000-0000-000000000001' AND event_kind='catalog.product_media.changed')=3")" == t ]]
echo 'PASS catalog details outbox concurrency: actual row lock, invisible uncommitted media brand and unit changes, identical updates emit one per source'

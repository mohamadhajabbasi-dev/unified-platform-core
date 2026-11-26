#!/usr/bin/env bash
set -euo pipefail
: "$PG_CONTAINER"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/fixture.sql" <<'PY'
from pathlib import Path
import sys
lines=Path('db/tests/0083_price_tier_outbox.sql').read_text().splitlines()
assert lines.count('ROLLBACK;')==1 and lines[-2]=='ROLLBACK;'
lines[-2]='COMMIT;'
Path(sys.argv[1]).write_text('\n'.join(lines)+'\n')
PY
psql_ci < "$tmp/fixture.sql"
psql_ci > "$tmp/first" 2>&1 <<'SQL' &
SET application_name='upc_tierbox_first';
SET SESSION AUTHORIZATION upc_tierbox_a;
BEGIN;
SET LOCAL statement_timeout='30s';
INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(iam.current_tenant_id(),'d0830000-0000-0000-0000-000000000011',int8range(10,20,'[)'),70);
SELECT pg_sleep(7);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_tierbox_first' AND wait_event='PgSleep'")" == 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=9 FROM ops.outbox_events WHERE tenant_id='a0830000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=0 FROM catalog.price_quantity_tiers WHERE price_id='d0830000-0000-0000-0000-000000000011' AND lower(quantity_range)=10")" == t ]]
psql_ci > "$tmp/second" 2>&1 <<'SQL' &
\set VERBOSITY verbose
SET application_name='upc_tierbox_second';
SET SESSION AUTHORIZATION upc_tierbox_a;
SET statement_timeout='30s';
INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(iam.current_tenant_id(),'d0830000-0000-0000-0000-000000000011',int8range(10,20,'[)'),70);
SQL
second=$!
blocked=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_stat_activity WHERE application_name='upc_tierbox_second' AND wait_event_type='Lock' AND cardinality(pg_blocking_pids(pid))>0")" == 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first"
if wait "$second"; then cat "$tmp/second"; exit 1; fi
grep -q "23P01" "$tmp/second"
[[ "$blocked" == 1 ]]
[[ "$(psql_ci -c "SELECT count(*)=10 FROM ops.outbox_events WHERE tenant_id='a0830000-0000-0000-0000-000000000001'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=5 FROM ops.outbox_events WHERE tenant_id='a0830000-0000-0000-0000-000000000002'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 AND bool_and(tier_amount=70) FROM catalog.price_quantity_tiers WHERE price_id='d0830000-0000-0000-0000-000000000011' AND lower(quantity_range)=10")" == t ]]
echo 'PASS price-tier outbox concurrency: actual blocking, invisible uncommitted tier and event, one accepted tier, rejected overlap no event'

#!/usr/bin/env bash
# A separate disposable CI service, never the foundation job's database.
set -euo pipefail
: "${PG_CONTAINER:?dedicated upgrade CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 id=$(basename "$migration")
 if [[ "$id" == 0058_* ]]; then break; fi
 echo "Upgrade baseline applying $migration"
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 57 ]]
[[ "$(psql_ci -c "SELECT to_regclass('sales.return_items') IS NOT NULL AND NOT has_table_privilege('upc_sales_executor','sales.return_items','INSERT')")" == t ]]
# Reuse the existing actual legacy API fixture, changing ONLY the final
# rollback to commit in this disposable job. Never edit the source fixture.
python3 - "$tmp/legacy.sql" <<'PY'
from pathlib import Path
import sys
source = Path("db/tests/0054_order_return_capacity.sql").read_text()
lines = source.splitlines()
indices = [i for i, line in enumerate(lines) if line == "ROLLBACK;"]
assert len(indices) == 1 and indices[0] == len(lines) - 2
assert lines[-1].startswith(r"\echo PASS read-only order return capacity:")
assert "ret:=sales.receive_full_return_allocated(" in source
assert "ret:=sales.receive_full_return(" in source
lines[indices[0]] = "COMMIT;"
lines[-1] = r"\echo UPGRADE_BASELINE actual pre-0058 ordinary and traced full returns committed"
Path(sys.argv[1]).write_text("\n".join(lines) + "\n")
PY
psql_ci < "$tmp/legacy.sql"
[[ "$(psql_ci -c "SELECT count(*)=2 FROM sales.returns")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=5 AND sum(quantity_delta)=7 FROM inventory.stock_ledger WHERE adjustment_key LIKE 'sales-return:%'")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=0 FROM sales.return_items")" == t ]]
# Compare exact deterministic row contents in every user table, including
# journals, memberships, decisions and immutable facts; synthetic data only.
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb) FROM %I.%I AS t;',schemaname||'.'||tablename,schemaname,tablename)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema')
 AND schemaname NOT LIKE 'pg_%' ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0058_canonical_full_return_receipts.sql
snapshot > "$tmp/after_migration"
cmp "$tmp/before" "$tmp/after_migration"
[[ "$(psql_ci -c "SELECT has_table_privilege('upc_sales_executor','sales.return_items','INSERT') AND NOT has_table_privilege('upc_runtime','sales.return_items','INSERT')")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE h sales.returns%ROWTYPE; alloc jsonb;
BEGIN
 SELECT * INTO STRICT h FROM sales.returns WHERE request_key='capacity-ordinary-return';
 IF sales.receive_full_return(h.order_id,h.request_key,h.reason) IS DISTINCT FROM h.return_id
 OR NOT EXISTS(SELECT 1 FROM finance.order_return_capacity(h.order_id) e WHERE e.sold_quantity=2 AND e.returned_quantity=2 AND e.remaining_quantity=0 AND e.return_id=h.return_id)
 THEN RAISE EXCEPTION 'FAIL ordinary legacy exact retry'; END IF;
 BEGIN PERFORM sales.receive_full_return(h.order_id,h.request_key,'Conflict'); RAISE EXCEPTION 'FAIL legacy payload conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM sales.receive_full_return(h.order_id,'upgrade-different-key',h.reason); RAISE EXCEPTION 'FAIL duplicate legacy receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 SELECT * INTO STRICT h FROM sales.returns WHERE request_key='trace-evidence-return';
 SELECT jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity)) INTO alloc
 FROM sales.order_items i JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id) WHERE i.order_id=h.order_id;
 IF sales.receive_full_return_allocated(h.order_id,h.request_key,h.reason,alloc) IS DISTINCT FROM h.return_id
 OR (SELECT count(*) FROM finance.order_return_capacity(h.order_id))<>4
 OR (SELECT sum(returned_quantity) FROM finance.order_return_capacity(h.order_id))<>5
 OR EXISTS(SELECT 1 FROM finance.order_return_capacity(h.order_id) e WHERE e.remaining_quantity<>0 OR e.return_id IS DISTINCT FROM h.return_id)
 THEN RAISE EXCEPTION 'FAIL traced legacy exact retry'; END IF;
 BEGIN PERFORM sales.receive_full_return_allocated(h.order_id,h.request_key,h.reason,NULL); RAISE EXCEPTION 'FAIL legacy trace mismatch'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM sales.return_items) THEN RAISE EXCEPTION 'FAIL implicit legacy backfill'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SELECT order_id AS legacy_order FROM sales.returns WHERE request_key='capacity-ordinary-return' \gset
SET SESSION AUTHORIZATION upc_inv_reader;
SELECT set_config('upc.test_legacy_order', :'legacy_order',false);
DO $$ BEGIN
 BEGIN PERFORM sales.receive_full_return(current_setting('upc.test_legacy_order')::uuid,'capacity-ordinary-return','Inspected');
  RAISE EXCEPTION 'FAIL unauthorized legacy retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 BEGIN PERFORM sales.receive_full_return(current_setting('upc.test_legacy_order')::uuid,'capacity-ordinary-return','Inspected');
  RAISE EXCEPTION 'FAIL foreign tenant legacy retry'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SQL
snapshot > "$tmp/after_retry"
cmp "$tmp/before" "$tmp/after_retry"
echo 'UPGRADE_LEGACY_RETRY exact ordinary/traced retries preserve all table rows, no backfill'
# Actual new full return coexists with committed old history.
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE oid uuid; rid uuid; n bigint; q numeric;
BEGIN
 oid:=sales.create_checkout('upgrade-new-order','95000000-0000-0000-0000-000000000001',
 '94000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','in_person',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id','93000000-0000-0000-0000-000000000005','quantity',2,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','upgrade-new-payment',2000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 rid:=sales.receive_full_return(oid,'upgrade-new-return','Inspected');
 IF (SELECT count(*) FROM sales.return_items)<>1 OR NOT EXISTS(SELECT 1 FROM sales.return_items WHERE return_id=rid AND order_id=oid AND received_quantity=2 AND disposition='sellable')
 OR NOT EXISTS(SELECT 1 FROM finance.order_return_capacity(oid) e WHERE e.return_id=rid AND e.sold_quantity=2 AND e.returned_quantity=2 AND e.remaining_quantity=0)
 THEN RAISE EXCEPTION 'FAIL new receipt after upgrade'; END IF;
 SELECT count(*),sum(quantity_delta) INTO n,q FROM inventory.stock_ledger;
 IF sales.receive_full_return(oid,'upgrade-new-return','Inspected') IS DISTINCT FROM rid
 OR (SELECT count(*) FROM sales.return_items)<>1 OR (SELECT count(*) FROM inventory.stock_ledger)<>n
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger) IS DISTINCT FROM q
 THEN RAISE EXCEPTION 'FAIL new receipt retry after upgrade'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.returns)<>3 OR (SELECT count(*) FROM sales.return_items)<>1
 OR EXISTS(SELECT 1 FROM sales.return_items ri JOIN sales.returns h USING(tenant_id,return_id) WHERE h.request_key IN ('trace-evidence-return','capacity-ordinary-return'))
 OR (SELECT count(*) FROM inventory.stock_ledger WHERE adjustment_key LIKE 'sales-return:%')<>6
 OR (SELECT count(*) FROM finance.journal_entries)<>1
 OR EXISTS(SELECT 1 FROM sales.refunds) OR EXISTS(SELECT 1 FROM finance.movement_cost_facts)
 THEN RAISE EXCEPTION 'FAIL legacy/new coexistence'; END IF;
END $$;
SQL
echo 'PASS actual 0057-to-0058 upgrade: committed legacy ordinary/traced returns, exact read-only replay, no backfill, new writer coexistence'

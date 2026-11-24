#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
psql_ci <<'SQL'
GRANT upc_supplier_document_verifier,upc_supplier_payment_verifier TO upc_sale_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,permission_key FROM iam.roles CROSS JOIN iam.permissions WHERE role_key='sales-race-editor' AND permission_key LIKE 'finance.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0000000-0000-0000-0000-000000000001',module_id,true,'a1000000-0000-0000-0000-000000000001','Synthetic finance' FROM platform.modules WHERE module_key='finance';
SET SESSION AUTHORIZATION upc_sale_a;
INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (iam.current_tenant_id(),'aa000000-0000-0000-0000-000000000001','inv','Inventory','asset','IRR'),
 (iam.current_tenant_id(),'aa000000-0000-0000-0000-000000000002','ap','Payable','liability','IRR'),
 (iam.current_tenant_id(),'aa000000-0000-0000-0000-000000000003','cash','Cash','asset','IRR');
SELECT finance.open_period('race period',(clock_timestamp() AT TIME ZONE 'UTC')::date,(clock_timestamp() AT TIME ZONE 'UTC')::date+30);
SELECT finance.record_supplier_invoice((SELECT purchase_id FROM procurement.purchase_orders WHERE request_key='race-po'),'RACE-INV',(clock_timestamp() AT TIME ZONE 'UTC')::date,(clock_timestamp() AT TIME ZONE 'UTC')::date+7,500,'IRR',decode(repeat('ab',32),'hex'),'aa000000-0000-0000-0000-000000000001','aa000000-0000-0000-0000-000000000002');
RESET SESSION AUTHORIZATION;
SQL
iid=$(psql_ci -c "SELECT invoice_id FROM finance.supplier_invoices WHERE invoice_ref='RACE-INV'")
paid=$(psql_ci -c "SELECT clock_timestamp()")
stmt() { echo "SELECT finance.record_supplier_settlement('$iid','bank','synthetic','$1',$2,'IRR','$paid',decode(repeat('cd',32),'hex'),'aa000000-0000-0000-0000-000000000003');"; }
psql_ci >"$tmp/first" 2>&1 <<SQL &
SET application_name='upc_settlement_first';
SET SESSION AUTHORIZATION upc_sale_a;
BEGIN;
SET LOCAL statement_timeout='25s';
$(stmt PAY-A 300)
SELECT pg_sleep(5);
COMMIT;
SQL
first=$!
ready=0
for i in {1..40}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_settlement_first' AND l.locktype='advisory' AND l.granted")" -ge 1 ]]; then ready=1; break; fi
 sleep 0.1
done
[[ "$ready" == 1 ]]
psql_ci >"$tmp/second" 2>&1 <<SQL &
\set VERBOSITY verbose
SET application_name='upc_settlement_second';
SET SESSION AUTHORIZATION upc_sale_a;
SET statement_timeout='25s';
$(stmt PAY-B 300)
SQL
second=$!
blocked=0
for i in {1..35}; do
 if [[ "$(psql_ci -c "SELECT count(*) FROM pg_locks l JOIN pg_stat_activity a USING(pid) WHERE a.application_name='upc_settlement_second' AND l.locktype='advisory' AND NOT l.granted")" -ge 1 ]]; then blocked=1; break; fi
 sleep 0.1
done
wait "$first" || { cat "$tmp/first"; exit 1; }
if wait "$second"; then cat "$tmp/second"; echo "FAIL competing overpayment"; exit 1; fi
[[ "$blocked" == 1 ]]
grep -q '23514: Settlement exceeds payable' "$tmp/second" || { cat "$tmp/second"; exit 1; }
retry=$(psql_ci <<SQL
SET SESSION AUTHORIZATION upc_sale_a;
$(stmt PAY-A 300)
SQL
)
[[ "$retry" == "$(grep -E '^[0-9a-f-]{36}$' "$tmp/first")" ]]
[[ "$(psql_ci -c "SELECT count(*) FROM finance.supplier_settlements WHERE invoice_id='$iid'")" == 1 ]]
[[ "$(psql_ci -c "SELECT outstanding FROM finance.supplier_payables WHERE invoice_id='$iid'")" == 200.0000 ]]
[[ "$(psql_ci -c "SELECT count(*) FROM finance.journal_entries WHERE supplier_settlement_id IS NOT NULL")" == 1 ]]
echo 'PASS supplier settlement concurrency: competing distinct references, overpayment rejected, exact retry and one journal'

-- 0042: extend existing readiness diagnostics with exact cost replay and journal amounts.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE OR REPLACE FUNCTION finance.inventory_cost_issues(p_warehouse uuid,p_variant uuid)
RETURNS TABLE(movement_id uuid,issue_code text)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); pol finance.valuation_policies%ROWTYPE; issue_count bigint; x record; actual_sources jsonb; cf_row finance.movement_cost_facts%ROWTYPE;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Inventory cost reconciliation access denied' USING ERRCODE='42501'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL THEN RAISE EXCEPTION 'Warehouse and variant required' USING ERRCODE='22023'; END IF;
 SELECT * INTO pol FROM finance.valuation_policies vp WHERE vp.tenant_id=t AND vp.variant_id=p_variant;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM inventory.warehouses w WHERE w.tenant_id=t AND w.warehouse_id=p_warehouse)
 THEN RAISE EXCEPTION 'Configured valuation scope unavailable' USING ERRCODE='23503'; END IF;
 RETURN QUERY
 WITH moves AS (
 SELECT l.movement_id AS mid,l.quantity_delta AS qty,l.reservation_id,l.adjustment_key,l.lot_id,l.serial_id,l.allocation_id,
 cf.movement_id AS captured_mid,cf.value_delta AS cost,
 rb.movement_id AS receipt_mid,rb.invoice_id,rb.currency AS receipt_currency,rb.agreed_cost,rb.quantity AS receipt_qty,
 sj.entry_id AS sale_entry,rj.entry_id AS return_entry,sj.currency AS sale_currency,rj.currency AS return_currency,
 ij.entry_id AS invoice_entry,ij.currency AS invoice_currency,iv.amount AS invoice_amount,
 orig.entry_id AS original_sale_entry,orig.currency AS original_sale_currency,
 ti.incoming_movement_id AS transfer_in,ti.outgoing_movement_id AS transfer_in_peer,
 tout.outgoing_movement_id AS transfer_out,tout.incoming_movement_id AS transfer_out_peer,
 ci.value_delta AS incoming_peer_value,co.value_delta AS outgoing_peer_value
 FROM inventory.stock_ledger l
 LEFT JOIN finance.movement_cost_facts cf ON cf.tenant_id=l.tenant_id AND cf.movement_id=l.movement_id
 LEFT JOIN finance.receipt_cost_basis rb ON rb.tenant_id=l.tenant_id AND rb.movement_id=l.movement_id
 LEFT JOIN finance.journal_entries sj ON sj.tenant_id=l.tenant_id AND sj.cogs_movement_id=l.movement_id
 LEFT JOIN finance.journal_entries rj ON rj.tenant_id=l.tenant_id AND rj.cogs_return_movement_id=l.movement_id
 LEFT JOIN finance.supplier_invoices iv ON iv.tenant_id=l.tenant_id AND iv.invoice_id=rb.invoice_id
 LEFT JOIN finance.journal_entries ij ON ij.tenant_id=l.tenant_id AND ij.supplier_invoice_id=rb.invoice_id
 LEFT JOIN sales.returns sr ON sr.tenant_id=l.tenant_id AND l.adjustment_key LIKE 'sales-return:'||sr.return_id::text||':%'
 LEFT JOIN sales.order_items si ON si.tenant_id=sr.tenant_id AND si.order_id=sr.order_id
 AND l.adjustment_key='sales-return:'||sr.return_id::text||':'||si.item_id::text
 LEFT JOIN inventory.stock_ledger os ON os.tenant_id=si.tenant_id AND os.reservation_id=si.reservation_id AND os.quantity_delta=-si.quantity AND os.lot_id IS NULL AND os.serial_id IS NULL AND os.allocation_id IS NULL
 LEFT JOIN finance.journal_entries orig ON orig.tenant_id=os.tenant_id AND orig.cogs_movement_id=os.movement_id
 LEFT JOIN inventory.transfer_lines ti ON ti.tenant_id=l.tenant_id AND ti.incoming_movement_id=l.movement_id
 LEFT JOIN inventory.transfer_lines tout ON tout.tenant_id=l.tenant_id AND tout.outgoing_movement_id=l.movement_id
 LEFT JOIN finance.movement_cost_facts ci ON ci.tenant_id=l.tenant_id AND ci.movement_id=ti.outgoing_movement_id
 LEFT JOIN finance.movement_cost_facts co ON co.tenant_id=l.tenant_id AND co.movement_id=tout.incoming_movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 )
 SELECT m.mid,i.code FROM moves m CROSS JOIN LATERAL (
 VALUES
 ('cost_not_captured',m.captured_mid IS NULL),
 ('unsupported_movement',m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL OR m.allocation_id IS NOT NULL
 OR NOT (m.receipt_mid IS NOT NULL OR m.transfer_in IS NOT NULL OR m.transfer_out IS NOT NULL
 OR (m.qty<0 AND m.reservation_id IS NOT NULL) OR (m.qty>0 AND COALESCE(m.adjustment_key LIKE 'sales-return:%',false)))),
 ('purchase_invoice_missing',m.receipt_mid IS NOT NULL AND m.invoice_id IS NULL),
 ('purchase_cost_mismatch',m.receipt_mid IS NOT NULL AND (m.receipt_currency IS DISTINCT FROM pol.currency OR m.receipt_qty IS DISTINCT FROM m.qty
 OR (m.captured_mid IS NOT NULL AND m.cost IS DISTINCT FROM m.agreed_cost))),
 ('sale_cogs_missing',m.qty<0 AND m.reservation_id IS NOT NULL AND m.sale_entry IS NULL),
 ('return_reversal_missing',m.qty>0 AND COALESCE(m.adjustment_key LIKE 'sales-return:%',false) AND m.return_entry IS NULL),
 ('transfer_cost_unpaired',(m.transfer_in IS NOT NULL AND (m.cost IS NULL OR m.incoming_peer_value IS NULL OR m.cost IS DISTINCT FROM -m.incoming_peer_value))
 OR (m.transfer_out IS NOT NULL AND (m.cost IS NULL OR m.outgoing_peer_value IS NULL OR m.cost IS DISTINCT FROM -m.outgoing_peer_value))),
 ('purchase_journal_mismatch',m.invoice_id IS NOT NULL AND (
 m.invoice_entry IS NULL OR m.invoice_currency IS DISTINCT FROM pol.currency OR m.invoice_amount IS NULL
 OR (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=m.invoice_entry)<>2
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.invoice_entry AND ac.account_type='asset' AND jl.amount=m.invoice_amount)
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.invoice_entry AND ac.account_type='liability' AND jl.amount=-m.invoice_amount))),
 ('sale_journal_mismatch',m.sale_entry IS NOT NULL AND m.captured_mid IS NOT NULL AND (
 m.sale_currency IS DISTINCT FROM pol.currency
 OR (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=m.sale_entry)<>2
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.sale_entry AND ac.account_type='asset' AND jl.amount=m.cost)
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.sale_entry AND ac.account_type='expense' AND jl.amount=-m.cost))),
 ('return_journal_mismatch',m.return_entry IS NOT NULL AND (
 m.original_sale_entry IS NULL OR m.return_currency IS DISTINCT FROM pol.currency OR m.original_sale_currency IS DISTINCT FROM pol.currency
 OR (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=m.return_entry)<>2
 OR (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=m.original_sale_entry)<>2
 OR EXISTS(SELECT 1 FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=m.original_sale_entry
 AND NOT EXISTS(SELECT 1 FROM finance.journal_lines rl WHERE rl.tenant_id=t AND rl.entry_id=m.return_entry AND rl.account_id=jl.account_id AND rl.amount=-jl.amount))
 OR (m.captured_mid IS NOT NULL AND (
 NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.return_entry AND ac.account_type='asset' AND jl.amount=m.cost)
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=m.return_entry AND ac.account_type='expense' AND jl.amount=-m.cost))))),
 ('zero_sale_cost_pending_policy',m.qty<0 AND m.reservation_id IS NOT NULL AND m.cost=0)
 ) i(code,problem) WHERE i.problem IS TRUE ORDER BY m.mid,i.code;
 GET DIAGNOSTICS issue_count=ROW_COUNT;
 -- Do not attempt replay while basic lifecycle issues remain; keep actionable diagnostics.
 IF issue_count>0 OR NOT EXISTS(SELECT 1 FROM inventory.stock_ledger l
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant) THEN RETURN; END IF;
 BEGIN
 FOR x IN SELECT * FROM finance.replay_valuation_detail(p_warehouse,p_variant,pol.currency,pol.method) LOOP
 SELECT * INTO cf_row FROM finance.movement_cost_facts cf WHERE cf.tenant_id=t AND cf.movement_id=x.movement_id;
 IF NOT FOUND OR cf_row.sequence_no IS DISTINCT FROM x.step_no OR cf_row.quantity_delta IS DISTINCT FROM x.quantity_delta
 OR cf_row.value_delta IS DISTINCT FROM x.value_delta OR x.all_receipts_invoiced IS DISTINCT FROM true
 THEN RETURN QUERY SELECT x.movement_id,'cost_replay_mismatch'::text; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('receipt_movement_id',fa.receipt_movement_id,'quantity',fa.quantity,'cost',fa.cost)
 ORDER BY fa.receipt_movement_id),'[]'::jsonb) INTO actual_sources
 FROM finance.fifo_cost_allocations fa WHERE fa.tenant_id=t AND fa.outgoing_movement_id=x.movement_id;
 IF actual_sources IS DISTINCT FROM x.fifo_sources
 THEN RETURN QUERY SELECT x.movement_id,'fifo_allocation_replay_mismatch'::text; END IF;
 END LOOP;
 EXCEPTION WHEN check_violation THEN
 -- A scope-level failure is deliberately not treated as a ready scope.
 RETURN QUERY SELECT NULL::uuid,'valuation_replay_failed'::text;
 END;
END $$;
COMMIT;

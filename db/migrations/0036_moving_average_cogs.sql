-- 0036: shared explicit COGS posting with confirmed moving-average pool; provisional.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.post_inventory_cogs(p_movement uuid,p_inventory uuid,p_expense uuid,p_method text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cogs'); fact finance.movement_cost_facts%ROWTYPE;
 pol finance.valuation_policies%ROWTYPE; oid uuid; order_state text; order_currency text; amount numeric; prior uuid;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'COGS access denied' USING ERRCODE='42501'; END IF;
 IF p_method IS NULL OR p_method NOT IN ('fifo','moving_average') OR p_movement IS NULL OR p_inventory IS NULL OR p_expense IS NULL OR p_inventory=p_expense
 THEN RAISE EXCEPTION 'Invalid COGS arguments' USING ERRCODE='22023'; END IF;
 SELECT * INTO fact FROM finance.movement_cost_facts WHERE tenant_id=t AND movement_id=p_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Captured cost unavailable' USING ERRCODE='23503'; END IF;
 SELECT i.order_id INTO oid FROM inventory.stock_ledger m JOIN sales.order_items i
 ON i.tenant_id=m.tenant_id AND i.reservation_id=m.reservation_id
 WHERE m.tenant_id=t AND m.movement_id=p_movement AND m.quantity_delta=-i.quantity;
 IF NOT FOUND OR fact.quantity_delta>=0 THEN RAISE EXCEPTION 'Ordinary sale movement required' USING ERRCODE='23514'; END IF;
 PERFORM sales.lock_order(t,oid);
 PERFORM inventory.lock_trace_variant(t,fact.variant_id);
 SELECT o.state,o.currency INTO order_state,order_currency FROM sales.orders o WHERE o.tenant_id=t AND o.order_id=oid;
 SELECT * INTO pol FROM finance.valuation_policies WHERE tenant_id=t AND variant_id=fact.variant_id;
 IF NOT FOUND OR pol.method IS DISTINCT FROM p_method OR pol.currency IS DISTINCT FROM order_currency OR fact.value_delta>=0
 THEN RAISE EXCEPTION 'Positive confirmed cost with matching method and order currency required' USING ERRCODE='23514'; END IF;
 SELECT entry_id INTO prior FROM finance.journal_entries WHERE tenant_id=t AND cogs_movement_id=p_movement;
 IF prior IS NULL AND order_state IS DISTINCT FROM 'fulfilled'
 THEN RAISE EXCEPTION 'Fulfilled order required for initial COGS' USING ERRCODE='23514'; END IF;
 amount:=-fact.value_delta;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts a WHERE a.tenant_id=t AND a.account_id=p_inventory AND a.account_type='asset' AND a.currency=pol.currency)
 OR NOT EXISTS(SELECT 1 FROM finance.accounts a WHERE a.tenant_id=t AND a.account_id=p_expense AND a.account_type='expense' AND a.currency=pol.currency)
 THEN RAISE EXCEPTION 'Matching asset and expense accounts required' USING ERRCODE='23503'; END IF;
 IF p_method='fifo' THEN
 IF (SELECT sum(a.quantity) FROM finance.fifo_cost_allocations a WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement) IS DISTINCT FROM (-fact.quantity_delta)::numeric
 OR (SELECT sum(a.cost) FROM finance.fifo_cost_allocations a WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement) IS DISTINCT FROM amount
 THEN RAISE EXCEPTION 'Complete FIFO provenance required' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM finance.fifo_cost_allocations a
 WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement AND NOT EXISTS(
 SELECT 1 FROM finance.receipt_cost_basis b JOIN finance.journal_entries j ON j.tenant_id=b.tenant_id AND j.supplier_invoice_id=b.invoice_id
 JOIN finance.journal_lines l ON l.tenant_id=j.tenant_id AND l.entry_id=j.entry_id
 WHERE b.tenant_id=t AND b.movement_id=a.receipt_movement_id AND b.currency=pol.currency
 AND l.account_id=p_inventory AND l.amount>0))
 THEN RAISE EXCEPTION 'Inventory account must match all source invoice debits' USING ERRCODE='23514'; END IF;

 ELSE
 -- Moving average pools receipts. Until an account-level pool model is approved,
 -- require every positive captured movement preceding this sale to be a confirmed
 -- purchase receipt debited to the same inventory account (including exhausted receipts).
 IF NOT EXISTS(SELECT 1 FROM finance.movement_cost_facts cf WHERE cf.tenant_id=t
 AND cf.warehouse_id=fact.warehouse_id AND cf.variant_id=fact.variant_id AND cf.sequence_no<fact.sequence_no AND cf.quantity_delta>0)
 OR EXISTS(SELECT 1 FROM finance.movement_cost_facts cf
 WHERE cf.tenant_id=t AND cf.warehouse_id=fact.warehouse_id AND cf.variant_id=fact.variant_id
 AND cf.sequence_no<fact.sequence_no AND cf.quantity_delta>0 AND NOT EXISTS(
 SELECT 1 FROM finance.receipt_cost_basis rb JOIN finance.journal_entries j ON j.tenant_id=rb.tenant_id AND j.supplier_invoice_id=rb.invoice_id
 JOIN finance.journal_lines l ON l.tenant_id=j.tenant_id AND l.entry_id=j.entry_id
 WHERE rb.tenant_id=t AND rb.movement_id=cf.movement_id AND rb.currency=pol.currency
 AND rb.quantity=cf.quantity_delta AND rb.agreed_cost=cf.value_delta
 AND l.account_id=p_inventory AND l.amount>0))
 THEN RAISE EXCEPTION 'Moving-average receipt pool must match one inventory account' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM finance.fifo_cost_allocations a WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement)
 THEN RAISE EXCEPTION 'Unexpected FIFO allocation for moving average' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN finance.write_entry(t,'cogs:'||p_movement::text,pol.currency,CASE WHEN p_method='fifo' THEN 'Confirmed FIFO sale cost' ELSE 'Confirmed moving-average sale cost' END,
 jsonb_build_array(jsonb_build_object('account_id',p_expense,'amount',amount),jsonb_build_object('account_id',p_inventory,'amount',-amount)),NULL,NULL);
END $$;
ALTER FUNCTION finance.post_inventory_cogs(uuid,uuid,uuid,text) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.post_inventory_cogs(uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.post_inventory_cogs(uuid,uuid,uuid,text) TO upc_runtime;
-- Preserve the existing FIFO entry point and strict method gate; one posting implementation.
CREATE OR REPLACE FUNCTION finance.post_fifo_cogs(p_movement uuid,p_inventory uuid,p_expense uuid) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT finance.post_inventory_cogs(p_movement,p_inventory,p_expense,'fifo')
$$;
COMMIT;

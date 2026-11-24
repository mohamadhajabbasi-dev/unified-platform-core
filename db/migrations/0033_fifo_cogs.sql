-- 0030: explicit FIFO COGS posting to existing journal; no automatic lifecycle activation.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('finance.post.cogs','Post verified FIFO cost of sold goods');
ALTER TABLE finance.journal_entries ADD COLUMN cogs_movement_id uuid;
ALTER TABLE finance.journal_entries ADD UNIQUE(tenant_id,cogs_movement_id);
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,cogs_movement_id) REFERENCES finance.movement_cost_facts(tenant_id,movement_id);
ALTER TABLE finance.journal_entries DROP CONSTRAINT journal_source_kind;
ALTER TABLE finance.journal_entries ADD CONSTRAINT journal_source_kind CHECK(
 num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id,cogs_movement_id)<=1 AND (
 (num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id,cogs_movement_id)=0 AND source_key LIKE 'manual:%')
 OR (payment_id IS NOT NULL AND source_key='payment:'||payment_id::text)
 OR (refund_id IS NOT NULL AND source_key='refund:'||refund_id::text)
 OR (recognition_order_id IS NOT NULL AND source_key='revenue:'||recognition_order_id::text)
 OR (supplier_invoice_id IS NOT NULL AND source_key='supplier-invoice:'||supplier_invoice_id::text)
 OR (supplier_settlement_id IS NOT NULL AND source_key='supplier-settlement:'||supplier_settlement_id::text)
 OR (cogs_movement_id IS NOT NULL AND source_key='cogs:'||cogs_movement_id::text)));
CREATE OR REPLACE FUNCTION finance.assign_period() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE pid uuid;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'Posting requires READ COMMITTED' USING ERRCODE='25000'; END IF;
 PERFORM finance.lock_periods(NEW.tenant_id);
 NEW.posted_at:=clock_timestamp();
 SELECT period_id INTO pid FROM finance.fiscal_periods WHERE tenant_id=NEW.tenant_id
 AND dates @> (NEW.posted_at AT TIME ZONE 'UTC')::date AND closed_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'No open fiscal period for posting date' USING ERRCODE='23514'; END IF;
 NEW.period_id:=pid;
 IF NEW.source_key LIKE 'revenue:%' THEN NEW.recognition_order_id:=substring(NEW.source_key from 9)::uuid; END IF;
 IF NEW.source_key LIKE 'supplier-invoice:%' THEN NEW.supplier_invoice_id:=substring(NEW.source_key from 18)::uuid; END IF;
 IF NEW.source_key LIKE 'supplier-settlement:%' THEN NEW.supplier_settlement_id:=substring(NEW.source_key from 21)::uuid; END IF;
 IF NEW.source_key LIKE 'cogs:%' THEN NEW.cogs_movement_id:=substring(NEW.source_key from 6)::uuid; END IF;
 RETURN NEW;
END $$;
GRANT SELECT ON sales.order_items TO upc_finance_executor;
CREATE POLICY finance_cogs_item_dependency ON sales.order_items FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
GRANT EXECUTE ON FUNCTION sales.lock_order(uuid,uuid) TO upc_finance_executor;
CREATE FUNCTION finance.post_fifo_cogs(p_movement uuid,p_inventory uuid,p_expense uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cogs'); fact finance.movement_cost_facts%ROWTYPE;
 pol finance.valuation_policies%ROWTYPE; oid uuid; order_state text; order_currency text; amount numeric; prior uuid;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'COGS access denied' USING ERRCODE='42501'; END IF;
 IF p_movement IS NULL OR p_inventory IS NULL OR p_expense IS NULL OR p_inventory=p_expense
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
 IF NOT FOUND OR pol.method<>'fifo' OR pol.currency IS DISTINCT FROM order_currency OR fact.value_delta>=0
 THEN RAISE EXCEPTION 'Positive confirmed FIFO cost in order currency required' USING ERRCODE='23514'; END IF;
 SELECT entry_id INTO prior FROM finance.journal_entries WHERE tenant_id=t AND cogs_movement_id=p_movement;
 IF prior IS NULL AND order_state IS DISTINCT FROM 'fulfilled'
 THEN RAISE EXCEPTION 'Fulfilled order required for initial COGS' USING ERRCODE='23514'; END IF;
 amount:=-fact.value_delta;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts a WHERE a.tenant_id=t AND a.account_id=p_inventory AND a.account_type='asset' AND a.currency=pol.currency)
 OR NOT EXISTS(SELECT 1 FROM finance.accounts a WHERE a.tenant_id=t AND a.account_id=p_expense AND a.account_type='expense' AND a.currency=pol.currency)
 THEN RAISE EXCEPTION 'Matching asset and expense accounts required' USING ERRCODE='23503'; END IF;
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
 RETURN finance.write_entry(t,'cogs:'||p_movement::text,pol.currency,'Confirmed FIFO sale cost',
 jsonb_build_array(jsonb_build_object('account_id',p_expense,'amount',amount),jsonb_build_object('account_id',p_inventory,'amount',-amount)),NULL,NULL);
END $$;
ALTER FUNCTION finance.post_fifo_cogs(uuid,uuid,uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.post_fifo_cogs(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.post_fifo_cogs(uuid,uuid,uuid) TO upc_runtime;
COMMIT;

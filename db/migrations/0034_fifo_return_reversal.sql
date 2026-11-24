-- 0034: explicit full sellable ordinary FIFO return reversal; no automated posting.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('finance.post.cogs_return','Reverse posted FIFO cost for a verified full sellable return');
ALTER TABLE finance.journal_entries ADD COLUMN cogs_return_movement_id uuid;
ALTER TABLE finance.journal_entries ADD UNIQUE(tenant_id,cogs_return_movement_id);
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,cogs_return_movement_id) REFERENCES inventory.stock_ledger(tenant_id,movement_id);
ALTER TABLE finance.journal_entries DROP CONSTRAINT journal_source_kind;
ALTER TABLE finance.journal_entries ADD CONSTRAINT journal_source_kind CHECK(
 num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id,cogs_movement_id,cogs_return_movement_id)<=1 AND (
 (num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id,cogs_movement_id,cogs_return_movement_id)=0 AND source_key LIKE 'manual:%')
 OR (payment_id IS NOT NULL AND source_key='payment:'||payment_id::text)
 OR (refund_id IS NOT NULL AND source_key='refund:'||refund_id::text)
 OR (recognition_order_id IS NOT NULL AND source_key='revenue:'||recognition_order_id::text)
 OR (supplier_invoice_id IS NOT NULL AND source_key='supplier-invoice:'||supplier_invoice_id::text)
 OR (supplier_settlement_id IS NOT NULL AND source_key='supplier-settlement:'||supplier_settlement_id::text)
 OR (cogs_movement_id IS NOT NULL AND source_key='cogs:'||cogs_movement_id::text)
 OR (cogs_return_movement_id IS NOT NULL AND source_key='cogs-return:'||cogs_return_movement_id::text)));
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
 IF NEW.source_key LIKE 'cogs-return:%' THEN NEW.cogs_return_movement_id:=substring(NEW.source_key from 13)::uuid; END IF;
 RETURN NEW;
END $$;
GRANT SELECT ON sales.returns TO upc_finance_executor;
CREATE POLICY finance_cogs_return_dependency ON sales.returns FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE FUNCTION finance.reverse_fifo_cogs(p_sale_movement uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cogs_return'); fact finance.movement_cost_facts%ROWTYPE;
 sale_item sales.order_items%ROWTYPE; original finance.journal_entries%ROWTYPE; ret sales.returns%ROWTYPE;
 movement inventory.stock_ledger%ROWTYPE; order_state text; reversal jsonb; amount numeric; n bigint;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'COGS return access denied' USING ERRCODE='42501'; END IF;
 IF p_sale_movement IS NULL THEN RAISE EXCEPTION 'Sale movement required' USING ERRCODE='22023'; END IF;
 SELECT * INTO fact FROM finance.movement_cost_facts WHERE tenant_id=t AND movement_id=p_sale_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Captured sale cost unavailable' USING ERRCODE='23503'; END IF;
 SELECT i.* INTO sale_item FROM inventory.stock_ledger m JOIN sales.order_items i
 ON i.tenant_id=m.tenant_id AND i.reservation_id=m.reservation_id
 WHERE m.tenant_id=t AND m.movement_id=p_sale_movement AND m.quantity_delta=-i.quantity
 AND m.lot_id IS NULL AND m.serial_id IS NULL AND m.allocation_id IS NULL;
 IF NOT FOUND OR fact.quantity_delta>=0 OR fact.value_delta>=0 THEN RAISE EXCEPTION 'Positive ordinary FIFO sale cost required' USING ERRCODE='23514'; END IF;
 PERFORM sales.lock_order(t,sale_item.order_id);
 PERFORM inventory.lock_trace_variant(t,fact.variant_id);
 SELECT * INTO original FROM finance.journal_entries WHERE tenant_id=t AND cogs_movement_id=p_sale_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Original COGS journal required' USING ERRCODE='23514'; END IF;
 SELECT o.state INTO order_state FROM sales.orders o WHERE o.tenant_id=t AND o.order_id=sale_item.order_id;
 IF order_state IS NULL OR order_state NOT IN ('returned','refunded') THEN RAISE EXCEPTION 'Confirmed physical return required' USING ERRCODE='23514'; END IF;
 SELECT * INTO ret FROM sales.returns WHERE tenant_id=t AND order_id=sale_item.order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Return evidence unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO movement FROM inventory.stock_ledger WHERE tenant_id=t
 AND adjustment_key='sales-return:'||ret.return_id::text||':'||sale_item.item_id::text
 AND warehouse_id=fact.warehouse_id AND variant_id=fact.variant_id AND quantity_delta=-fact.quantity_delta
 AND reason='full order return' AND lot_id IS NULL AND serial_id IS NULL AND reservation_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Exact sellable return movement required' USING ERRCODE='23514'; END IF;
 amount:=-fact.value_delta;
 SELECT count(*),jsonb_agg(jsonb_build_object('account_id',l.account_id,'amount',-l.amount) ORDER BY l.account_id)
 INTO n,reversal FROM finance.journal_lines l WHERE l.tenant_id=t AND l.entry_id=original.entry_id;
 IF n<>2 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=amount AND a.account_type='expense')
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=-amount AND a.account_type='asset')
 THEN RAISE EXCEPTION 'Original COGS lines do not match captured cost' USING ERRCODE='23514'; END IF;
 RETURN finance.write_entry(t,'cogs-return:'||movement.movement_id::text,original.currency,'Confirmed FIFO full return reversal',reversal,NULL,NULL);
END $$;
ALTER FUNCTION finance.reverse_fifo_cogs(uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.reverse_fifo_cogs(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.reverse_fifo_cogs(uuid) TO upc_runtime;
-- Return movements are not yet admitted into valuation replay: no resale valuation or
-- new capture across this history until FIFO return-layer provenance is implemented.
COMMIT;

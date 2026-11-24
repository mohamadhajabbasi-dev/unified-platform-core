-- 0039: conservative moving-average account provenance through exact transfer pairs.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.assert_average_asset_provenance(p_tenant uuid,p_movement uuid,p_inventory uuid,p_currency text) RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE bad boolean;
BEGIN
 IF p_tenant IS DISTINCT FROM iam.current_tenant_id() THEN RAISE EXCEPTION 'Valuation scope denied' USING ERRCODE='42501'; END IF;
 -- Each node is an outflow cutoff. Walk every prior positive input, including exhausted
 -- layers, and recursively follow exact transfer pairs to the earlier source cutoff.
 -- Strict ledger chronology on edges and UNION deduplication prevent cycles.
 WITH RECURSIVE edges AS (
 SELECT fi.movement_id AS incoming_id,fo.movement_id AS outgoing_id
 FROM inventory.transfer_lines tl
 JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id
 JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id
 JOIN inventory.stock_ledger li ON li.tenant_id=fi.tenant_id AND li.movement_id=fi.movement_id
 JOIN inventory.stock_ledger lo ON lo.tenant_id=fo.tenant_id AND lo.movement_id=fo.movement_id
 JOIN finance.valuation_policies vp ON vp.tenant_id=fi.tenant_id AND vp.variant_id=fi.variant_id
 WHERE tl.tenant_id=p_tenant AND vp.method='moving_average' AND vp.currency=p_currency
 AND fi.warehouse_id=tl.destination_warehouse_id AND fo.warehouse_id=tl.source_warehouse_id
 AND fi.variant_id=tl.variant_id AND fo.variant_id=tl.variant_id
 AND fi.quantity_delta=tl.quantity AND fo.quantity_delta=-tl.quantity
 AND fi.value_delta=-fo.value_delta AND fi.value_delta>=0
 AND (lo.recorded_at,lo.movement_id)<(li.recorded_at,li.movement_id)
 ), scopes(mid) AS (
 SELECT p_movement
 UNION
 SELECT e.outgoing_id FROM scopes sc
 JOIN finance.movement_cost_facts cutoff ON cutoff.tenant_id=p_tenant AND cutoff.movement_id=sc.mid
 JOIN finance.movement_cost_facts cf ON cf.tenant_id=cutoff.tenant_id AND cf.warehouse_id=cutoff.warehouse_id
 AND cf.variant_id=cutoff.variant_id AND cf.sequence_no<cutoff.sequence_no AND cf.quantity_delta>0
 JOIN edges e ON e.incoming_id=cf.movement_id
 ), inputs AS (
 SELECT DISTINCT sc.mid AS cutoff_id,cf.movement_id,cf.quantity_delta,cf.value_delta
 FROM scopes sc JOIN finance.movement_cost_facts cutoff ON cutoff.tenant_id=p_tenant AND cutoff.movement_id=sc.mid
 JOIN finance.movement_cost_facts cf ON cf.tenant_id=cutoff.tenant_id AND cf.warehouse_id=cutoff.warehouse_id
 AND cf.variant_id=cutoff.variant_id AND cf.sequence_no<cutoff.sequence_no AND cf.quantity_delta>0
 )
 SELECT EXISTS(SELECT 1 FROM scopes sc WHERE NOT EXISTS(SELECT 1 FROM inputs i WHERE i.cutoff_id=sc.mid))
 OR EXISTS(SELECT 1 FROM inputs cf WHERE
 NOT EXISTS(SELECT 1 FROM finance.receipt_cost_basis rb
 JOIN finance.journal_entries j ON j.tenant_id=rb.tenant_id AND j.supplier_invoice_id=rb.invoice_id
 JOIN finance.journal_lines l ON l.tenant_id=j.tenant_id AND l.entry_id=j.entry_id
 WHERE rb.tenant_id=p_tenant AND rb.movement_id=cf.movement_id AND rb.currency=p_currency
 AND rb.quantity=cf.quantity_delta AND rb.agreed_cost=cf.value_delta AND l.account_id=p_inventory AND l.amount>0)
 AND NOT EXISTS(SELECT 1 FROM finance.journal_entries rj
 JOIN finance.journal_lines rl ON rl.tenant_id=rj.tenant_id AND rl.entry_id=rj.entry_id
 WHERE rj.tenant_id=p_tenant AND rj.cogs_return_movement_id=cf.movement_id AND rj.currency=p_currency
 AND rl.account_id=p_inventory AND rl.amount=cf.value_delta AND rl.amount>0)
 AND NOT EXISTS(SELECT 1 FROM edges e WHERE e.incoming_id=cf.movement_id))
 INTO bad;
 IF bad IS DISTINCT FROM false THEN RAISE EXCEPTION 'Moving-average receipt/transfer pool must match one inventory account' USING ERRCODE='23514'; END IF;
END $$;
ALTER FUNCTION finance.assert_average_asset_provenance(uuid,uuid,uuid,text) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.assert_average_asset_provenance(uuid,uuid,uuid,text) FROM PUBLIC;
CREATE OR REPLACE FUNCTION finance.post_inventory_cogs(p_movement uuid,p_inventory uuid,p_expense uuid,p_method text) RETURNS uuid
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
 PERFORM finance.assert_average_asset_provenance(t,p_movement,p_inventory,pol.currency);
 IF EXISTS(SELECT 1 FROM finance.fifo_cost_allocations a WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement)
 THEN RAISE EXCEPTION 'Unexpected FIFO allocation for moving average' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN finance.write_entry(t,'cogs:'||p_movement::text,pol.currency,CASE WHEN p_method='fifo' THEN 'Confirmed FIFO sale cost' ELSE 'Confirmed moving-average sale cost' END,
 jsonb_build_array(jsonb_build_object('account_id',p_expense,'amount',amount),jsonb_build_object('account_id',p_inventory,'amount',-amount)),NULL,NULL);
END $$;
COMMIT;

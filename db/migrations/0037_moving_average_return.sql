-- 0037: shared full sellable return reversal and historical moving-average return cost; provisional.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.reverse_inventory_cogs(p_sale_movement uuid,p_method text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cogs_return'); fact finance.movement_cost_facts%ROWTYPE;
 sale_item sales.order_items%ROWTYPE; original finance.journal_entries%ROWTYPE; ret sales.returns%ROWTYPE;
 movement inventory.stock_ledger%ROWTYPE; pol finance.valuation_policies%ROWTYPE; order_state text; reversal jsonb; v_original_cost numeric; n bigint;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'COGS return access denied' USING ERRCODE='42501'; END IF;
 IF p_sale_movement IS NULL OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average') THEN RAISE EXCEPTION 'Sale movement required' USING ERRCODE='22023'; END IF;
 SELECT * INTO fact FROM finance.movement_cost_facts WHERE tenant_id=t AND movement_id=p_sale_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Captured sale cost unavailable' USING ERRCODE='23503'; END IF;
 SELECT i.* INTO sale_item FROM inventory.stock_ledger m JOIN sales.order_items i
 ON i.tenant_id=m.tenant_id AND i.reservation_id=m.reservation_id
 WHERE m.tenant_id=t AND m.movement_id=p_sale_movement AND m.quantity_delta=-i.quantity
 AND m.lot_id IS NULL AND m.serial_id IS NULL AND m.allocation_id IS NULL;
 IF NOT FOUND OR fact.quantity_delta>=0 OR fact.value_delta>=0 THEN RAISE EXCEPTION 'Positive ordinary sale cost required' USING ERRCODE='23514'; END IF;
 PERFORM sales.lock_order(t,sale_item.order_id);
 PERFORM inventory.lock_trace_variant(t,fact.variant_id);
 SELECT * INTO pol FROM finance.valuation_policies WHERE tenant_id=t AND variant_id=fact.variant_id;
 IF NOT FOUND OR pol.method IS DISTINCT FROM p_method THEN RAISE EXCEPTION 'Return valuation method mismatch' USING ERRCODE='23514'; END IF;
 SELECT * INTO original FROM finance.journal_entries WHERE tenant_id=t AND cogs_movement_id=p_sale_movement;
 IF NOT FOUND OR original.currency IS DISTINCT FROM pol.currency THEN RAISE EXCEPTION 'Original COGS journal required' USING ERRCODE='23514'; END IF;
 SELECT o.state INTO order_state FROM sales.orders o WHERE o.tenant_id=t AND o.order_id=sale_item.order_id;
 IF order_state IS NULL OR order_state NOT IN ('returned','refunded') THEN RAISE EXCEPTION 'Confirmed physical return required' USING ERRCODE='23514'; END IF;
 SELECT * INTO ret FROM sales.returns WHERE tenant_id=t AND order_id=sale_item.order_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Return evidence unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO movement FROM inventory.stock_ledger WHERE tenant_id=t
 AND adjustment_key='sales-return:'||ret.return_id::text||':'||sale_item.item_id::text
 AND warehouse_id=fact.warehouse_id AND variant_id=fact.variant_id AND quantity_delta=-fact.quantity_delta
 AND reason='full order return' AND lot_id IS NULL AND serial_id IS NULL AND reservation_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Exact sellable return movement required' USING ERRCODE='23514'; END IF;
 v_original_cost:=-fact.value_delta;
 SELECT count(*),jsonb_agg(jsonb_build_object('account_id',l.account_id,'amount',-l.amount) ORDER BY l.account_id)
 INTO n,reversal FROM finance.journal_lines l WHERE l.tenant_id=t AND l.entry_id=original.entry_id;
 IF n<>2 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=v_original_cost AND a.account_type='expense')
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=-v_original_cost AND a.account_type='asset')
 THEN RAISE EXCEPTION 'Original COGS lines do not match captured cost' USING ERRCODE='23514'; END IF;
 RETURN finance.write_entry(t,'cogs-return:'||movement.movement_id::text,original.currency,CASE WHEN p_method='fifo' THEN 'Confirmed FIFO full return reversal' ELSE 'Confirmed moving-average full return reversal' END,reversal,NULL,NULL);
END $$;
ALTER FUNCTION finance.reverse_inventory_cogs(uuid,text) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.reverse_inventory_cogs(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.reverse_inventory_cogs(uuid,text) TO upc_runtime;
CREATE OR REPLACE FUNCTION finance.reverse_fifo_cogs(p_sale_movement uuid) RETURNS uuid
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT finance.reverse_inventory_cogs(p_sale_movement,'fifo')
$$;
CREATE OR REPLACE FUNCTION finance.replay_valuation_detail(p_warehouse uuid,p_variant uuid,p_currency text,p_method text)
RETURNS TABLE(step_no bigint,movement_id uuid,quantity_delta bigint,value_delta numeric,on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean,fifo_sources jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE m record; t uuid:=iam.current_tenant_id(); q numeric:=0; val numeric:=0; spent numeric:=0;
 take_qty numeric; cost numeric; remaining numeric; idx integer:=1;
 layer_qty numeric[]:=ARRAY[]::numeric[]; layer_cost numeric[]:=ARRAY[]::numeric[];
 confirmed boolean:=true; seq bigint:=0; source_ids uuid[]:=ARRAY[]::uuid[]; sources jsonb; returned_sale record; restored record; restored_qty numeric; restored_value numeric;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Valuation access denied' USING ERRCODE='42501'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
 OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average') THEN
 RAISE EXCEPTION 'Invalid valuation arguments' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.warehouses w WHERE w.tenant_id=t AND w.warehouse_id=p_warehouse)
 THEN RAISE EXCEPTION 'Warehouse unavailable' USING ERRCODE='23503'; END IF;
 -- No partial results for unsupported movements or absent stock history.
 FOR m IN SELECT l.movement_id,l.quantity_delta,l.reservation_id,l.lot_id,l.serial_id,l.adjustment_key,
 b.movement_id AS receipt_movement,b.quantity AS receipt_qty,b.agreed_cost,b.currency,b.invoice_id
 FROM inventory.stock_ledger l LEFT JOIN finance.receipt_cost_basis b
 ON b.tenant_id=l.tenant_id AND b.movement_id=l.movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 ORDER BY l.recorded_at,l.movement_id
 LOOP
 sources:='[]'::jsonb;
 IF m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Tracked valuation not supported in preview' USING ERRCODE='23514'; END IF;
 IF m.quantity_delta>0 THEN
 IF m.adjustment_key LIKE 'sales-return:%' THEN
 IF NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Sales return evidence access denied' USING ERRCODE='42501'; END IF;
 -- Only an exact full ordinary return with already captured and reversed historical COGS.
 SELECT cf.movement_id AS original_movement,cf.quantity_delta AS original_qty,cf.value_delta AS original_value
 INTO returned_sale
 FROM sales.returns r JOIN sales.order_items i ON i.tenant_id=r.tenant_id AND i.order_id=r.order_id
 JOIN inventory.stock_ledger sl ON sl.tenant_id=i.tenant_id AND sl.reservation_id=i.reservation_id
 JOIN finance.movement_cost_facts cf ON cf.tenant_id=sl.tenant_id AND cf.movement_id=sl.movement_id
 JOIN finance.valuation_policies vp ON vp.tenant_id=cf.tenant_id AND vp.variant_id=cf.variant_id
 JOIN finance.journal_entries sj ON sj.tenant_id=cf.tenant_id AND sj.cogs_movement_id=cf.movement_id
 JOIN finance.journal_entries rj ON rj.tenant_id=cf.tenant_id AND rj.cogs_return_movement_id=m.movement_id
 WHERE r.tenant_id=t AND m.adjustment_key='sales-return:'||r.return_id::text||':'||i.item_id::text
 AND i.warehouse_id=p_warehouse AND i.variant_id=p_variant AND i.quantity=m.quantity_delta
 AND sl.quantity_delta=-i.quantity AND sl.lot_id IS NULL AND sl.serial_id IS NULL
 AND cf.warehouse_id=p_warehouse AND cf.variant_id=p_variant AND cf.sequence_no<=seq
 AND cf.value_delta<0 AND vp.method=p_method AND vp.currency=p_currency
 AND sj.currency=p_currency AND rj.currency=p_currency;
 IF NOT FOUND THEN RAISE EXCEPTION 'Confirmed reversed return evidence with matching method required' USING ERRCODE='23514'; END IF;
 IF p_method='fifo' THEN
 restored_qty:=0; restored_value:=0;
 FOR restored IN SELECT a.receipt_movement_id,a.quantity,a.cost
 FROM finance.fifo_cost_allocations a
 JOIN inventory.stock_ledger rl ON rl.tenant_id=a.tenant_id AND rl.movement_id=a.receipt_movement_id
 JOIN finance.receipt_cost_basis rb ON rb.tenant_id=a.tenant_id AND rb.movement_id=a.receipt_movement_id
 WHERE a.tenant_id=t AND a.outgoing_movement_id=returned_sale.original_movement
 AND a.warehouse_id=p_warehouse AND a.variant_id=p_variant AND rb.invoice_id IS NOT NULL AND rb.currency=p_currency
 ORDER BY rl.recorded_at,rl.movement_id LOOP
 -- Append at return time, retaining original receipt identity and exact consumed cost.
 layer_qty:=array_append(layer_qty,restored.quantity::numeric);
 layer_cost:=array_append(layer_cost,restored.cost);
 source_ids:=array_append(source_ids,restored.receipt_movement_id);
 restored_qty:=restored_qty+restored.quantity; restored_value:=restored_value+restored.cost;
 END LOOP;
 IF restored_qty<>m.quantity_delta OR restored_value<>-returned_sale.original_value
 THEN RAISE EXCEPTION 'Return source allocation reconciliation failed' USING ERRCODE='23514'; END IF;
 cost:=restored_value;
 ELSE
 IF returned_sale.original_qty IS DISTINCT FROM -m.quantity_delta
 OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa WHERE fa.tenant_id=t AND fa.outgoing_movement_id=returned_sale.original_movement)
 THEN RAISE EXCEPTION 'Moving-average return evidence mismatch' USING ERRCODE='23514'; END IF;
 cost:=-returned_sale.original_value;
 END IF;
 q:=q+m.quantity_delta; val:=val+cost; spent:=spent-cost;
 ELSE
 IF m.receipt_movement IS NULL OR m.receipt_qty IS DISTINCT FROM m.quantity_delta OR m.currency IS DISTINCT FROM p_currency
 OR m.agreed_cost IS NULL OR m.agreed_cost<0 OR m.agreed_cost='NaN'::numeric THEN
 RAISE EXCEPTION 'Unknown or incompatible receipt cost' USING ERRCODE='23514'; END IF;
 confirmed:=confirmed AND m.invoice_id IS NOT NULL;
 q:=q+m.quantity_delta; val:=val+m.agreed_cost; cost:=m.agreed_cost;
 IF p_method='fifo' THEN
 layer_qty:=array_append(layer_qty,m.quantity_delta::numeric);
 layer_cost:=array_append(layer_cost,m.agreed_cost);
 source_ids:=array_append(source_ids,m.movement_id);
 END IF;
 END IF;
 ELSE
 IF m.reservation_id IS NULL OR q< -m.quantity_delta THEN
 RAISE EXCEPTION 'Unsupported or uncosted stock outflow' USING ERRCODE='23514'; END IF;
 remaining:= -m.quantity_delta; cost:=0;
 IF p_method='moving_average' THEN
 cost:=CASE WHEN remaining=q THEN val ELSE round(val*remaining/q,4) END;
 ELSE
 WHILE remaining>0 LOOP
 IF layer_qty[idx] IS NULL THEN RAISE EXCEPTION 'Missing cost layer' USING ERRCODE='23514'; END IF;
 take_qty:=least(remaining,layer_qty[idx]);
 IF take_qty IS NULL OR take_qty<=0 THEN RAISE EXCEPTION 'Missing cost layer' USING ERRCODE='23514'; END IF;
 DECLARE part numeric; BEGIN
 part:=CASE WHEN take_qty=layer_qty[idx] THEN layer_cost[idx] ELSE round(layer_cost[idx]*take_qty/layer_qty[idx],4) END;
 sources:=sources||jsonb_build_array(jsonb_build_object('receipt_movement_id',source_ids[idx],'quantity',take_qty,'cost',part));
 cost:=cost+part; layer_qty[idx]:=layer_qty[idx]-take_qty; layer_cost[idx]:=layer_cost[idx]-part;
 END;
 remaining:=remaining-take_qty;
 IF layer_qty[idx]=0 THEN idx:=idx+1; END IF;
 END LOOP;
 END IF;
 IF p_method='fifo' THEN
 -- A receipt can recur in multiple queue layers after returns. Preserve one source row per receipt.
 SELECT COALESCE(jsonb_agg(jsonb_build_object('receipt_movement_id',g.rid,'quantity',g.qty,'cost',g.cost) ORDER BY g.rid),'[]'::jsonb)
 INTO sources FROM (SELECT x.receipt_movement_id AS rid,sum(x.quantity) AS qty,sum(x.cost) AS cost
 FROM jsonb_to_recordset(sources) AS x(receipt_movement_id uuid,quantity numeric,cost numeric)
 GROUP BY x.receipt_movement_id) g;
 END IF;
 q:=q+m.quantity_delta; val:=val-cost; spent:=spent+cost;
 END IF;
 seq:=seq+1;
 RETURN QUERY SELECT seq,m.movement_id,m.quantity_delta,CASE WHEN m.quantity_delta>0 THEN cost ELSE -cost END,q,val,spent,confirmed,sources;
 END LOOP;
 IF NOT FOUND THEN RAISE EXCEPTION 'No visible stock history' USING ERRCODE='23503'; END IF;
END $$;
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
 -- Moving average pools receipts. Until an account-level pool model is approved,
 -- require every positive captured movement preceding this sale to be a confirmed
 -- purchase receipt or confirmed return debited to the same inventory account (including exhausted receipts).
 IF NOT EXISTS(SELECT 1 FROM finance.movement_cost_facts cf WHERE cf.tenant_id=t
 AND cf.warehouse_id=fact.warehouse_id AND cf.variant_id=fact.variant_id AND cf.sequence_no<fact.sequence_no AND cf.quantity_delta>0)
 OR EXISTS(SELECT 1 FROM finance.movement_cost_facts cf
 WHERE cf.tenant_id=t AND cf.warehouse_id=fact.warehouse_id AND cf.variant_id=fact.variant_id
 AND cf.sequence_no<fact.sequence_no AND cf.quantity_delta>0 AND NOT EXISTS(
 SELECT 1 FROM finance.receipt_cost_basis rb JOIN finance.journal_entries j ON j.tenant_id=rb.tenant_id AND j.supplier_invoice_id=rb.invoice_id
 JOIN finance.journal_lines l ON l.tenant_id=j.tenant_id AND l.entry_id=j.entry_id
 WHERE rb.tenant_id=t AND rb.movement_id=cf.movement_id AND rb.currency=pol.currency
 AND rb.quantity=cf.quantity_delta AND rb.agreed_cost=cf.value_delta
 AND l.account_id=p_inventory AND l.amount>0)
 AND NOT EXISTS(
 SELECT 1 FROM finance.journal_entries rj JOIN finance.journal_lines rl ON rl.tenant_id=rj.tenant_id AND rl.entry_id=rj.entry_id
 WHERE rj.tenant_id=t AND rj.cogs_return_movement_id=cf.movement_id AND rj.currency=pol.currency
 AND rl.account_id=p_inventory AND rl.amount=cf.value_delta AND rl.amount>0))
 THEN RAISE EXCEPTION 'Moving-average receipt pool must match one inventory account' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM finance.fifo_cost_allocations a WHERE a.tenant_id=t AND a.outgoing_movement_id=p_movement)
 THEN RAISE EXCEPTION 'Unexpected FIFO allocation for moving average' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN finance.write_entry(t,'cogs:'||p_movement::text,pol.currency,CASE WHEN p_method='fifo' THEN 'Confirmed FIFO sale cost' ELSE 'Confirmed moving-average sale cost' END,
 jsonb_build_array(jsonb_build_object('account_id',p_expense,'amount',amount),jsonb_build_object('account_id',p_inventory,'amount',-amount)),NULL,NULL);
END $$;
COMMIT;

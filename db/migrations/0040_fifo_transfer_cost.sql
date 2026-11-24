-- 0040: ordinary FIFO transfers retain original receipt provenance across warehouses.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
-- Keep the outgoing scope FK intact. Only the receipt-side warehouse restriction changes:
-- the original confirmed receipt may belong to a different warehouse, never tenant or variant.
ALTER TABLE finance.movement_cost_facts ADD UNIQUE(tenant_id,variant_id,movement_id);
DO $$
DECLARE fk_name text; n integer;
BEGIN
 SELECT count(*),min(conname) INTO n,fk_name FROM pg_constraint
 WHERE conrelid='finance.fifo_cost_allocations'::regclass AND contype='f'
 AND pg_get_constraintdef(oid) LIKE 'FOREIGN KEY (tenant_id, warehouse_id, variant_id, receipt_movement_id)%';
 IF n<>1 THEN RAISE EXCEPTION 'Expected exactly one original receipt scope FK'; END IF;
 EXECUTE format('ALTER TABLE finance.fifo_cost_allocations DROP CONSTRAINT %I',fk_name);
END $$;
ALTER TABLE finance.fifo_cost_allocations ADD CONSTRAINT fifo_original_receipt_scope_fk
 FOREIGN KEY(tenant_id,variant_id,receipt_movement_id) REFERENCES finance.movement_cost_facts(tenant_id,variant_id,movement_id);
CREATE OR REPLACE FUNCTION finance.replay_valuation_detail(p_warehouse uuid,p_variant uuid,p_currency text,p_method text)
RETURNS TABLE(step_no bigint,movement_id uuid,quantity_delta bigint,value_delta numeric,on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean,fifo_sources jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE m record; t uuid:=iam.current_tenant_id(); q numeric:=0; val numeric:=0; spent numeric:=0;
 take_qty numeric; cost numeric; remaining numeric; idx integer:=1;
 layer_qty numeric[]:=ARRAY[]::numeric[]; layer_cost numeric[]:=ARRAY[]::numeric[];
 confirmed boolean:=true; seq bigint:=0; source_ids uuid[]:=ARRAY[]::uuid[]; sources jsonb; returned_sale record; restored record; restored_qty numeric; restored_value numeric; transfer_out boolean; transferred_cost numeric; transfer_source uuid; transfer_source_wh uuid;
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
 sources:='[]'::jsonb; transfer_out:=false;
 IF m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Tracked valuation not supported in preview' USING ERRCODE='23514'; END IF;
 IF m.quantity_delta>0 THEN
 IF m.adjustment_key LIKE 'transfer:%' THEN
 SELECT -cf.value_delta,cf.movement_id,cf.warehouse_id INTO transferred_cost,transfer_source,transfer_source_wh
 FROM inventory.transfer_lines tl
 JOIN finance.movement_cost_facts cf ON cf.tenant_id=tl.tenant_id AND cf.movement_id=tl.outgoing_movement_id
 JOIN finance.valuation_policies vp ON vp.tenant_id=cf.tenant_id AND vp.variant_id=cf.variant_id
 WHERE tl.tenant_id=t AND tl.incoming_movement_id=m.movement_id
 AND tl.destination_warehouse_id=p_warehouse AND tl.variant_id=p_variant AND tl.quantity=m.quantity_delta
 AND cf.warehouse_id=tl.source_warehouse_id AND cf.variant_id=p_variant
 AND cf.quantity_delta=-m.quantity_delta AND cf.value_delta<=0
 AND vp.method=p_method AND vp.currency=p_currency;
 IF NOT FOUND THEN RAISE EXCEPTION 'Confirmed paired transfer outflow required' USING ERRCODE='23514'; END IF;
 IF p_method='fifo' THEN
 restored_qty:=0; restored_value:=0;
 FOR restored IN SELECT a.receipt_movement_id,a.quantity,a.cost
 FROM finance.fifo_cost_allocations a
 JOIN inventory.stock_ledger rl ON rl.tenant_id=a.tenant_id AND rl.movement_id=a.receipt_movement_id
 JOIN finance.receipt_cost_basis rb ON rb.tenant_id=a.tenant_id AND rb.movement_id=a.receipt_movement_id
 WHERE a.tenant_id=t AND a.outgoing_movement_id=transfer_source
 AND a.warehouse_id=transfer_source_wh AND a.variant_id=p_variant AND rb.invoice_id IS NOT NULL AND rb.currency=p_currency
 ORDER BY rl.recorded_at,rl.movement_id LOOP
 layer_qty:=array_append(layer_qty,restored.quantity::numeric);
 layer_cost:=array_append(layer_cost,restored.cost);
 source_ids:=array_append(source_ids,restored.receipt_movement_id);
 restored_qty:=restored_qty+restored.quantity; restored_value:=restored_value+restored.cost;
 END LOOP;
 IF restored_qty<>m.quantity_delta OR restored_value<>transferred_cost
 THEN RAISE EXCEPTION 'FIFO transfer allocation reconciliation failed' USING ERRCODE='23514'; END IF;
 END IF;
 cost:=transferred_cost; q:=q+m.quantity_delta; val:=val+cost;
 ELSIF m.adjustment_key LIKE 'sales-return:%' THEN
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
 IF m.adjustment_key LIKE 'transfer:%' THEN
 IF NOT EXISTS(SELECT 1 FROM inventory.transfer_lines tl
 WHERE tl.tenant_id=t AND tl.outgoing_movement_id=m.movement_id AND tl.source_warehouse_id=p_warehouse
 AND tl.variant_id=p_variant AND tl.quantity=-m.quantity_delta)
 THEN RAISE EXCEPTION 'Unsupported transfer cost outflow' USING ERRCODE='23514'; END IF;
 transfer_out:=true;
 END IF;
 IF (m.reservation_id IS NULL AND NOT transfer_out) OR q< -m.quantity_delta THEN
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
 q:=q+m.quantity_delta; val:=val-cost;
 IF NOT transfer_out THEN spent:=spent+cost; END IF;
 END IF;
 seq:=seq+1;
 RETURN QUERY SELECT seq,m.movement_id,m.quantity_delta,CASE WHEN m.quantity_delta>0 THEN cost ELSE -cost END,q,val,spent,confirmed,sources;
 END LOOP;
 IF NOT FOUND THEN RAISE EXCEPTION 'No visible stock history' USING ERRCODE='23503'; END IF;
END $$;
CREATE OR REPLACE FUNCTION finance.capture_transfer_costs(p_transfer uuid,p_variant uuid) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.valuation.capture'); tl inventory.transfer_lines%ROWTYPE;
 pol finance.valuation_policies%ROWTYPE; n bigint;
BEGIN
 IF p_transfer IS NULL OR p_variant IS NULL THEN RAISE EXCEPTION 'Transfer and variant required' USING ERRCODE='22023'; END IF;
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Transfer valuation access denied' USING ERRCODE='42501'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO pol FROM finance.valuation_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF NOT FOUND OR pol.method NOT IN ('moving_average','fifo') THEN RAISE EXCEPTION 'Supported valuation policy required' USING ERRCODE='23514'; END IF;
 SELECT * INTO STRICT tl FROM inventory.transfer_lines WHERE tenant_id=t AND transfer_id=p_transfer AND variant_id=p_variant;
 -- Same variant lock as every physical mutation. Both capture calls and pair checks are atomic.
 n:=finance.capture_movement_costs_internal(tl.source_warehouse_id,p_variant);
 n:=n+finance.capture_movement_costs_internal(tl.destination_warehouse_id,p_variant);
 PERFORM finance.assert_transfer_cost_pairs(t,tl.source_warehouse_id,p_variant);
 PERFORM finance.assert_transfer_cost_pairs(t,tl.destination_warehouse_id,p_variant);
 RETURN n;
END $$;
COMMIT;

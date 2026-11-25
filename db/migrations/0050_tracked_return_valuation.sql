-- 0050: exact full sellable tracked return reversals and historical layer restoration.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE OR REPLACE FUNCTION finance.reverse_inventory_cogs(p_sale_movement uuid,p_method text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cogs_return'); fact finance.movement_cost_facts%ROWTYPE;
 sale_item sales.order_items%ROWTYPE; original finance.journal_entries%ROWTYPE; ret sales.returns%ROWTYPE;
 movement inventory.stock_ledger%ROWTYPE; pol finance.valuation_policies%ROWTYPE; order_state text; reversal jsonb; v_original_cost numeric; n bigint; traced boolean; ev record; re record; replayed record; actual_sources jsonb; return_key text;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'COGS return access denied' USING ERRCODE='42501'; END IF;
 IF p_sale_movement IS NULL OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average','lot_fifo','serial_specific') THEN RAISE EXCEPTION 'Sale movement required' USING ERRCODE='22023'; END IF;
 SELECT * INTO fact FROM finance.movement_cost_facts WHERE tenant_id=t AND movement_id=p_sale_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Captured sale cost unavailable' USING ERRCODE='23503'; END IF;
 traced:=p_method IN ('lot_fifo','serial_specific');
 IF traced THEN
 SELECT * INTO STRICT ev FROM finance.tracked_movement_evidence(p_sale_movement);
 IF ev.evidence_kind<>'sale' OR ev.quantity_delta IS DISTINCT FROM fact.quantity_delta
 THEN RAISE EXCEPTION 'Tracked sale movement required' USING ERRCODE='23514'; END IF;
 SELECT i.* INTO STRICT sale_item FROM inventory.stock_ledger sl JOIN sales.order_items i
 ON i.tenant_id=sl.tenant_id AND i.reservation_id=sl.reservation_id
 WHERE sl.tenant_id=t AND sl.movement_id=p_sale_movement AND i.order_id=ev.order_id;
 ELSE
 SELECT i.* INTO sale_item FROM inventory.stock_ledger m JOIN sales.order_items i
 ON i.tenant_id=m.tenant_id AND i.reservation_id=m.reservation_id
 WHERE m.tenant_id=t AND m.movement_id=p_sale_movement AND m.quantity_delta=-i.quantity
 AND m.lot_id IS NULL AND m.serial_id IS NULL AND m.allocation_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ordinary sale movement required' USING ERRCODE='23514'; END IF;
 END IF;
 IF fact.quantity_delta>=0 OR fact.value_delta>=0 THEN RAISE EXCEPTION 'Positive captured sale cost required' USING ERRCODE='23514'; END IF;
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
 return_key:='sales-return:'||ret.return_id::text||':'||sale_item.item_id::text;
 IF traced THEN return_key:=return_key||':'||ev.allocation_id::text; END IF;
 SELECT * INTO movement FROM inventory.stock_ledger WHERE tenant_id=t
 AND adjustment_key=return_key
 AND warehouse_id=fact.warehouse_id AND variant_id=fact.variant_id AND quantity_delta=-fact.quantity_delta
 AND reason='full order return' AND reservation_id IS NULL AND allocation_id IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Exact sellable return movement required' USING ERRCODE='23514'; END IF;
 IF traced THEN
 SELECT * INTO STRICT re FROM finance.tracked_movement_evidence(movement.movement_id);
 IF re.evidence_kind<>'return' OR re.related_movement_id IS DISTINCT FROM p_sale_movement
 OR re.allocation_id IS DISTINCT FROM ev.allocation_id OR re.return_id IS DISTINCT FROM ret.return_id
 THEN RAISE EXCEPTION 'Tracked return identity mismatch' USING ERRCODE='23514'; END IF;
 SELECT rp.* INTO STRICT replayed FROM finance.replay_valuation_prefix(fact.warehouse_id,fact.variant_id,pol.currency,pol.method,p_sale_movement) rp
 WHERE rp.movement_id=p_sale_movement;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('receipt_movement_id',fa.receipt_movement_id,'quantity',fa.quantity,'cost',fa.cost) ORDER BY fa.receipt_movement_id),'[]'::jsonb)
 INTO actual_sources FROM finance.fifo_cost_allocations fa WHERE fa.tenant_id=t AND fa.outgoing_movement_id=p_sale_movement;
 IF replayed.all_receipts_invoiced IS DISTINCT FROM true OR replayed.step_no IS DISTINCT FROM fact.sequence_no
 OR replayed.quantity_delta IS DISTINCT FROM fact.quantity_delta OR replayed.value_delta IS DISTINCT FROM fact.value_delta
 OR replayed.fifo_sources IS DISTINCT FROM actual_sources
 THEN RAISE EXCEPTION 'Original tracked sale cost differs from replay' USING ERRCODE='23514'; END IF;
 ELSIF movement.lot_id IS NOT NULL OR movement.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Ordinary return identity required' USING ERRCODE='23514'; END IF;
 v_original_cost:=-fact.value_delta;
 SELECT count(*),jsonb_agg(jsonb_build_object('account_id',l.account_id,'amount',-l.amount) ORDER BY l.account_id)
 INTO n,reversal FROM finance.journal_lines l WHERE l.tenant_id=t AND l.entry_id=original.entry_id;
 IF n<>2 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=v_original_cost AND a.account_type='expense')
 OR NOT EXISTS(SELECT 1 FROM finance.journal_lines l JOIN finance.accounts a USING(tenant_id,account_id,currency)
 WHERE l.tenant_id=t AND l.entry_id=original.entry_id AND l.amount=-v_original_cost AND a.account_type='asset')
 THEN RAISE EXCEPTION 'Original COGS lines do not match captured cost' USING ERRCODE='23514'; END IF;
 RETURN finance.write_entry(t,'cogs-return:'||movement.movement_id::text,original.currency,CASE p_method WHEN 'fifo' THEN 'Confirmed FIFO full return reversal'
 WHEN 'moving_average' THEN 'Confirmed moving-average full return reversal'
 WHEN 'lot_fifo' THEN 'Confirmed lot FIFO full return reversal' ELSE 'Confirmed serial specific full return reversal' END,reversal,NULL,NULL);
END $$;
CREATE OR REPLACE FUNCTION finance.replay_valuation_prefix(p_warehouse uuid,p_variant uuid,p_currency text,p_method text,p_through uuid)
RETURNS TABLE(step_no bigint,movement_id uuid,quantity_delta bigint,value_delta numeric,on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean,fifo_sources jsonb)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE m record; t uuid:=iam.current_tenant_id(); q numeric:=0; val numeric:=0; spent numeric:=0;
 take_qty numeric; cost numeric; remaining numeric; idx integer:=1;
 layer_qty numeric[]:=ARRAY[]::numeric[]; layer_cost numeric[]:=ARRAY[]::numeric[];
 confirmed boolean:=true; seq bigint:=0; source_ids uuid[]:=ARRAY[]::uuid[]; sources jsonb; returned_sale record; restored record; restored_qty numeric; restored_value numeric; transfer_out boolean; transferred_cost numeric; transfer_source uuid; transfer_source_wh uuid; cutoff_at timestamptz; traced boolean; ev record; layer_lots uuid[]:=ARRAY[]::uuid[]; layer_serials uuid[]:=ARRAY[]::uuid[]; scan_idx integer;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Valuation access denied' USING ERRCODE='42501'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
 OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average','lot_fifo','serial_specific') THEN
 RAISE EXCEPTION 'Invalid valuation arguments' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.warehouses w WHERE w.tenant_id=t AND w.warehouse_id=p_warehouse)
 THEN RAISE EXCEPTION 'Warehouse unavailable' USING ERRCODE='23503'; END IF;
 traced:=p_method IN ('lot_fifo','serial_specific');
 IF traced AND (NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales'))
 THEN RAISE EXCEPTION 'Tracked valuation requires sales evidence access' USING ERRCODE='42501'; END IF;
 IF traced AND NOT EXISTS(SELECT 1 FROM finance.valuation_policies vp WHERE vp.tenant_id=t AND vp.variant_id=p_variant AND vp.method=p_method AND vp.currency=p_currency)
 THEN RAISE EXCEPTION 'Configured tracked policy required' USING ERRCODE='23514'; END IF;
 IF p_through IS NOT NULL THEN
 SELECT l.recorded_at INTO cutoff_at FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant AND l.movement_id=p_through;
 IF NOT FOUND THEN RAISE EXCEPTION 'Replay cutoff unavailable' USING ERRCODE='23503'; END IF;
 END IF;
 -- Same valuation engine, with an optional inclusive chronological cutoff.
 FOR m IN SELECT l.movement_id,l.quantity_delta,l.reservation_id,l.lot_id,l.serial_id,l.adjustment_key,
 b.movement_id AS receipt_movement,b.quantity AS receipt_qty,b.agreed_cost,b.currency,b.invoice_id
 FROM inventory.stock_ledger l LEFT JOIN finance.receipt_cost_basis b
 ON b.tenant_id=l.tenant_id AND b.movement_id=l.movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 AND (p_through IS NULL OR (l.recorded_at,l.movement_id)<=(cutoff_at,p_through))
 ORDER BY l.recorded_at,l.movement_id
 LOOP
 sources:='[]'::jsonb; transfer_out:=false;
 IF traced THEN
 SELECT * INTO STRICT ev FROM finance.tracked_movement_evidence(m.movement_id);
 IF (p_method='lot_fifo' AND (ev.lot_id IS NULL OR ev.serial_id IS NOT NULL))
 OR (p_method='serial_specific' AND ev.serial_id IS NULL)
 OR ev.evidence_kind NOT IN ('receipt','sale','transfer_out','transfer_in','return')
 THEN RAISE EXCEPTION 'Unsupported tracked valuation evidence' USING ERRCODE='23514'; END IF;
 ELSIF m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Ordinary method cannot value traced movements' USING ERRCODE='23514'; END IF;
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
 IF p_method='fifo' OR traced THEN
 restored_qty:=0; restored_value:=0;
 FOR restored IN SELECT a.receipt_movement_id,a.quantity,a.cost
 FROM finance.fifo_cost_allocations a
 JOIN inventory.stock_ledger rl ON rl.tenant_id=a.tenant_id AND rl.movement_id=a.receipt_movement_id
 JOIN finance.receipt_cost_basis rb ON rb.tenant_id=a.tenant_id AND rb.movement_id=a.receipt_movement_id
 WHERE a.tenant_id=t AND a.outgoing_movement_id=transfer_source
 AND a.warehouse_id=transfer_source_wh AND a.variant_id=p_variant AND rb.invoice_id IS NOT NULL AND rb.currency=p_currency
 AND (NOT traced OR (rb.lot_id IS NOT DISTINCT FROM m.lot_id AND rb.serial_id IS NOT DISTINCT FROM m.serial_id))
 ORDER BY rl.recorded_at,rl.movement_id LOOP
 layer_qty:=array_append(layer_qty,restored.quantity::numeric);
 layer_cost:=array_append(layer_cost,restored.cost);
 source_ids:=array_append(source_ids,restored.receipt_movement_id);
 IF traced THEN
 layer_lots:=array_append(layer_lots,m.lot_id);
 layer_serials:=array_append(layer_serials,m.serial_id);
 END IF;
 restored_qty:=restored_qty+restored.quantity; restored_value:=restored_value+restored.cost;
 END LOOP;
 IF restored_qty<>m.quantity_delta OR restored_value<>transferred_cost
 THEN RAISE EXCEPTION 'FIFO transfer allocation reconciliation failed' USING ERRCODE='23514'; END IF;
 END IF;
 cost:=transferred_cost; q:=q+m.quantity_delta; val:=val+cost;
 ELSIF m.adjustment_key LIKE 'sales-return:%' THEN
 IF NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Sales return evidence access denied' USING ERRCODE='42501'; END IF;
 -- Exact full return with already captured and reversed historical COGS.
 IF traced THEN
 SELECT cf.movement_id AS original_movement,cf.quantity_delta AS original_qty,cf.value_delta AS original_value
 INTO returned_sale
 FROM finance.movement_cost_facts cf
 JOIN finance.valuation_policies vp ON vp.tenant_id=cf.tenant_id AND vp.variant_id=cf.variant_id
 JOIN finance.journal_entries sj ON sj.tenant_id=cf.tenant_id AND sj.cogs_movement_id=cf.movement_id
 JOIN finance.journal_entries rj ON rj.tenant_id=cf.tenant_id AND rj.cogs_return_movement_id=m.movement_id
 WHERE cf.tenant_id=t AND cf.movement_id=ev.related_movement_id AND ev.evidence_kind='return'
 AND cf.warehouse_id=p_warehouse AND cf.variant_id=p_variant AND cf.sequence_no<=seq
 AND cf.quantity_delta=-m.quantity_delta AND cf.value_delta<0 AND vp.method=p_method AND vp.currency=p_currency
 AND sj.currency=p_currency AND rj.currency=p_currency
 AND (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=sj.entry_id)=2
 AND (SELECT count(*) FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=rj.entry_id)=2
 AND EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=sj.entry_id AND ac.account_type='asset' AND jl.amount=cf.value_delta)
 AND EXISTS(SELECT 1 FROM finance.journal_lines jl JOIN finance.accounts ac USING(tenant_id,account_id,currency)
 WHERE jl.tenant_id=t AND jl.entry_id=sj.entry_id AND ac.account_type='expense' AND jl.amount=-cf.value_delta)
 AND NOT EXISTS(SELECT 1 FROM finance.journal_lines jl WHERE jl.tenant_id=t AND jl.entry_id=sj.entry_id
 AND NOT EXISTS(SELECT 1 FROM finance.journal_lines rl WHERE rl.tenant_id=t AND rl.entry_id=rj.entry_id AND rl.account_id=jl.account_id AND rl.amount=-jl.amount));
 ELSE
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
 END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'Confirmed reversed return evidence with matching method required' USING ERRCODE='23514'; END IF;
 IF p_method='fifo' OR traced THEN
 restored_qty:=0; restored_value:=0;
 FOR restored IN SELECT a.receipt_movement_id,a.quantity,a.cost
 FROM finance.fifo_cost_allocations a
 JOIN inventory.stock_ledger rl ON rl.tenant_id=a.tenant_id AND rl.movement_id=a.receipt_movement_id
 JOIN finance.receipt_cost_basis rb ON rb.tenant_id=a.tenant_id AND rb.movement_id=a.receipt_movement_id
 WHERE a.tenant_id=t AND a.outgoing_movement_id=returned_sale.original_movement
 AND a.warehouse_id=p_warehouse AND a.variant_id=p_variant AND rb.invoice_id IS NOT NULL AND rb.currency=p_currency
 AND (NOT traced OR (rb.lot_id IS NOT DISTINCT FROM m.lot_id AND rb.serial_id IS NOT DISTINCT FROM m.serial_id))
 ORDER BY rl.recorded_at,rl.movement_id LOOP
 -- Append at return time, retaining original receipt identity and exact consumed cost.
 layer_qty:=array_append(layer_qty,restored.quantity::numeric);
 layer_cost:=array_append(layer_cost,restored.cost);
 source_ids:=array_append(source_ids,restored.receipt_movement_id);
 IF traced THEN
 layer_lots:=array_append(layer_lots,m.lot_id);
 layer_serials:=array_append(layer_serials,m.serial_id);
 END IF;
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
 IF p_method='fifo' OR traced THEN
 layer_qty:=array_append(layer_qty,m.quantity_delta::numeric);
 layer_cost:=array_append(layer_cost,m.agreed_cost);
 source_ids:=array_append(source_ids,m.movement_id);
 IF traced THEN
 layer_lots:=array_append(layer_lots,m.lot_id);
 layer_serials:=array_append(layer_serials,m.serial_id);
 END IF;
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
 IF traced THEN
 -- Select the earliest still-available layer for this exact physical identity.
 -- Other lots/serials may precede it globally, but may never be consumed here.
 idx:=NULL;
 FOR scan_idx IN 1..COALESCE(array_length(layer_qty,1),0) LOOP
 IF layer_qty[scan_idx]>0 AND layer_lots[scan_idx] IS NOT DISTINCT FROM m.lot_id
 AND layer_serials[scan_idx] IS NOT DISTINCT FROM m.serial_id THEN
 idx:=scan_idx; EXIT;
 END IF;
 END LOOP;
 IF idx IS NULL THEN RAISE EXCEPTION 'Missing matching traced cost layer' USING ERRCODE='23514'; END IF;
 END IF;
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
 IF p_method='fifo' OR traced THEN
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
 AND (l.adjustment_key='sales-return:'||sr.return_id::text||':'||si.item_id::text
 OR l.adjustment_key LIKE 'sales-return:'||sr.return_id::text||':'||si.item_id::text||':%')
 LEFT JOIN inventory.stock_ledger os ON os.tenant_id=si.tenant_id AND os.reservation_id=si.reservation_id
 AND os.quantity_delta=-l.quantity_delta AND os.warehouse_id=l.warehouse_id AND os.variant_id=l.variant_id
 AND os.lot_id IS NOT DISTINCT FROM l.lot_id AND os.serial_id IS NOT DISTINCT FROM l.serial_id
 AND l.adjustment_key='sales-return:'||sr.return_id::text||':'||si.item_id::text||COALESCE(':'||os.allocation_id::text,'')
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
 ('unsupported_movement',
 (CASE WHEN pol.method='lot_fifo' THEN m.lot_id IS NULL OR m.serial_id IS NOT NULL
 WHEN pol.method='serial_specific' THEN m.serial_id IS NULL
 ELSE m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL OR m.allocation_id IS NOT NULL END)
 OR NOT (m.receipt_mid IS NOT NULL OR m.transfer_in IS NOT NULL OR m.transfer_out IS NOT NULL
 OR (m.qty<0 AND m.reservation_id IS NOT NULL)
 OR (m.qty>0 AND COALESCE(m.adjustment_key LIKE 'sales-return:%',false)))),
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

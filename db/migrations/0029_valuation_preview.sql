-- 0026: read-only valuation candidate, not a posted accounting ledger.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.preview_inventory_valuation(p_warehouse uuid,p_variant uuid,p_currency text,p_method text)
RETURNS TABLE(on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE m record; t uuid:=iam.current_tenant_id(); q numeric:=0; val numeric:=0; spent numeric:=0;
 take_qty numeric; cost numeric; remaining numeric; idx integer:=1;
 layer_qty numeric[]:=ARRAY[]::numeric[]; layer_cost numeric[]:=ARRAY[]::numeric[];
 confirmed boolean:=true;
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
 FOR m IN SELECT l.movement_id,l.quantity_delta,l.reservation_id,l.lot_id,l.serial_id,
 b.movement_id AS receipt_movement,b.quantity AS receipt_qty,b.agreed_cost,b.currency,b.invoice_id
 FROM inventory.stock_ledger l LEFT JOIN finance.receipt_cost_basis b
 ON b.tenant_id=l.tenant_id AND b.movement_id=l.movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 ORDER BY l.recorded_at,l.movement_id
 LOOP
 IF m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Tracked valuation not supported in preview' USING ERRCODE='23514'; END IF;
 IF m.quantity_delta>0 THEN
 IF m.receipt_movement IS NULL OR m.receipt_qty IS DISTINCT FROM m.quantity_delta OR m.currency IS DISTINCT FROM p_currency
 OR m.agreed_cost IS NULL OR m.agreed_cost<0 OR m.agreed_cost='NaN'::numeric THEN
 RAISE EXCEPTION 'Unknown or incompatible receipt cost' USING ERRCODE='23514'; END IF;
 confirmed:=confirmed AND m.invoice_id IS NOT NULL;
 q:=q+m.quantity_delta; val:=val+m.agreed_cost;
 IF p_method='fifo' THEN
 layer_qty:=array_append(layer_qty,m.quantity_delta::numeric);
 layer_cost:=array_append(layer_cost,m.agreed_cost);
 END IF;
 ELSE
 IF m.reservation_id IS NULL OR q< -m.quantity_delta THEN
 RAISE EXCEPTION 'Unsupported or uncosted stock outflow' USING ERRCODE='23514'; END IF;
 remaining:= -m.quantity_delta; cost:=0;
 IF p_method='moving_average' THEN
 cost:=CASE WHEN remaining=q THEN val ELSE round(val*remaining/q,4) END;
 ELSE
 WHILE remaining>0 LOOP
 take_qty:=least(remaining,layer_qty[idx]);
 IF take_qty IS NULL OR take_qty<=0 THEN RAISE EXCEPTION 'Missing cost layer' USING ERRCODE='23514'; END IF;
 DECLARE part numeric; BEGIN
 part:=CASE WHEN take_qty=layer_qty[idx] THEN layer_cost[idx] ELSE round(layer_cost[idx]*take_qty/layer_qty[idx],4) END;
 cost:=cost+part; layer_qty[idx]:=layer_qty[idx]-take_qty; layer_cost[idx]:=layer_cost[idx]-part;
 END;
 remaining:=remaining-take_qty;
 IF layer_qty[idx]=0 THEN idx:=idx+1; END IF;
 END LOOP;
 END IF;
 q:=q+m.quantity_delta; val:=val-cost; spent:=spent+cost;
 END IF;
 END LOOP;
 IF NOT FOUND THEN RAISE EXCEPTION 'No visible stock history' USING ERRCODE='23503'; END IF;
 RETURN QUERY SELECT q,val,spent,confirmed;
END $$;
REVOKE ALL ON FUNCTION finance.preview_inventory_valuation(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.preview_inventory_valuation(uuid,uuid,text,text) TO upc_runtime;
COMMIT;

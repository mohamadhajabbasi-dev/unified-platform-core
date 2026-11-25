-- 0060: reject unsupported return allocation properties before normalization/replay.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE OR REPLACE FUNCTION sales.receive_full_return_allocated(p_order uuid,p_key text,p_reason text,p_allocations jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.return.receive'); o sales.orders%ROWTYPE; prior sales.returns%ROWTYPE;
 rid uuid; i record; m record; expected jsonb; norm jsonb; replay boolean;
 sold numeric; n bigint; expected_lines bigint:=0; expected_key text;
BEGIN
 IF p_order IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_reason IS NULL OR btrim(p_reason)='' THEN RAISE EXCEPTION 'Invalid return' USING ERRCODE='22023'; END IF;
 -- Return allocations have exactly the documented identity/quantity keys.
 -- jsonb_to_recordset silently ignores unknown keys; reject them here
 -- rather than treating explicit damaged/expired input as sellable.
 IF p_allocations IS NOT NULL THEN
  IF jsonb_typeof(p_allocations)<>'array' THEN
   RAISE EXCEPTION 'Invalid return allocations' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_allocations) AS a(line)
   WHERE jsonb_typeof(a.line)<>'object') THEN
   RAISE EXCEPTION 'Invalid return allocation object' USING ERRCODE='22023'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_allocations) AS a(line)
   WHERE (a.line - ARRAY['variant_id','lot_id','serial_id','quantity']::text[])<>'{}'::jsonb) THEN
   RAISE EXCEPTION 'Unsupported return allocation field' USING ERRCODE='22023'; END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-return-key',t,p_key)::text,0));
 PERFORM sales.lock_order(t,p_order);
 SELECT inventory.normalize_allocations(jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity))) INTO expected
 FROM sales.order_items oi JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id)
 WHERE oi.tenant_id=t AND oi.order_id=p_order HAVING count(*)>0;
 IF expected IS NOT NULL THEN
 IF p_allocations IS NULL THEN RAISE EXCEPTION 'Return must confirm original traced units' USING ERRCODE='23514'; END IF;
 norm:=inventory.normalize_allocations(p_allocations);
 IF norm IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Return allocation does not match fulfilled units' USING ERRCODE='23514'; END IF;
 ELSIF p_allocations IS NOT NULL THEN RAISE EXCEPTION 'Unexpected traced return allocations' USING ERRCODE='22023'; END IF;
 SELECT * INTO prior FROM sales.returns WHERE tenant_id=t AND request_key=p_key;
 replay:=FOUND;
 IF replay THEN
  IF prior.order_id<>p_order OR prior.reason<>p_reason THEN RAISE EXCEPTION 'Return idempotency conflict' USING ERRCODE='23505'; END IF;
  rid:=prior.return_id;
  -- Pre-0058 exact retry stays read-only; no implicit historical backfill.
  IF NOT EXISTS(SELECT 1 FROM sales.return_items WHERE tenant_id=t AND return_id=rid) THEN RETURN rid; END IF;
 END IF;
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF NOT replay AND o.state<>'fulfilled' THEN RAISE EXCEPTION 'Only fulfilled orders can receive a full return' USING ERRCODE='23514'; END IF;
 IF replay AND o.state NOT IN ('returned','refunded') THEN RAISE EXCEPTION 'Invalid full return replay state' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM sales.order_items WHERE tenant_id=t AND order_id=p_order) THEN
  RAISE EXCEPTION 'Order items missing' USING ERRCODE='23514'; END IF;
 IF NOT replay THEN
  IF EXISTS(SELECT 1 FROM sales.returns WHERE tenant_id=t AND order_id=p_order) THEN
   RAISE EXCEPTION 'Existing return unavailable for new receipt' USING ERRCODE='23514'; END IF;
  INSERT INTO sales.returns(tenant_id,order_id,request_key,reason,received_by)
  VALUES(t,p_order,p_key,p_reason,iam.current_user_id()) RETURNING return_id INTO rid;
 END IF;
 FOR i IN SELECT item_id,warehouse_id,variant_id,quantity,reservation_id FROM sales.order_items
  WHERE tenant_id=t AND order_id=p_order ORDER BY warehouse_id,variant_id LOOP
  IF NOT EXISTS(SELECT 1 FROM inventory.reservations r WHERE r.tenant_id=t AND r.reservation_id=i.reservation_id
   AND r.state='consumed' AND r.quantity=i.quantity AND r.warehouse_id=i.warehouse_id AND r.variant_id=i.variant_id)
  THEN RAISE EXCEPTION 'Consumed sale reservation required' USING ERRCODE='23514'; END IF;
  SELECT count(*),COALESCE(sum(-l.quantity_delta::numeric),0) INTO n,sold FROM inventory.stock_ledger l
   WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id;
  IF n=0 OR sold<>i.quantity THEN RAISE EXCEPTION 'Sale movement quantity mismatch' USING ERRCODE='23514'; END IF;
  -- Ordinary and tracked sales use the same canonical movement identity.
  IF EXISTS(SELECT 1 FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id
   AND (l.quantity_delta>=0 OR l.warehouse_id<>i.warehouse_id OR l.variant_id<>i.variant_id
    OR l.reason<>'reservation fulfillment' OR l.adjustment_key IS NOT NULL
    OR (l.allocation_id IS NULL AND (n<>1 OR l.lot_id IS NOT NULL OR l.serial_id IS NOT NULL
       OR EXISTS(SELECT 1 FROM inventory.reservation_allocations a WHERE a.tenant_id=t AND a.reservation_id=i.reservation_id)))
    OR (l.allocation_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM inventory.reservation_allocations a
       WHERE a.tenant_id=t AND a.reservation_id=i.reservation_id AND a.allocation_id=l.allocation_id
       AND a.warehouse_id=i.warehouse_id AND a.variant_id=i.variant_id AND a.quantity::numeric=-l.quantity_delta::numeric
       AND a.lot_id IS NOT DISTINCT FROM l.lot_id AND a.serial_id IS NOT DISTINCT FROM l.serial_id))))
  THEN RAISE EXCEPTION 'Invalid original sale movement evidence' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM inventory.reservation_allocations a WHERE a.tenant_id=t AND a.reservation_id=i.reservation_id
   AND NOT EXISTS(SELECT 1 FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id AND l.allocation_id=a.allocation_id))
  THEN RAISE EXCEPTION 'Missing original sale allocation' USING ERRCODE='23514'; END IF;
  IF NOT replay THEN
   PERFORM inventory.return_fulfilled_reservation(i.reservation_id,'sales-return:'||rid::text||':'||i.item_id::text);
  END IF;
  FOR m IN SELECT l.movement_id,l.quantity_delta,l.allocation_id,l.lot_id,l.serial_id,l.recorded_at
   FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id ORDER BY l.movement_id LOOP
   expected_key:='sales-return:'||rid::text||':'||i.item_id::text||COALESCE(':'||m.allocation_id::text,'');
   IF NOT EXISTS(SELECT 1 FROM inventory.stock_ledger r WHERE r.tenant_id=t AND r.adjustment_key=expected_key
     AND r.quantity_delta::numeric=-m.quantity_delta::numeric AND r.warehouse_id=i.warehouse_id AND r.variant_id=i.variant_id
     AND r.lot_id IS NOT DISTINCT FROM m.lot_id AND r.serial_id IS NOT DISTINCT FROM m.serial_id
     AND r.reservation_id IS NULL AND r.allocation_id IS NULL AND r.reason='full order return'
     AND (r.recorded_at,r.movement_id)>(m.recorded_at,m.movement_id))
   THEN RAISE EXCEPTION 'Exact full return movement required' USING ERRCODE='23514'; END IF;
   IF NOT replay THEN
    INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
    VALUES(t,rid,p_order,i.reservation_id,m.movement_id,-m.quantity_delta,'sellable');
   END IF;
   IF NOT EXISTS(SELECT 1 FROM sales.return_items ri WHERE ri.tenant_id=t AND ri.return_id=rid AND ri.order_id=p_order
    AND ri.reservation_id=i.reservation_id AND ri.sale_movement_id=m.movement_id
    AND ri.received_quantity::numeric=-m.quantity_delta::numeric AND ri.disposition='sellable')
   THEN RAISE EXCEPTION 'Exact full return line required' USING ERRCODE='23514'; END IF;
   expected_lines:=expected_lines+1;
  END LOOP;
 END LOOP;
 IF (SELECT count(*) FROM sales.return_items WHERE tenant_id=t AND return_id=rid)<>expected_lines
 OR (SELECT count(*) FROM inventory.stock_ledger WHERE tenant_id=t AND adjustment_key LIKE 'sales-return:'||rid::text||':%')<>expected_lines
 THEN RAISE EXCEPTION 'Unexpected full return evidence count' USING ERRCODE='23514'; END IF;
 IF NOT replay THEN UPDATE sales.orders SET state='returned' WHERE tenant_id=t AND order_id=p_order; END IF;
 RETURN rid;
END $$;
COMMIT;

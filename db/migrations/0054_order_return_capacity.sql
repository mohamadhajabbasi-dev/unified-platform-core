-- 0054: read-only return capacity for existing fulfilled sale movements.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.order_return_capacity(p_order uuid)
RETURNS TABLE(item_id uuid,sale_movement_id uuid,warehouse_id uuid,variant_id uuid,
 allocation_id uuid,lot_id uuid,serial_id uuid,sold_quantity bigint,returned_quantity bigint,
 remaining_quantity bigint,return_id uuid,return_movement_id uuid)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); o sales.orders%ROWTYPE; h sales.returns%ROWTYPE;
 i record; m record; r inventory.stock_ledger%ROWTYPE; ev record; ret_ev record;
 has_return boolean; expected_key text; sold_total numeric; returned_total numeric; n bigint; tracked boolean;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Return capacity access denied' USING ERRCODE='42501'; END IF;
 IF p_order IS NULL THEN RAISE EXCEPTION 'Order required' USING ERRCODE='22023'; END IF;
 SELECT * INTO o FROM sales.orders so WHERE so.tenant_id=t AND so.order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF o.state NOT IN ('fulfilled','returned','refunded') THEN
 RAISE EXCEPTION 'Fulfilled sale evidence required' USING ERRCODE='23514'; END IF;
 SELECT * INTO h FROM sales.returns sr WHERE sr.tenant_id=t AND sr.order_id=p_order;
 has_return:=FOUND;
 IF (o.state='fulfilled' AND has_return) OR (o.state IN ('returned','refunded') AND NOT has_return) THEN
 RAISE EXCEPTION 'Unsupported return lifecycle or unfulfilled refund' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM sales.order_items si WHERE si.tenant_id=t AND si.order_id=p_order) THEN
 RAISE EXCEPTION 'Order items missing' USING ERRCODE='23514'; END IF;
 FOR i IN SELECT si.* FROM sales.order_items si WHERE si.tenant_id=t AND si.order_id=p_order ORDER BY si.item_id LOOP
  IF NOT EXISTS(SELECT 1 FROM inventory.reservations rs WHERE rs.tenant_id=t AND rs.reservation_id=i.reservation_id
   AND rs.state='consumed' AND rs.quantity=i.quantity AND rs.warehouse_id=i.warehouse_id AND rs.variant_id=i.variant_id)
  THEN RAISE EXCEPTION 'Consumed reservation required' USING ERRCODE='23514'; END IF;
  SELECT count(*),COALESCE(sum(-l.quantity_delta::numeric),0) INTO n,sold_total
  FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id;
  IF n=0 OR sold_total<>i.quantity THEN RAISE EXCEPTION 'Sale quantity evidence mismatch' USING ERRCODE='23514'; END IF;
  returned_total:=0;
  FOR m IN SELECT l.* FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=i.reservation_id ORDER BY l.movement_id LOOP
   IF m.quantity_delta>=0 OR m.warehouse_id<>i.warehouse_id OR m.variant_id<>i.variant_id OR m.reason<>'reservation fulfillment' OR m.adjustment_key IS NOT NULL
   THEN RAISE EXCEPTION 'Invalid sale movement' USING ERRCODE='23514'; END IF;
   tracked:=m.allocation_id IS NOT NULL OR m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL;
   IF tracked THEN
    SELECT * INTO STRICT ev FROM finance.tracked_movement_evidence(m.movement_id);
    IF ev.evidence_kind<>'sale' OR ev.order_id IS DISTINCT FROM p_order OR ev.allocation_id IS DISTINCT FROM m.allocation_id
    THEN RAISE EXCEPTION 'Invalid traced sale evidence' USING ERRCODE='23514'; END IF;
   ELSE
    IF n<>1 OR m.quantity_delta<>-i.quantity OR EXISTS(SELECT 1 FROM inventory.reservation_allocations ra
     WHERE ra.tenant_id=t AND ra.reservation_id=i.reservation_id)
    THEN RAISE EXCEPTION 'Invalid ordinary sale evidence' USING ERRCODE='23514'; END IF;
   END IF;
   IF has_return THEN
    expected_key:='sales-return:'||h.return_id::text||':'||i.item_id::text||COALESCE(':'||m.allocation_id::text,'');
    SELECT * INTO r FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.adjustment_key=expected_key;
    IF NOT FOUND OR r.quantity_delta<>-m.quantity_delta OR r.warehouse_id<>m.warehouse_id OR r.variant_id<>m.variant_id
     OR r.lot_id IS DISTINCT FROM m.lot_id OR r.serial_id IS DISTINCT FROM m.serial_id OR r.reservation_id IS NOT NULL
     OR r.allocation_id IS NOT NULL OR r.reason<>'full order return' OR (r.recorded_at,r.movement_id)<=(m.recorded_at,m.movement_id)
    THEN RAISE EXCEPTION 'Exact full return evidence required' USING ERRCODE='23514'; END IF;
    IF tracked THEN
     SELECT * INTO STRICT ret_ev FROM finance.tracked_movement_evidence(r.movement_id);
     IF ret_ev.evidence_kind<>'return' OR ret_ev.related_movement_id IS DISTINCT FROM m.movement_id OR ret_ev.return_id IS DISTINCT FROM h.return_id
     THEN RAISE EXCEPTION 'Invalid traced return evidence' USING ERRCODE='23514'; END IF;
    END IF;
    returned_total:=returned_total+r.quantity_delta;
    RETURN QUERY SELECT i.item_id,m.movement_id,m.warehouse_id,m.variant_id,m.allocation_id,m.lot_id,m.serial_id,
      -m.quantity_delta,r.quantity_delta,0::bigint,h.return_id,r.movement_id;
   ELSE
    RETURN QUERY SELECT i.item_id,m.movement_id,m.warehouse_id,m.variant_id,m.allocation_id,m.lot_id,m.serial_id,
      -m.quantity_delta,0::bigint,-m.quantity_delta,NULL::uuid,NULL::uuid;
   END IF;
  END LOOP;
  IF has_return AND returned_total<>i.quantity THEN RAISE EXCEPTION 'Return quantity evidence mismatch' USING ERRCODE='23514'; END IF;
 END LOOP;
 -- No unknown or extra return movements may masquerade as valid evidence.
 IF has_return AND (SELECT count(*) FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.adjustment_key LIKE 'sales-return:'||h.return_id::text||':%')
  <> (SELECT count(*) FROM sales.order_items si JOIN inventory.stock_ledger l ON l.tenant_id=si.tenant_id AND l.reservation_id=si.reservation_id WHERE si.tenant_id=t AND si.order_id=p_order)
 THEN RAISE EXCEPTION 'Unexpected return movement count' USING ERRCODE='23514'; END IF;
EXCEPTION WHEN no_data_found OR too_many_rows THEN
 RAISE EXCEPTION 'Missing or ambiguous sale/return evidence' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION finance.order_return_capacity(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.order_return_capacity(uuid) TO upc_runtime;
COMMIT;

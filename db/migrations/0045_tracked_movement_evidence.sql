-- 0045: read-only exact evidence for traced inventory movements; not valuation activation.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.tracked_movement_evidence(p_movement uuid)
RETURNS TABLE(movement_id uuid,warehouse_id uuid,variant_id uuid,lot_id uuid,serial_id uuid,
 quantity_delta bigint,evidence_kind text,receipt_id uuid,invoice_id uuid,receipt_agreed_cost numeric,
 receipt_currency text,order_id uuid,allocation_id uuid,transfer_id uuid,related_movement_id uuid,return_id uuid)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); m inventory.stock_ledger%ROWTYPE; mode text; x record; n bigint;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Tracked evidence access denied' USING ERRCODE='42501'; END IF;
 IF p_movement IS NULL THEN RAISE EXCEPTION 'Movement required' USING ERRCODE='22023'; END IF;
 SELECT * INTO m FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.movement_id=p_movement;
 IF NOT FOUND THEN RAISE EXCEPTION 'Movement unavailable' USING ERRCODE='23503'; END IF;
 SELECT tp.tracking_mode INTO mode FROM inventory.tracking_policies tp WHERE tp.tenant_id=t AND tp.variant_id=m.variant_id;
 IF NOT FOUND OR NOT (
 (mode='lot' AND m.lot_id IS NOT NULL AND m.serial_id IS NULL)
 OR (mode='serial' AND m.serial_id IS NOT NULL AND m.quantity_delta IN (-1,1)
 AND EXISTS(SELECT 1 FROM inventory.serial_numbers sn WHERE sn.tenant_id=t AND sn.variant_id=m.variant_id
 AND sn.serial_id=m.serial_id AND sn.lot_id IS NOT DISTINCT FROM m.lot_id)))
 THEN RAISE EXCEPTION 'Tracked movement identity required' USING ERRCODE='23514'; END IF;
 IF m.quantity_delta>0 AND m.adjustment_key LIKE 'purchase-receipt:%' THEN
 SELECT rb.* INTO STRICT x FROM finance.receipt_cost_basis rb WHERE rb.tenant_id=t AND rb.movement_id=m.movement_id
 AND rb.warehouse_id=m.warehouse_id AND rb.variant_id=m.variant_id AND rb.quantity=m.quantity_delta
 AND rb.lot_id IS NOT DISTINCT FROM m.lot_id AND rb.serial_id IS NOT DISTINCT FROM m.serial_id
 AND rb.agreed_cost>=0 AND rb.agreed_cost<>'NaN'::numeric;
 IF m.reservation_id IS NOT NULL OR m.allocation_id IS NOT NULL OR m.reason<>'purchase receipt'
 THEN RAISE EXCEPTION 'Invalid receipt evidence' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT m.movement_id,m.warehouse_id,m.variant_id,m.lot_id,m.serial_id,m.quantity_delta,
 'receipt'::text,x.receipt_id,x.invoice_id,x.agreed_cost,x.currency,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid;
 ELSIF m.adjustment_key LIKE 'transfer:%' THEN
 SELECT tl.transfer_id AS tid,peer.movement_id AS peer_id INTO STRICT x
 FROM inventory.transfer_lines tl
 JOIN inventory.stock_ledger peer ON peer.tenant_id=tl.tenant_id AND peer.movement_id=
 CASE WHEN tl.outgoing_movement_id=m.movement_id THEN tl.incoming_movement_id ELSE tl.outgoing_movement_id END
 WHERE tl.tenant_id=t AND tl.variant_id=m.variant_id
 AND ((m.quantity_delta<0 AND tl.outgoing_movement_id=m.movement_id AND tl.source_warehouse_id=m.warehouse_id AND tl.destination_warehouse_id=peer.warehouse_id AND tl.quantity=-m.quantity_delta
 AND (m.recorded_at,m.movement_id)<(peer.recorded_at,peer.movement_id))
 OR (m.quantity_delta>0 AND tl.incoming_movement_id=m.movement_id AND tl.destination_warehouse_id=m.warehouse_id AND tl.source_warehouse_id=peer.warehouse_id AND tl.quantity=m.quantity_delta
 AND (peer.recorded_at,peer.movement_id)<(m.recorded_at,m.movement_id)))
 AND peer.variant_id=m.variant_id AND peer.quantity_delta=-m.quantity_delta
 AND peer.lot_id IS NOT DISTINCT FROM m.lot_id AND peer.serial_id IS NOT DISTINCT FROM m.serial_id
 AND peer.reservation_id IS NULL AND peer.allocation_id IS NULL
 AND peer.adjustment_key LIKE 'transfer:'||tl.transfer_id::text||':%' AND m.adjustment_key LIKE 'transfer:'||tl.transfer_id::text||':%'
 AND peer.reason='warehouse transfer';
 IF m.reservation_id IS NOT NULL OR m.allocation_id IS NOT NULL OR m.reason<>'warehouse transfer'
 THEN RAISE EXCEPTION 'Invalid transfer evidence' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT m.movement_id,m.warehouse_id,m.variant_id,m.lot_id,m.serial_id,m.quantity_delta,
 CASE WHEN m.quantity_delta<0 THEN 'transfer_out' ELSE 'transfer_in' END,NULL::uuid,NULL::uuid,NULL::numeric,NULL::text,
 NULL::uuid,NULL::uuid,x.tid,x.peer_id,NULL::uuid;
 ELSIF m.quantity_delta<0 AND m.reservation_id IS NOT NULL THEN
 SELECT si.order_id AS oid,ra.allocation_id AS aid INTO STRICT x
 FROM inventory.reservation_allocations ra JOIN inventory.reservations rs USING(tenant_id,reservation_id)
 JOIN sales.order_items si ON si.tenant_id=ra.tenant_id AND si.reservation_id=ra.reservation_id
 JOIN sales.orders o ON o.tenant_id=si.tenant_id AND o.order_id=si.order_id
 WHERE ra.tenant_id=t AND ra.reservation_id=m.reservation_id AND ra.allocation_id=m.allocation_id
 AND ra.warehouse_id=m.warehouse_id AND ra.variant_id=m.variant_id AND ra.quantity=-m.quantity_delta
 AND ra.lot_id IS NOT DISTINCT FROM m.lot_id AND ra.serial_id IS NOT DISTINCT FROM m.serial_id
 AND rs.state='consumed' AND o.state IN ('fulfilled','returned','refunded')
 AND si.quantity=(SELECT sum(a.quantity) FROM inventory.reservation_allocations a WHERE a.tenant_id=t AND a.reservation_id=ra.reservation_id)
 AND si.quantity=-(SELECT sum(l.quantity_delta) FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=ra.reservation_id);
 IF m.reason<>'reservation fulfillment' THEN RAISE EXCEPTION 'Invalid sale evidence' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT m.movement_id,m.warehouse_id,m.variant_id,m.lot_id,m.serial_id,m.quantity_delta,
 'sale'::text,NULL::uuid,NULL::uuid,NULL::numeric,NULL::text,x.oid,x.aid,NULL::uuid,NULL::uuid,NULL::uuid;
 ELSIF m.quantity_delta>0 AND m.adjustment_key LIKE 'sales-return:%' THEN
 SELECT si.order_id AS oid,ra.allocation_id AS aid,sr.return_id AS rid,sl.movement_id AS original_mid INTO STRICT x
 FROM sales.returns sr JOIN sales.order_items si ON si.tenant_id=sr.tenant_id AND si.order_id=sr.order_id
 JOIN sales.orders o ON o.tenant_id=si.tenant_id AND o.order_id=si.order_id
 JOIN inventory.reservation_allocations ra ON ra.tenant_id=si.tenant_id AND ra.reservation_id=si.reservation_id
 JOIN inventory.stock_ledger sl ON sl.tenant_id=ra.tenant_id AND sl.reservation_id=ra.reservation_id AND sl.allocation_id=ra.allocation_id
 JOIN inventory.reservations rs ON rs.tenant_id=ra.tenant_id AND rs.reservation_id=ra.reservation_id
 WHERE sr.tenant_id=t AND m.adjustment_key='sales-return:'||sr.return_id::text||':'||si.item_id::text||':'||ra.allocation_id::text
 AND ra.warehouse_id=m.warehouse_id AND ra.variant_id=m.variant_id AND ra.quantity=m.quantity_delta
 AND ra.lot_id IS NOT DISTINCT FROM m.lot_id AND ra.serial_id IS NOT DISTINCT FROM m.serial_id
 AND sl.warehouse_id=m.warehouse_id AND sl.variant_id=m.variant_id AND sl.quantity_delta=-m.quantity_delta
 AND sl.lot_id IS NOT DISTINCT FROM m.lot_id AND sl.serial_id IS NOT DISTINCT FROM m.serial_id
 AND sl.reason='reservation fulfillment' AND (sl.recorded_at,sl.movement_id)<(m.recorded_at,m.movement_id)
 AND rs.state='consumed' AND o.state IN ('returned','refunded')
 AND si.quantity=(SELECT sum(a.quantity) FROM inventory.reservation_allocations a WHERE a.tenant_id=t AND a.reservation_id=ra.reservation_id)
 AND si.quantity=-(SELECT sum(l.quantity_delta) FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.reservation_id=ra.reservation_id);
 IF m.reservation_id IS NOT NULL OR m.allocation_id IS NOT NULL OR m.reason<>'full order return'
 THEN RAISE EXCEPTION 'Invalid return evidence' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT m.movement_id,m.warehouse_id,m.variant_id,m.lot_id,m.serial_id,m.quantity_delta,
 'return'::text,NULL::uuid,NULL::uuid,NULL::numeric,NULL::text,x.oid,x.aid,NULL::uuid,x.original_mid,x.rid;
 ELSE
 RAISE EXCEPTION 'Unsupported tracked movement evidence' USING ERRCODE='23514';
 END IF;
EXCEPTION WHEN no_data_found OR too_many_rows THEN
 RAISE EXCEPTION 'Missing or ambiguous tracked source evidence' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION finance.tracked_movement_evidence(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.tracked_movement_evidence(uuid) TO upc_runtime;
COMMIT;

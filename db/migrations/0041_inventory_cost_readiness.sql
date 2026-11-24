-- 0041: read-only inventory-cost lifecycle reconciliation and explicit readiness guard.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.inventory_cost_issues(p_warehouse uuid,p_variant uuid)
RETURNS TABLE(movement_id uuid,issue_code text)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); pol finance.valuation_policies%ROWTYPE;
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
 sj.entry_id AS sale_entry,rj.entry_id AS return_entry,
 ti.incoming_movement_id AS transfer_in,ti.outgoing_movement_id AS transfer_in_peer,
 tout.outgoing_movement_id AS transfer_out,tout.incoming_movement_id AS transfer_out_peer,
 ci.value_delta AS incoming_peer_value,co.value_delta AS outgoing_peer_value
 FROM inventory.stock_ledger l
 LEFT JOIN finance.movement_cost_facts cf ON cf.tenant_id=l.tenant_id AND cf.movement_id=l.movement_id
 LEFT JOIN finance.receipt_cost_basis rb ON rb.tenant_id=l.tenant_id AND rb.movement_id=l.movement_id
 LEFT JOIN finance.journal_entries sj ON sj.tenant_id=l.tenant_id AND sj.cogs_movement_id=l.movement_id
 LEFT JOIN finance.journal_entries rj ON rj.tenant_id=l.tenant_id AND rj.cogs_return_movement_id=l.movement_id
 LEFT JOIN inventory.transfer_lines ti ON ti.tenant_id=l.tenant_id AND ti.incoming_movement_id=l.movement_id
 LEFT JOIN inventory.transfer_lines tout ON tout.tenant_id=l.tenant_id AND tout.outgoing_movement_id=l.movement_id
 LEFT JOIN finance.movement_cost_facts ci ON ci.tenant_id=l.tenant_id AND ci.movement_id=ti.outgoing_movement_id
 LEFT JOIN finance.movement_cost_facts co ON co.tenant_id=l.tenant_id AND co.movement_id=tout.incoming_movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 )
 SELECT m.mid,i.code FROM moves m CROSS JOIN LATERAL (
 VALUES
 ('cost_not_captured',m.captured_mid IS NULL),
 ('unsupported_movement',m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL OR m.allocation_id IS NOT NULL
 OR NOT (m.receipt_mid IS NOT NULL OR m.transfer_in IS NOT NULL OR m.transfer_out IS NOT NULL
 OR (m.qty<0 AND m.reservation_id IS NOT NULL) OR (m.qty>0 AND COALESCE(m.adjustment_key LIKE 'sales-return:%',false)))),
 ('purchase_invoice_missing',m.receipt_mid IS NOT NULL AND m.invoice_id IS NULL),
 ('purchase_cost_mismatch',m.receipt_mid IS NOT NULL AND (m.receipt_currency IS DISTINCT FROM pol.currency OR m.receipt_qty IS DISTINCT FROM m.qty
 OR (m.captured_mid IS NOT NULL AND m.cost IS DISTINCT FROM m.agreed_cost))),
 ('sale_cogs_missing',m.qty<0 AND m.reservation_id IS NOT NULL AND m.sale_entry IS NULL),
 ('return_reversal_missing',m.qty>0 AND COALESCE(m.adjustment_key LIKE 'sales-return:%',false) AND m.return_entry IS NULL),
 ('transfer_cost_unpaired',(m.transfer_in IS NOT NULL AND (m.cost IS NULL OR m.incoming_peer_value IS NULL OR m.cost IS DISTINCT FROM -m.incoming_peer_value))
 OR (m.transfer_out IS NOT NULL AND (m.cost IS NULL OR m.outgoing_peer_value IS NULL OR m.cost IS DISTINCT FROM -m.outgoing_peer_value))),
 ('zero_sale_cost_pending_policy',m.qty<0 AND m.reservation_id IS NOT NULL AND m.cost=0)
 ) i(code,problem) WHERE i.problem IS TRUE ORDER BY m.mid,i.code;
END $$;
REVOKE ALL ON FUNCTION finance.inventory_cost_issues(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.inventory_cost_issues(uuid,uuid) TO upc_runtime;
CREATE FUNCTION finance.assert_inventory_cost_ready(p_warehouse uuid,p_variant uuid) RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE first_issue record;
BEGIN
 SELECT * INTO first_issue FROM finance.inventory_cost_issues(p_warehouse,p_variant) LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Inventory cost lifecycle incomplete: %',first_issue.issue_code USING ERRCODE='23514'; END IF;
END $$;
REVOKE ALL ON FUNCTION finance.assert_inventory_cost_ready(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.assert_inventory_cost_ready(uuid,uuid) TO upc_runtime;
COMMIT;

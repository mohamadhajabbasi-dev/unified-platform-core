-- 0046: experimental immutable tracked valuation methods; no activation of costing.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
ALTER TABLE finance.valuation_policies DROP CONSTRAINT valuation_policies_method_check;
ALTER TABLE finance.valuation_policies ADD CONSTRAINT valuation_policies_method_check
 CHECK(method IN ('fifo','moving_average','lot_fifo','serial_specific'));
CREATE OR REPLACE FUNCTION finance.configure_valuation_preview(p_variant uuid,p_method text,p_currency text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.read'); prior finance.valuation_policies%ROWTYPE; tracking text;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('finance.valuation.configure')
 OR NOT platform.module_enabled('finance') THEN RAISE EXCEPTION 'Valuation configuration denied' USING ERRCODE='42501'; END IF;
 IF p_variant IS NULL OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average','lot_fifo','serial_specific')
 OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Invalid valuation policy' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO prior FROM finance.valuation_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF FOUND THEN
 IF prior.method<>p_method OR prior.currency<>p_currency THEN RAISE EXCEPTION 'Valuation policy immutable' USING ERRCODE='23505'; END IF;
 RETURN p_variant;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
 WHERE v.tenant_id=t AND v.variant_id=p_variant AND p.kind='physical' AND p.is_active AND v.is_active)
 THEN RAISE EXCEPTION 'Physical variant unavailable' USING ERRCODE='23503'; END IF;
 IF EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id=t AND variant_id=p_variant)
 OR EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id=t AND variant_id=p_variant)
 THEN RAISE EXCEPTION 'Preview policy requires unused variant' USING ERRCODE='23514'; END IF;
 SELECT tp.tracking_mode INTO tracking FROM inventory.tracking_policies tp WHERE tp.tenant_id=t AND tp.variant_id=p_variant;
 IF (tracking IS NULL AND p_method NOT IN ('fifo','moving_average'))
 OR (tracking='lot' AND p_method<>'lot_fifo')
 OR (tracking='serial' AND p_method<>'serial_specific')
 THEN RAISE EXCEPTION 'Valuation method must match physical tracking policy' USING ERRCODE='23514'; END IF;
 -- The method is an explicit experimental policy; enrollment does not activate replay or posting.
 INSERT INTO finance.valuation_policies(tenant_id,variant_id,method,currency,configured_by)
 VALUES(t,p_variant,p_method,p_currency,iam.current_user_id());
 RETURN p_variant;
END $$;
CREATE OR REPLACE FUNCTION inventory.configure_tracking(p_variant uuid,p_mode text,p_expiry boolean DEFAULT false) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.trace.configure'); prior inventory.tracking_policies%ROWTYPE;
BEGIN
 IF p_variant IS NULL OR p_mode IS NULL OR p_mode NOT IN ('lot','serial') OR p_expiry IS NULL
 THEN RAISE EXCEPTION 'Invalid tracking policy' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO prior FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF FOUND THEN
 IF prior.tracking_mode<>p_mode OR prior.expiry_required<>p_expiry THEN RAISE EXCEPTION 'Tracking policy immutable' USING ERRCODE='23505'; END IF;
 RETURN p_variant;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
 WHERE v.tenant_id=t AND v.variant_id=p_variant AND p.kind='physical' AND p.is_active AND v.is_active)
 THEN RAISE EXCEPTION 'Physical variant unavailable' USING ERRCODE='23503'; END IF;
 IF EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id=t AND variant_id=p_variant)
 OR EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id=t AND variant_id=p_variant)
 THEN RAISE EXCEPTION 'Tracking requires a new unused variant; migration workflow pending' USING ERRCODE='23514'; END IF;
 -- Prevent the opposite enrollment order from creating an ordinary costing policy
 -- on a newly tracked variant. Same variant lock serializes both policy writers.
 IF EXISTS(SELECT 1 FROM finance.valuation_policies vp WHERE vp.tenant_id=t AND vp.variant_id=p_variant)
 THEN RAISE EXCEPTION 'Tracking must precede tracked valuation enrollment' USING ERRCODE='23514'; END IF;
 INSERT INTO inventory.tracking_policies(tenant_id,variant_id,tracking_mode,expiry_required,configured_by)
 VALUES(t,p_variant,p_mode,p_expiry,iam.current_user_id());
 RETURN p_variant;
END $$;
CREATE OR REPLACE FUNCTION finance.configured_inventory_preview(p_warehouse uuid,p_variant uuid)
RETURNS TABLE(on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE pol finance.valuation_policies%ROWTYPE;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Valuation access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO pol FROM finance.valuation_policies WHERE tenant_id=iam.current_tenant_id() AND variant_id=p_variant;
 IF NOT FOUND THEN RAISE EXCEPTION 'Valuation policy unavailable' USING ERRCODE='23503'; END IF;
 IF pol.method IN ('lot_fifo','serial_specific') THEN
 RAISE EXCEPTION 'Tracked valuation engine not enabled' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT * FROM finance.preview_inventory_valuation(p_warehouse,p_variant,pol.currency,pol.method);
END $$;
COMMIT;

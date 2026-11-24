-- 0027: immutable preview policy, not activation of financial posting.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('finance.valuation.configure','Configure experimental inventory valuation policy');
CREATE TABLE finance.valuation_policies(
 tenant_id uuid NOT NULL, variant_id uuid NOT NULL,
 method text NOT NULL CHECK(method IN ('fifo','moving_average')),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 configured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 configured_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
ALTER TABLE finance.valuation_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.valuation_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY valuation_read ON finance.valuation_policies FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('finance.read') AND platform.module_enabled('finance')
 AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory'));
CREATE POLICY valuation_private ON finance.valuation_policies FOR ALL TO upc_inventory_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT USAGE ON SCHEMA finance TO upc_inventory_executor;
GRANT SELECT ON finance.valuation_policies TO upc_runtime,upc_inventory_executor;
GRANT INSERT ON finance.valuation_policies TO upc_inventory_executor;
CREATE FUNCTION finance.configure_valuation_preview(p_variant uuid,p_method text,p_currency text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.read'); prior finance.valuation_policies%ROWTYPE;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('finance.valuation.configure')
 OR NOT platform.module_enabled('finance') THEN RAISE EXCEPTION 'Valuation configuration denied' USING ERRCODE='42501'; END IF;
 IF p_variant IS NULL OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average')
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
 OR EXISTS(SELECT 1 FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant)
 THEN RAISE EXCEPTION 'Preview policy requires unused ordinary variant' USING ERRCODE='23514'; END IF;
 INSERT INTO finance.valuation_policies(tenant_id,variant_id,method,currency,configured_by)
 VALUES(t,p_variant,p_method,p_currency,iam.current_user_id());
 RETURN p_variant;
END $$;
ALTER FUNCTION finance.configure_valuation_preview(uuid,text,text) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION finance.configure_valuation_preview(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.configure_valuation_preview(uuid,text,text) TO upc_runtime;
CREATE FUNCTION finance.configured_inventory_preview(p_warehouse uuid,p_variant uuid)
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
 RETURN QUERY SELECT * FROM finance.preview_inventory_valuation(p_warehouse,p_variant,pol.currency,pol.method);
END $$;
REVOKE ALL ON FUNCTION finance.configured_inventory_preview(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.configured_inventory_preview(uuid,uuid) TO upc_runtime;
COMMIT;

-- 0051: read-only conservative inventory close preflight; not a close gate.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.inventory_period_close_issues(p_period uuid)
RETURNS TABLE(issue_code text,warehouse_id uuid,variant_id uuid,movement_id uuid,account_id uuid,currency text)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); p finance.fiscal_periods%ROWTYPE; boundary timestamptz;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.period.manage')
 OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Inventory period preflight access denied' USING ERRCODE='42501'; END IF;
 IF p_period IS NULL THEN RAISE EXCEPTION 'Period required' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM finance.fiscal_periods fp WHERE fp.tenant_id=t AND fp.period_id=p_period;
 IF NOT FOUND THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='23503'; END IF;
 boundary:=upper(p.dates)::timestamp AT TIME ZONE 'UTC';
 IF p.closed_at IS NOT NULL THEN
 RETURN QUERY SELECT 'period_already_closed'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text;
 END IF;
 IF statement_timestamp()<boundary THEN
 RETURN QUERY SELECT 'period_end_not_reached'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text;
 END IF;
 -- The current reconciliation is cumulative, not historical as-of. Do not claim
 -- period readiness if later inventory activity has entered the ledger.
 IF EXISTS(SELECT 1 FROM inventory.stock_ledger l WHERE l.tenant_id=t AND l.recorded_at>=boundary) THEN
 RETURN QUERY SELECT 'inventory_movements_after_period'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text;
 END IF;
 IF EXISTS(SELECT 1 FROM finance.journal_entries j WHERE j.tenant_id=t AND j.posted_at>=boundary
 AND (j.supplier_invoice_id IS NOT NULL OR j.cogs_movement_id IS NOT NULL OR j.cogs_return_movement_id IS NOT NULL)) THEN
 RETURN QUERY SELECT 'inventory_journals_after_period'::text,NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,NULL::text;
 END IF;
 -- Preserve actionable current-state diagnostics, explicitly not a historical
 -- snapshot. Existing currency separation and missing-policy checks are reused.
 RETURN QUERY SELECT i.issue_code,i.warehouse_id,i.variant_id,i.movement_id,i.account_id,i.currency
 FROM finance.tenant_inventory_cost_issues() i;
END $$;
REVOKE ALL ON FUNCTION finance.inventory_period_close_issues(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.inventory_period_close_issues(uuid) TO upc_runtime;
COMMIT;

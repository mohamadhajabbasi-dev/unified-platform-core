-- 0055: provisional temporal safety guards for the existing atomic close.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
-- Single canonical entitlement decision implementation; private overload
-- accepts an explicit observation time. Existing public signature keeps
-- statement semantics and ACL; arbitrary-time query is NOT a runtime API.
CREATE FUNCTION platform.module_enabled(p_module_key text,p_at timestamptz) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $$
 SELECT COALESCE((
   SELECT p_at IS NOT NULL AND g.enabled AND (g.expires_at IS NULL OR g.expires_at > p_at)
   FROM platform.tenant_module_grants g JOIN platform.modules m USING(module_id)
   WHERE g.tenant_id=iam.current_tenant_id() AND m.module_key=p_module_key
   ORDER BY g.decision_id DESC LIMIT 1
 ),false)
$$;
ALTER FUNCTION platform.module_enabled(text,timestamptz) OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION platform.module_enabled(text,timestamptz) FROM PUBLIC,upc_runtime;
GRANT EXECUTE ON FUNCTION platform.module_enabled(text,timestamptz) TO upc_finance_executor;
CREATE OR REPLACE FUNCTION platform.module_enabled(p_module_key text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT platform.module_enabled(p_module_key,statement_timestamp())
$$;
CREATE OR REPLACE FUNCTION finance.inventory_period_close_issues(p_period uuid)
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
 -- A pre-cutoff movement captured at/after the exclusive UTC boundary
 -- is unresolved historical evidence, not an approved adjusting entry.
 RETURN QUERY SELECT 'inventory_cost_captured_after_period'::text,cf.warehouse_id,cf.variant_id,cf.movement_id,NULL::uuid,vp.currency
 FROM finance.movement_cost_facts cf JOIN inventory.stock_ledger l
 ON l.tenant_id=cf.tenant_id AND l.movement_id=cf.movement_id
 JOIN finance.valuation_policies vp ON vp.tenant_id=cf.tenant_id AND vp.variant_id=cf.variant_id
 WHERE cf.tenant_id=t AND l.recorded_at<boundary AND cf.captured_at>=boundary;
 -- Preserve actionable current-state diagnostics, explicitly not a historical
 -- snapshot. Existing currency separation and missing-policy checks are reused.
 RETURN QUERY SELECT i.issue_code,i.warehouse_id,i.variant_id,i.movement_id,i.account_id,i.currency
 FROM finance.tenant_inventory_cost_issues() i;
END $$;
CREATE OR REPLACE FUNCTION finance.close_period(p_period uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.period.manage'); p finance.fiscal_periods%ROWTYPE; k bigint; issue text;
 has_history boolean; checked_at timestamptz;
BEGIN
 IF NOT iam.has_permission('finance.read') THEN RAISE EXCEPTION 'Finance read required' USING ERRCODE='42501'; END IF;
 IF p_period IS NULL THEN RAISE EXCEPTION 'Period required' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM finance.fiscal_periods WHERE tenant_id=t AND period_id=p_period;
 IF NOT FOUND THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='23503'; END IF;
 -- Keep the existing read-only retry and RLS contract. A new close
 -- additionally requires live finance entitlement.
 IF p.closed_at IS NULL AND NOT platform.module_enabled('finance',clock_timestamp())
 THEN RAISE EXCEPTION 'Finance module expired before close' USING ERRCODE='42501'; END IF;
 -- Exact retry is read-only; preserve the original close timestamp.
 IF p.closed_at IS NOT NULL THEN RETURN p_period; END IF;
 IF statement_timestamp()< (upper(p.dates)::timestamp AT TIME ZONE 'UTC') THEN
 RAISE EXCEPTION 'Fiscal period has not ended' USING ERRCODE='23514'; END IF;
 k:=hashtextextended(jsonb_build_array('inventory-period-barrier',t)::text,0);
 IF EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' AND granted AND mode IN ('ShareLock','ExclusiveLock')
 AND classid=((k>>32)&4294967295)::oid AND objid=(k&4294967295)::oid AND objsubid=1)
 THEN RAISE EXCEPTION 'Close requires its own transaction without prior tenant mutations' USING ERRCODE='25000'; END IF;
 PERFORM finance.try_inventory_period_barrier(t,true);
 -- Preserve the old journal/period lock namespace, but never wait while exclusive.
 IF NOT pg_try_advisory_xact_lock(hashtextextended(jsonb_build_array('finance-period',t)::text,0))
 THEN RAISE EXCEPTION 'Fiscal period lock busy; retry transaction' USING ERRCODE='55P03'; END IF;
 -- VOLATILE function, READ COMMITTED: fresh reads after acquiring both locks.
 IF finance.require_access('finance.period.manage') IS DISTINCT FROM t OR NOT iam.has_permission('finance.read')
 THEN RAISE EXCEPTION 'Close access changed' USING ERRCODE='42501'; END IF;
 SELECT * INTO p FROM finance.fiscal_periods WHERE tenant_id=t AND period_id=p_period;
 IF NOT FOUND THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='23503'; END IF;
 IF p.closed_at IS NOT NULL THEN RETURN p_period; END IF;
 -- Inspect actual tenant rows through the existing private executor policies.
 -- Disabled modules are never treated as proof of empty history.
 SELECT EXISTS(SELECT 1 FROM inventory.stock_ledger l WHERE l.tenant_id=t)
 OR EXISTS(SELECT 1 FROM finance.movement_cost_facts cf WHERE cf.tenant_id=t)
 OR EXISTS(SELECT 1 FROM finance.supplier_invoices si WHERE si.tenant_id=t)
 OR EXISTS(SELECT 1 FROM finance.journal_entries j WHERE j.tenant_id=t
 AND (j.supplier_invoice_id IS NOT NULL OR j.cogs_movement_id IS NOT NULL OR j.cogs_return_movement_id IS NOT NULL))
 INTO has_history;
 checked_at:=clock_timestamp();
 IF NOT platform.module_enabled('finance',checked_at) OR (has_history AND
 (NOT platform.module_enabled('inventory',checked_at) OR NOT platform.module_enabled('procurement',checked_at)
 OR NOT platform.module_enabled('sales',checked_at)))
 THEN RAISE EXCEPTION 'Required module expired at close barrier' USING ERRCODE='42501'; END IF;
 IF has_history THEN
 SELECT i.issue_code INTO issue FROM finance.inventory_period_close_issues(p_period) i LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Inventory period close blocked: %',issue USING ERRCODE='23514'; END IF;
 END IF;
 -- Provisional fail-closed live check at write and after triggers. No
 -- general change to statement-time RLS or claim about commit-time expiry.
 checked_at:=clock_timestamp();
 IF NOT platform.module_enabled('finance',checked_at) OR (has_history AND
 (NOT platform.module_enabled('inventory',checked_at) OR NOT platform.module_enabled('procurement',checked_at)
 OR NOT platform.module_enabled('sales',checked_at)))
 THEN RAISE EXCEPTION 'Required module expired during close' USING ERRCODE='42501'; END IF;
 UPDATE finance.fiscal_periods SET closed_at=checked_at,closed_by=iam.current_user_id() WHERE tenant_id=t AND period_id=p_period;
 checked_at:=clock_timestamp();
 IF NOT platform.module_enabled('finance',checked_at) OR (has_history AND
 (NOT platform.module_enabled('inventory',checked_at) OR NOT platform.module_enabled('procurement',checked_at)
 OR NOT platform.module_enabled('sales',checked_at)))
 THEN RAISE EXCEPTION 'Required module expired during close' USING ERRCODE='42501'; END IF;
 RETURN p_period;
END $$;
COMMIT;

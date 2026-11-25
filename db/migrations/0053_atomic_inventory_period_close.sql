-- 0053: conservative atomic close using the one existing fiscal period API.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
GRANT EXECUTE ON FUNCTION finance.inventory_period_close_issues(uuid),
 finance.tenant_inventory_cost_issues(),finance.tenant_inventory_cost_totals(),
 finance.tenant_inventory_asset_activity(),finance.inventory_cost_issues(uuid,uuid) TO upc_finance_executor;
-- A closing transaction cannot subsequently mutate the reconciled data, including
-- acquiring its own shared lock. The only exception is the exact period close update.
CREATE OR REPLACE FUNCTION finance.guard_inventory_period_mutation() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE tid uuid; k bigint;
BEGIN
 IF TG_OP='DELETE' THEN tid:=OLD.tenant_id;
 ELSIF TG_OP='UPDATE' THEN
 IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN RAISE EXCEPTION 'Tenant identity immutable' USING ERRCODE='42501'; END IF;
 tid:=NEW.tenant_id;
 ELSE tid:=NEW.tenant_id; END IF;
 k:=hashtextextended(jsonb_build_array('inventory-period-barrier',tid)::text,0);
 IF EXISTS(SELECT 1 FROM pg_locks WHERE pid=pg_backend_pid() AND locktype='advisory' AND granted AND mode='ExclusiveLock'
 AND classid=((k>>32)&4294967295)::oid AND objid=(k&4294967295)::oid AND objsubid=1) THEN
 IF TG_RELID='finance.fiscal_periods'::regclass AND TG_OP='UPDATE' THEN
  IF OLD.closed_at IS NULL AND NEW.closed_at IS NOT NULL AND NEW.closed_by IS NOT NULL THEN RETURN NEW; END IF;
 END IF;
 RAISE EXCEPTION 'Close transaction must not mutate tenant data' USING ERRCODE='25000';
 END IF;
 PERFORM finance.try_inventory_period_barrier(tid,false);
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION finance.close_period(p_period uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.period.manage'); p finance.fiscal_periods%ROWTYPE; k bigint; issue text;
 has_history boolean;
BEGIN
 IF NOT iam.has_permission('finance.read') THEN RAISE EXCEPTION 'Finance read required' USING ERRCODE='42501'; END IF;
 IF p_period IS NULL THEN RAISE EXCEPTION 'Period required' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM finance.fiscal_periods WHERE tenant_id=t AND period_id=p_period;
 IF NOT FOUND THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='23503'; END IF;
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
 IF has_history THEN
 SELECT i.issue_code INTO issue FROM finance.inventory_period_close_issues(p_period) i LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Inventory period close blocked: %',issue USING ERRCODE='23514'; END IF;
 END IF;
 UPDATE finance.fiscal_periods SET closed_at=clock_timestamp(),closed_by=iam.current_user_id() WHERE tenant_id=t AND period_id=p_period;
 RETURN p_period;
END $$;
COMMIT;

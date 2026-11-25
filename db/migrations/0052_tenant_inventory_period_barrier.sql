-- 0052: private tenant transaction barrier; existing close_period behavior unchanged.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.try_inventory_period_barrier(p_tenant uuid,p_exclusive boolean) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE k bigint; acquired boolean;
BEGIN
 IF p_tenant IS NULL OR p_exclusive IS NULL THEN RAISE EXCEPTION 'Barrier scope required' USING ERRCODE='22023'; END IF;
 -- The future closer must see a fresh snapshot after obtaining exclusivity.
 -- Shared writers retain their existing API-specific isolation rules.
 IF p_exclusive AND current_setting('transaction_isolation')<>'read committed' THEN
 RAISE EXCEPTION 'Exclusive inventory period barrier requires READ COMMITTED' USING ERRCODE='25000'; END IF;
 k:=hashtextextended(jsonb_build_array('inventory-period-barrier',p_tenant)::text,0);
 IF p_exclusive THEN acquired:=pg_try_advisory_xact_lock(k);
 ELSE acquired:=pg_try_advisory_xact_lock_shared(k); END IF;
 IF NOT acquired THEN RAISE EXCEPTION 'Tenant inventory period barrier busy; retry transaction' USING ERRCODE='55P03'; END IF;
END $$;
ALTER FUNCTION finance.try_inventory_period_barrier(uuid,boolean) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.try_inventory_period_barrier(uuid,boolean) FROM PUBLIC,upc_runtime;
-- Private trigger only obtains a lock, reads/writes no protected data. Tenant comes
-- from the row after existing authorization checks, including cross-tenant module decisions.
CREATE FUNCTION finance.guard_inventory_period_mutation() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE tid uuid;
BEGIN
 IF TG_OP='DELETE' THEN tid:=OLD.tenant_id;
 ELSIF TG_OP='UPDATE' THEN
 IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN RAISE EXCEPTION 'Tenant identity immutable' USING ERRCODE='42501'; END IF;
 tid:=NEW.tenant_id;
 ELSE tid:=NEW.tenant_id; END IF;
 PERFORM finance.try_inventory_period_barrier(tid,false);
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 RETURN NEW;
END $$;
ALTER FUNCTION finance.guard_inventory_period_mutation() OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.guard_inventory_period_mutation() FROM PUBLIC,upc_runtime;
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY[
 'inventory.stock_ledger'::regclass,
 'finance.valuation_policies'::regclass,
 'finance.movement_cost_facts'::regclass,
 'finance.fifo_cost_allocations'::regclass,
 'procurement.purchase_orders'::regclass,
 'procurement.purchase_items'::regclass,
 'procurement.goods_receipts'::regclass,
 'procurement.receipt_items'::regclass,
 'finance.supplier_invoices'::regclass,
 'finance.journal_entries'::regclass,
 'finance.journal_lines'::regclass,
 'finance.accounts'::regclass,
 'inventory.transfer_lines'::regclass,
 'inventory.warehouse_transfers'::regclass,
 'inventory.tracking_policies'::regclass,
 'inventory.serial_numbers'::regclass,
 'inventory.inventory_lots'::regclass,
 'inventory.reservations'::regclass,
 'inventory.reservation_allocations'::regclass,
 'sales.orders'::regclass,
 'sales.order_items'::regclass,
 'sales.returns'::regclass,
 'inventory.warehouses'::regclass,
 'catalog.products'::regclass,
 'catalog.variants'::regclass,
 'platform.tenant_module_grants'::regclass,
 'iam.memberships'::regclass,
 'iam.db_principals'::regclass,
 'iam.roles'::regclass,
 'iam.role_grants'::regclass,
 'iam.membership_roles'::regclass,
 'finance.fiscal_periods'::regclass
 ] LOOP
 EXECUTE format('CREATE TRIGGER inventory_period_mutation_barrier BEFORE INSERT OR UPDATE OR DELETE ON %s FOR EACH ROW EXECUTE FUNCTION finance.guard_inventory_period_mutation()',rel);
 END LOOP;
END $$;
COMMIT;

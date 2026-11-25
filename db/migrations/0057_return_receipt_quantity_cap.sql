-- 0057: atomic aggregate receipt-line cap; dormant relation stays dormant.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
-- No new role, ACL, public writer, table, balance or counter.
-- The existing order lock serializes all receipt lines for the same order.
-- SECURITY INVOKER: no authority to see/write rows is added by this trigger.
-- Any future writer MUST have full tenant-scoped evidence visibility and
-- use the same order lock; it is not enabled by this migration.
CREATE FUNCTION sales.guard_return_item_quantity() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE sold numeric; used numeric;
BEGIN
 IF TG_OP<>'INSERT' THEN
  RAISE EXCEPTION 'Return receipt lines are append-only' USING ERRCODE='23514';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Return receipt quantity requires READ COMMITTED' USING ERRCODE='25000';
 END IF;
 -- Preserve the existing NOT NULL and CHECK constraint SQLSTATEs.
 IF NEW.tenant_id IS NULL OR NEW.order_id IS NULL OR NEW.return_id IS NULL
 OR NEW.reservation_id IS NULL OR NEW.sale_movement_id IS NULL
 OR NEW.received_quantity IS NULL OR NEW.received_quantity<=0
 OR NEW.disposition IS NULL OR NEW.disposition NOT IN ('sellable','damaged','expired')
 THEN RETURN NEW; END IF;
 PERFORM sales.lock_order(NEW.tenant_id,NEW.order_id);
 -- Fresh snapshot after lock. Prove exact tenant/order/header/reservation
 -- provenance before computing the cap; existing composite FKs stay enforced.
 SELECT -l.quantity_delta::numeric INTO sold
 FROM sales.returns h
 JOIN sales.order_items i ON i.tenant_id=h.tenant_id AND i.order_id=h.order_id
 JOIN inventory.stock_ledger l ON l.tenant_id=i.tenant_id AND l.reservation_id=i.reservation_id
 WHERE h.tenant_id=NEW.tenant_id AND h.order_id=NEW.order_id AND h.return_id=NEW.return_id
 AND i.reservation_id=NEW.reservation_id AND l.movement_id=NEW.sale_movement_id;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Return receipt identity unavailable' USING ERRCODE='23503';
 END IF;
 IF sold IS NULL OR sold<=0 THEN RAISE EXCEPTION 'Original sale quantity invalid' USING ERRCODE='23514'; END IF;
 -- Aggregate across all headers/dispositions, never count a legacy return
 -- ledger row a second time. This is a cap on the new fact, NOT a complete
 -- physical eligibility or valuation/refund decision.
 SELECT COALESCE(sum(ri.received_quantity::numeric),0) INTO used
 FROM sales.return_items ri
 WHERE ri.tenant_id=NEW.tenant_id AND ri.sale_movement_id=NEW.sale_movement_id;
 IF used+NEW.received_quantity::numeric>sold THEN
  RAISE EXCEPTION 'Return receipt quantity exceeds original sale movement' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION sales.guard_return_item_quantity() FROM PUBLIC,upc_runtime;
-- Existing inventory_period_mutation_barrier fires first alphabetically.
CREATE TRIGGER return_items_quantity_guard BEFORE INSERT OR UPDATE OR DELETE ON sales.return_items
 FOR EACH ROW EXECUTE FUNCTION sales.guard_return_item_quantity();
COMMIT;

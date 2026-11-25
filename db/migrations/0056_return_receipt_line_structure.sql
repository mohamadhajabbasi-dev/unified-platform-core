-- 0056: dormant normalized return receipt line; no runtime write path.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
-- Existing PKs and uniqueness stay intact. These exact superkeys allow
-- composite FKs to enforce tenant/order/reservation identity.
ALTER TABLE sales.returns ADD CONSTRAINT returns_order_return_identity
 UNIQUE(tenant_id,order_id,return_id);
ALTER TABLE sales.order_items ADD CONSTRAINT order_items_order_reservation_identity
 UNIQUE(tenant_id,order_id,reservation_id);
ALTER TABLE inventory.stock_ledger ADD CONSTRAINT stock_ledger_movement_reservation_identity
 UNIQUE(tenant_id,movement_id,reservation_id);
-- An independent physical inspection/receipt fact, NOT another product,
-- order, inventory balance or cost master. Derive item/variant/warehouse/
-- trace identity through the original sale movement and order reservation.
-- This phase deliberately has no writer/backfill and does not approve
-- disposition, quarantine, accounting or refund policy.
CREATE TABLE sales.return_items (
 tenant_id uuid NOT NULL,
 return_item_id uuid NOT NULL DEFAULT gen_random_uuid(),
 return_id uuid NOT NULL,
 order_id uuid NOT NULL,
 reservation_id uuid NOT NULL,
 sale_movement_id uuid NOT NULL,
 received_quantity bigint NOT NULL CHECK(received_quantity>0),
 disposition text NOT NULL CHECK(disposition IN ('sellable','damaged','expired')),
 PRIMARY KEY(tenant_id,return_item_id),
 UNIQUE(tenant_id,return_id,sale_movement_id,disposition),
 FOREIGN KEY(tenant_id,order_id,return_id)
  REFERENCES sales.returns(tenant_id,order_id,return_id),
 FOREIGN KEY(tenant_id,order_id,reservation_id)
  REFERENCES sales.order_items(tenant_id,order_id,reservation_id),
 FOREIGN KEY(tenant_id,sale_movement_id,reservation_id)
  REFERENCES inventory.stock_ledger(tenant_id,movement_id,reservation_id)
);
-- Non-null reservation on original stock_ledger row implies a negative
-- fulfillment movement under its existing CHECK. Remaining quantity/cap,
-- exact evidence and state require a future atomic canonical writer;
-- a row CHECK/unique constraint does not enforce an aggregate cap.
ALTER TABLE sales.return_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.return_items FORCE ROW LEVEL SECURITY;
CREATE POLICY sales_read ON sales.return_items FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('sales.read') AND platform.module_enabled('sales'));
REVOKE ALL ON sales.return_items FROM PUBLIC,upc_runtime,upc_sales_executor,upc_inventory_executor,upc_finance_executor;
GRANT SELECT ON sales.return_items TO upc_runtime;
CREATE TRIGGER inventory_period_mutation_barrier BEFORE INSERT OR UPDATE OR DELETE ON sales.return_items
 FOR EACH ROW EXECUTE FUNCTION finance.guard_inventory_period_mutation();
COMMIT;

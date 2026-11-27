-- 0094: dormant fixed asset identity register, distinct from sellable stock.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE inventory.stock_assets (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 asset_id uuid NOT NULL DEFAULT gen_random_uuid(),
 asset_key text NOT NULL CHECK(asset_key ~ '^[a-z0-9][a-z0-9_.-]{0,99}$'),
 display_name text NOT NULL CHECK(display_name=btrim(display_name) AND length(display_name) BETWEEN 1 AND 300),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,asset_id),
 UNIQUE(tenant_id,asset_key)
);
ALTER TABLE inventory.stock_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.stock_assets FORCE ROW LEVEL SECURITY;
REVOKE ALL ON inventory.stock_assets FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_inventory_executor,upc_reorder_executor,upc_procurement_executor,upc_finance_executor,upc_finance_checker,upc_outbox_capture;
COMMENT ON TABLE inventory.stock_assets IS 'Dormant identity for individual internal fixed assets; not catalog, sellable stock, inventory balance, asset custody, financial recognition or depreciation.';
COMMIT;

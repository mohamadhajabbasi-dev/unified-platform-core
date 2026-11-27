-- 0092: dormant procurement planning facts, not purchase commitments or stock movements.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE procurement.procurement_requests (
 tenant_id uuid NOT NULL,
 request_id uuid NOT NULL DEFAULT gen_random_uuid(),
 request_key uuid NOT NULL,
 warehouse_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,request_id),
 UNIQUE(tenant_id,request_key),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id)
);
CREATE INDEX procurement_requests_warehouse_idx ON procurement.procurement_requests(tenant_id,warehouse_id);
CREATE TABLE procurement.procurement_request_items (
 tenant_id uuid NOT NULL,
 request_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 requested_units bigint NOT NULL CHECK(requested_units>0),
 PRIMARY KEY(tenant_id,request_id,variant_id),
 FOREIGN KEY(tenant_id,request_id) REFERENCES procurement.procurement_requests(tenant_id,request_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE INDEX procurement_request_items_variant_idx ON procurement.procurement_request_items(tenant_id,variant_id);
ALTER TABLE procurement.procurement_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE procurement.procurement_requests FORCE ROW LEVEL SECURITY;
ALTER TABLE procurement.procurement_request_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE procurement.procurement_request_items FORCE ROW LEVEL SECURITY;
REVOKE ALL ON procurement.procurement_requests,procurement.procurement_request_items FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_procurement_executor,upc_inventory_executor,upc_reorder_executor,upc_outbox_capture;
COMMENT ON TABLE procurement.procurement_requests IS 'Dormant synthetic planning identity; no approval, purchase commitment, actor verification or automatic stock effect.';
COMMENT ON TABLE procurement.procurement_request_items IS 'Dormant whole-unit planning quantity, not a reservation or physical movement; quantity/eligibility/lifecycle policy pending.';
COMMIT;

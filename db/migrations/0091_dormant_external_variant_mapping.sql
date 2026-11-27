-- 0091: dormant external variant identity mapping; no catalog mirror or legacy sync.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.external_variant_mappings (
 tenant_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 external_variant_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,connection_id,external_variant_id),
 FOREIGN KEY(tenant_id,connection_id) REFERENCES ops.integration_connections(tenant_id,connection_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE INDEX external_variant_mappings_variant_idx ON ops.external_variant_mappings(tenant_id,variant_id);
ALTER TABLE ops.external_variant_mappings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.external_variant_mappings FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.external_variant_mappings FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.external_variant_mappings IS 'Dormant synthetic external variant identity relation; canonical variant FK only; no price, inventory, product mirror, provider identifier normalization or runtime authority.';
COMMIT;

-- 0090: dormant external adapter identity and inbound synthetic deduplication facts.
-- Not an ERP/Commerce sync mechanism, provider verifier, payload store or worker.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.integration_connections (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 connection_id uuid NOT NULL DEFAULT gen_random_uuid(),
 connection_key text NOT NULL CHECK(connection_key ~ '^[a-z][a-z0-9_.-]{0,79}$'),
 adapter_key text NOT NULL CHECK(adapter_key ~ '^[a-z][a-z0-9_.-]{0,79}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,connection_id),
 UNIQUE(tenant_id,connection_key)
);
CREATE TABLE ops.inbound_inbox (
 tenant_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 source_event_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,connection_id,source_event_id),
 FOREIGN KEY(tenant_id,connection_id) REFERENCES ops.integration_connections(tenant_id,connection_id)
);
ALTER TABLE ops.integration_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.integration_connections FORCE ROW LEVEL SECURITY;
ALTER TABLE ops.inbound_inbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.inbound_inbox FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.integration_connections,ops.inbound_inbox FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.integration_connections IS 'Dormant external adapter identity only; synthetic keys, no provider credentials, endpoint, status, sync or runtime authority.';
COMMENT ON TABLE ops.inbound_inbox IS 'Dormant inbound deduplication metadata; synthetic opaque UUID scoped to connection, not verified receipt, payload, processing or provider identifier contract.';
COMMIT;

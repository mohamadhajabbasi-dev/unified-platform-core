-- 0100: dormant API credential metadata, never a credential or authentication mechanism.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE iam.api_credentials_metadata (
 tenant_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 credential_id uuid NOT NULL DEFAULT gen_random_uuid(),
 vault_reference_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,credential_id),
 FOREIGN KEY(tenant_id,connection_id) REFERENCES ops.integration_connections(tenant_id,connection_id),
 UNIQUE(vault_reference_id)
);
CREATE INDEX api_credentials_connection_idx ON iam.api_credentials_metadata(tenant_id,connection_id);
ALTER TABLE iam.api_credentials_metadata ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.api_credentials_metadata FORCE ROW LEVEL SECURITY;
REVOKE ALL ON iam.api_credentials_metadata FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE iam.api_credentials_metadata IS 'Dormant synthetic connection credential metadata; opaque globally unique reference UUID only, not a vault locator or secret. No lookup, authentication, credential generation, rotation, shared secret or runtime authority. Ownership and reference contract provisional.';
COMMIT;

-- 0101: dormant inbound webhook registration identity, not endpoint or delivery.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.webhook_registrations (
 tenant_id uuid NOT NULL,
 connection_id uuid NOT NULL,
 registration_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,connection_id,registration_id),
 FOREIGN KEY(tenant_id,connection_id) REFERENCES ops.integration_connections(tenant_id,connection_id)
);
ALTER TABLE ops.webhook_registrations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.webhook_registrations FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.webhook_registrations FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.webhook_registrations IS 'Dormant synthetic inbound registration identity, scoped to existing connection; not a URL, routing key, credential, event, signature verifier or provider identifier contract. No runtime authority, worker, delivery or new inbox.';
COMMIT;

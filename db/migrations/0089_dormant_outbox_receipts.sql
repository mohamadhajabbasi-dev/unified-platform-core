-- 0089: dormant consumer/receipt relations for the single existing transactional outbox.
-- No worker, delivery, acknowledgement authorization or retention policy.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.outbox_consumers (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 consumer_id uuid NOT NULL DEFAULT gen_random_uuid(),
 consumer_key text NOT NULL CHECK(consumer_key ~ '^[a-z][a-z0-9_.-]{0,79}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,consumer_id),
 UNIQUE(tenant_id,consumer_key)
);
CREATE TABLE ops.outbox_consumer_receipts (
 tenant_id uuid NOT NULL,
 consumer_id uuid NOT NULL,
 event_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,consumer_id,event_id),
 FOREIGN KEY(tenant_id,consumer_id) REFERENCES ops.outbox_consumers(tenant_id,consumer_id),
 FOREIGN KEY(tenant_id,event_id) REFERENCES ops.outbox_events(tenant_id,event_id)
);
CREATE INDEX outbox_receipts_event_idx ON ops.outbox_consumer_receipts(tenant_id,event_id);
ALTER TABLE ops.outbox_consumers ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_consumers FORCE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_consumer_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_consumer_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.outbox_consumers,ops.outbox_consumer_receipts FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.outbox_consumers IS 'Dormant internal consumer identity; no connection, endpoint, secrets or operational rights.';
COMMENT ON TABLE ops.outbox_consumer_receipts IS 'Dormant synthetic receipt relation, not proof of delivery; one consumer/event pair, no commit-order cursor or delivery worker.';
COMMIT;

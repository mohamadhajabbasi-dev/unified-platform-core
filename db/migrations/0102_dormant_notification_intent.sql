-- 0102: dormant internal member notification intent, not delivery or permission.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.notifications (
 tenant_id uuid NOT NULL,
 event_id uuid NOT NULL,
 user_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,event_id,user_id),
 FOREIGN KEY(tenant_id,event_id) REFERENCES ops.outbox_events(tenant_id,event_id),
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id) ON DELETE CASCADE
);
CREATE INDEX notifications_member_idx ON ops.notifications(tenant_id,user_id,event_id);
ALTER TABLE ops.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.notifications FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.notifications FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.notifications IS 'Dormant synthetic internal tenant-member notification intent; one relation per event/member, not audience eligibility, consent, rendered message, customer notification, delivery, read status or queue. Membership deletion cascade preserves membership removal; retention contract provisional.';
COMMIT;

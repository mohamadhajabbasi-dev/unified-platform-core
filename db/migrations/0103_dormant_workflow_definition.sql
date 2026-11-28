-- 0103: dormant tenant workflow definition identity, not an execution engine.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.workflow_definitions (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 workflow_id uuid NOT NULL DEFAULT gen_random_uuid(),
 workflow_key text NOT NULL CHECK(workflow_key ~ '^[a-z][a-z0-9_.-]{0,79}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,workflow_id),
 UNIQUE(tenant_id,workflow_key)
);
ALTER TABLE ops.workflow_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.workflow_definitions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.workflow_definitions FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.workflow_definitions IS 'Dormant synthetic tenant-scoped logical workflow identity only. No executable rules, versions, publication, triggers, steps, runs, queue, scheduling, domain authority or runtime grants. Key and lifecycle contracts provisional.';
COMMIT;

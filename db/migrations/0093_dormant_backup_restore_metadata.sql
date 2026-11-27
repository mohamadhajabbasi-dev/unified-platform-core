-- 0093: dormant synthetic backup snapshot identity and restore intent; no actual backup or restore.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.backup_snapshots (
 tenant_id uuid NOT NULL,
 snapshot_id uuid NOT NULL DEFAULT gen_random_uuid(),
 job_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,snapshot_id),
 FOREIGN KEY(tenant_id,job_id) REFERENCES ops.tenant_backup_jobs(tenant_id,job_id)
);
CREATE INDEX backup_snapshots_job_idx ON ops.backup_snapshots(tenant_id,job_id);
CREATE TABLE ops.restore_requests (
 tenant_id uuid NOT NULL,
 restore_request_id uuid NOT NULL DEFAULT gen_random_uuid(),
 request_key uuid NOT NULL CHECK(request_key<>'00000000-0000-0000-0000-000000000000'::uuid),
 snapshot_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,restore_request_id),
 UNIQUE(request_key),
 FOREIGN KEY(tenant_id,snapshot_id) REFERENCES ops.backup_snapshots(tenant_id,snapshot_id)
);
CREATE INDEX restore_requests_snapshot_idx ON ops.restore_requests(tenant_id,snapshot_id);
ALTER TABLE ops.backup_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.backup_snapshots FORCE ROW LEVEL SECURITY;
ALTER TABLE ops.restore_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.restore_requests FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.backup_snapshots,ops.restore_requests FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_backup_request_executor,upc_outbox_capture;
COMMENT ON TABLE ops.backup_snapshots IS 'Dormant synthetic identity only; not proof of a backup, storage, checksum, completeness, or recoverability.';
COMMENT ON TABLE ops.restore_requests IS 'Dormant synthetic restore intent; no verified actor, authorization, restore operation or lifecycle.';
COMMIT;

-- 0071: tenant backup request metadata only; no worker, storage, backup or restore operation.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_backup_request_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE ops.tenant_backup_jobs (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 job_id uuid NOT NULL DEFAULT gen_random_uuid(),
 request_key uuid NOT NULL CHECK(request_key<>'00000000-0000-0000-0000-000000000000'::uuid),
 requested_by uuid NOT NULL REFERENCES core.users(user_id),
 requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,job_id),
 UNIQUE(request_key)
);
CREATE INDEX backup_jobs_tenant_requested_idx ON ops.tenant_backup_jobs(tenant_id,requested_at,job_id);
ALTER TABLE ops.tenant_backup_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.tenant_backup_jobs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.tenant_backup_jobs FROM PUBLIC;
GRANT USAGE ON SCHEMA ops,iam TO upc_backup_request_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_backup_request_executor;
GRANT SELECT ON iam.platform_staff_assignments TO upc_backup_request_executor;
-- Only this non-login executor may use the approved platform path; no tenant role receives access.
CREATE POLICY backup_request_select ON ops.tenant_backup_jobs FOR SELECT TO upc_backup_request_executor
 USING(iam.current_tenant_id() IS NULL AND EXISTS(SELECT 1 FROM iam.platform_staff_assignments a
  WHERE a.login_role=session_user::name AND a.is_superadmin AND a.revoked_at IS NULL));
CREATE POLICY backup_request_insert ON ops.tenant_backup_jobs FOR INSERT TO upc_backup_request_executor
 WITH CHECK(iam.current_tenant_id() IS NULL AND EXISTS(SELECT 1 FROM iam.platform_staff_assignments a
  WHERE a.login_role=session_user::name AND a.is_superadmin AND a.revoked_at IS NULL AND a.user_id=requested_by));
GRANT SELECT ON ops.tenant_backup_jobs TO upc_backup_request_executor;
GRANT INSERT(tenant_id,request_key,requested_by) ON ops.tenant_backup_jobs TO upc_backup_request_executor;
-- Existing audit relation; restricted platform insert only for a matching request and actual platform actor.
CREATE POLICY backup_request_audit_insert ON ops.audit_events FOR INSERT TO upc_backup_request_executor
 WITH CHECK(event_type='insert' AND entity_type='ops.tenant_backup_jobs'
 AND iam.current_tenant_id() IS NULL
 AND EXISTS(SELECT 1 FROM iam.platform_staff_assignments a WHERE a.login_role=session_user::name
  AND a.is_superadmin AND a.revoked_at IS NULL AND a.user_id=ops.audit_events.actor_user_id)
 AND EXISTS(SELECT 1 FROM ops.tenant_backup_jobs b WHERE b.tenant_id=ops.audit_events.tenant_id
  AND b.job_id=ops.audit_events.entity_id AND b.requested_by=ops.audit_events.actor_user_id));
GRANT INSERT(tenant_id,actor_user_id,event_type,entity_type,entity_id) ON ops.audit_events TO upc_backup_request_executor;
CREATE FUNCTION ops.request_tenant_backup(p_tenant uuid,p_request_key uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid; prior ops.tenant_backup_jobs%ROWTYPE; jid uuid;
BEGIN
 SELECT user_id INTO actor FROM iam.platform_staff_assignments
 WHERE login_role=session_user::name AND is_superadmin AND revoked_at IS NULL;
 IF actor IS NULL OR iam.current_tenant_id() IS NOT NULL THEN RAISE EXCEPTION 'Platform superadmin required' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_tenant IS NULL OR p_request_key IS NULL OR p_request_key='00000000-0000-0000-0000-000000000000'::uuid
 THEN RAISE EXCEPTION 'Invalid backup request' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('ops-tenant-backup-request',p_request_key)::text,0));
 IF iam.current_tenant_id() IS NOT NULL OR NOT EXISTS(SELECT 1 FROM iam.platform_staff_assignments
 WHERE login_role=session_user::name AND user_id=actor AND is_superadmin AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'Platform superadmin required' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM ops.tenant_backup_jobs WHERE request_key=p_request_key;
 IF FOUND THEN
  IF prior.tenant_id IS DISTINCT FROM p_tenant OR prior.requested_by IS DISTINCT FROM actor
  THEN RAISE EXCEPTION 'Backup request key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.job_id;
 END IF;
 INSERT INTO ops.tenant_backup_jobs(tenant_id,request_key,requested_by) VALUES(p_tenant,p_request_key,actor) RETURNING job_id INTO jid;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(p_tenant,actor,'insert','ops.tenant_backup_jobs',jid);
 RETURN jid;
END $$;
ALTER FUNCTION ops.request_tenant_backup(uuid,uuid) OWNER TO upc_backup_request_executor;
REVOKE ALL ON FUNCTION ops.request_tenant_backup(uuid,uuid) FROM PUBLIC;
CREATE FUNCTION ops.list_tenant_backup_requests(p_tenant uuid) RETURNS TABLE(job_id uuid,request_key uuid,requested_by uuid,requested_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF iam.current_tenant_id() IS NOT NULL OR NOT EXISTS(SELECT 1 FROM iam.platform_staff_assignments
 WHERE login_role=session_user::name AND is_superadmin AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'Platform superadmin required' USING ERRCODE='42501'; END IF;
 IF p_tenant IS NULL THEN RAISE EXCEPTION 'Invalid tenant' USING ERRCODE='22023'; END IF;
 RETURN QUERY SELECT b.job_id,b.request_key,b.requested_by,b.requested_at FROM ops.tenant_backup_jobs b
 WHERE b.tenant_id=p_tenant ORDER BY b.requested_at,b.job_id;
END $$;
ALTER FUNCTION ops.list_tenant_backup_requests(uuid) OWNER TO upc_backup_request_executor;
REVOKE ALL ON FUNCTION ops.list_tenant_backup_requests(uuid) FROM PUBLIC;
GRANT USAGE ON SCHEMA ops TO upc_platform_approver;
GRANT EXECUTE ON FUNCTION ops.request_tenant_backup(uuid,uuid),ops.list_tenant_backup_requests(uuid) TO upc_platform_approver;
COMMIT;

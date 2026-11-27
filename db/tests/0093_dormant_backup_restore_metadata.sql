\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_recovery_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_recovery_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_recovery_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_recovery_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_recovery_a,upc_recovery_b,upc_recovery_unmapped;
GRANT upc_platform_approver TO upc_recovery_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0930000-0000-0000-0000-000000000001','recovery-a','Synthetic A'),
 ('a0930000-0000-0000-0000-000000000002','recovery-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0930000-0000-0000-0000-000000000001','test','recovery-a'),
 ('b0930000-0000-0000-0000-000000000002','test','recovery-b'),
 ('b0930000-0000-0000-0000-000000000003','test','recovery-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0930000-0000-0000-0000-000000000001','b0930000-0000-0000-0000-000000000001'),
 ('a0930000-0000-0000-0000-000000000002','b0930000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_recovery_a','a0930000-0000-0000-0000-000000000001','b0930000-0000-0000-0000-000000000001'),
 ('upc_recovery_b','a0930000-0000-0000-0000-000000000002','b0930000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_recovery_platform','b0930000-0000-0000-0000-000000000003',true);
SET SESSION AUTHORIZATION upc_recovery_platform;
SELECT ops.request_tenant_backup('a0930000-0000-0000-0000-000000000001','d0930000-0000-0000-0000-000000000001');
SELECT ops.request_tenant_backup('a0930000-0000-0000-0000-000000000002','d0930000-0000-0000-0000-000000000002');
RESET SESSION AUTHORIZATION;
DO $$
DECLARE a uuid:='a0930000-0000-0000-0000-000000000001'; b uuid:='a0930000-0000-0000-0000-000000000002';
 sa uuid:='e0930000-0000-0000-0000-000000000001'; sb uuid:='e0930000-0000-0000-0000-000000000002';
 k uuid:='f0930000-0000-0000-0000-000000000001';
 ja uuid; jb uuid; rel regclass; jobs_before jsonb; audit_before jsonb; events_before jsonb;
BEGIN
 SELECT job_id INTO STRICT ja FROM ops.tenant_backup_jobs WHERE tenant_id=a;
 SELECT job_id INTO STRICT jb FROM ops.tenant_backup_jobs WHERE tenant_id=b;
 SELECT jsonb_agg(to_jsonb(j) ORDER BY tenant_id,job_id) INTO jobs_before FROM ops.tenant_backup_jobs j WHERE tenant_id IN(a,b);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) INTO audit_before FROM ops.audit_events x WHERE tenant_id IN(a,b);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) INTO events_before FROM ops.outbox_events x WHERE tenant_id IN(a,b);
 INSERT INTO ops.backup_snapshots(tenant_id,snapshot_id,job_id) VALUES(a,sa,ja),(b,sb,jb);
 INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(a,k,sa);
 BEGIN INSERT INTO ops.backup_snapshots(tenant_id,snapshot_id,job_id) VALUES(a,sa,ja);
  RAISE EXCEPTION 'FAIL duplicate snapshot'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.backup_snapshots(tenant_id,job_id) VALUES(a,jb);
  RAISE EXCEPTION 'FAIL cross-tenant backup job'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(a,gen_random_uuid(),sb);
  RAISE EXCEPTION 'FAIL cross-tenant snapshot'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(a,k,sa);
  RAISE EXCEPTION 'FAIL duplicate restore key'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(b,k,sb);
  RAISE EXCEPTION 'FAIL cross-tenant key conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(a,'00000000-0000-0000-0000-000000000000',sa);
  RAISE EXCEPTION 'FAIL zero restore key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN DELETE FROM ops.backup_snapshots WHERE tenant_id=a AND snapshot_id=sa;
  RAISE EXCEPTION 'FAIL referenced snapshot deletion'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(b,gen_random_uuid(),sb);
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.backup_snapshots WHERE tenant_id IN(a,b))<>2
 OR (SELECT count(*) FROM ops.restore_requests WHERE tenant_id IN(a,b))<>1
 OR jobs_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(j) ORDER BY tenant_id,job_id) FROM ops.tenant_backup_jobs j WHERE tenant_id IN(a,b))
 OR audit_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM ops.audit_events x WHERE tenant_id IN(a,b))
 OR events_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM ops.outbox_events x WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or automatic effect'; END IF;
 FOREACH rel IN ARRAY ARRAY['ops.backup_snapshots'::regclass,'ops.restore_requests'::regclass] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
  OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_backup_request_executor','upc_outbox_capture']) r(role_name)
   WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
 END LOOP;
END $$;
SET SESSION AUTHORIZATION upc_recovery_platform;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.list_tenant_backup_requests('a0930000-0000-0000-0000-000000000001'))<>1 THEN RAISE EXCEPTION 'FAIL old backup request read'; END IF;
 BEGIN PERFORM 1 FROM ops.backup_snapshots; RAISE EXCEPTION 'FAIL direct snapshot read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.restore_requests; RAISE EXCEPTION 'FAIL direct restore read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_recovery_a,upc_recovery_b,upc_recovery_unmapped,upc_recovery_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.backup_snapshots,ops.restore_requests TO upc_recovery_a,upc_recovery_b,upc_recovery_unmapped,upc_recovery_platform;
SET SESSION AUTHORIZATION upc_recovery_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0930000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 IF EXISTS(SELECT 1 FROM ops.backup_snapshots) OR EXISTS(SELECT 1 FROM ops.restore_requests) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.backup_snapshots(tenant_id,job_id) VALUES(iam.current_tenant_id(),gen_random_uuid()); RAISE EXCEPTION 'FAIL RLS snapshot insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.restore_requests(tenant_id,request_key,snapshot_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),'e0930000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL RLS restore insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.restore_requests SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.backup_snapshots; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_recovery_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.backup_snapshots) OR EXISTS(SELECT 1 FROM ops.restore_requests) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_recovery_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.backup_snapshots) OR EXISTS(SELECT 1 FROM ops.restore_requests) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_recovery_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.backup_snapshots) OR EXISTS(SELECT 1 FROM ops.restore_requests) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant backup and restore metadata: scoped job and snapshot FKs, duplicate restore key rejection, rollback, deny-all RLS, old request path preserved and no automatic effects

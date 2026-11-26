\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_backup_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_backup_other LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_backup_staff LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_backup_mixed LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_backup_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_backup_tenant LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_backup_admin,upc_backup_other,upc_backup_staff,upc_backup_mixed,upc_backup_unmapped;
GRANT upc_runtime TO upc_backup_mixed,upc_backup_tenant;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES ('a0710000-0000-0000-0000-000000000001','backup-a','Synthetic A'),('a0710000-0000-0000-0000-000000000002','backup-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0710000-0000-0000-0000-00000000000'||i)::uuid,'test','backup-'||i FROM generate_series(1,5) i;
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin)
 SELECT (ARRAY['upc_backup_admin','upc_backup_other','upc_backup_staff','upc_backup_mixed'])[i]::name,
 ('b0710000-0000-0000-0000-00000000000'||i)::uuid,i<>3 FROM generate_series(1,4) i;
INSERT INTO iam.memberships(tenant_id,user_id) SELECT 'a0710000-0000-0000-0000-000000000001',user_id FROM core.users WHERE identity_issuer='test' AND identity_subject IN ('backup-4','backup-5');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_backup_mixed','a0710000-0000-0000-0000-000000000001','b0710000-0000-0000-0000-000000000004'),('upc_backup_tenant','a0710000-0000-0000-0000-000000000001','b0710000-0000-0000-0000-000000000005');
SET SESSION AUTHORIZATION upc_backup_admin;
DO $$
DECLARE jid uuid; before_row jsonb; cmd text;
BEGIN
 jid:=ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000001');
 SELECT to_jsonb(x) INTO before_row FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001') x WHERE job_id=jid;
 IF before_row IS NULL OR ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000001') IS DISTINCT FROM jid
 OR (SELECT to_jsonb(x) FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001') x WHERE job_id=jid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'))<>1
 OR EXISTS(SELECT 1 FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000002'))
 THEN RAISE EXCEPTION 'FAIL replay or requested scope'; END IF;
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000002','d0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL cross-tenant key conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM ops.request_tenant_backup(NULL,'d0710000-0000-0000-0000-000000000002'); RAISE EXCEPTION 'FAIL null tenant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000000'); RAISE EXCEPTION 'FAIL zero key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.request_tenant_backup('00000000-0000-0000-0000-000000000000','d0710000-0000-0000-0000-000000000002'); RAISE EXCEPTION 'FAIL absent tenant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests(NULL); RAISE EXCEPTION 'FAIL unscoped list'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'SELECT * FROM ops.tenant_backup_jobs','INSERT INTO ops.tenant_backup_jobs(tenant_id,request_key,requested_by) VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid())',
 'UPDATE ops.tenant_backup_jobs SET requested_at=clock_timestamp()','DELETE FROM ops.tenant_backup_jobs','TRUNCATE ops.tenant_backup_jobs',
 'SET ROLE upc_backup_request_executor','INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id) VALUES(gen_random_uuid(),gen_random_uuid(),''insert'',''ops.tenant_backup_jobs'',gen_random_uuid())'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct access: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000002','d0710000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF EXISTS(SELECT 1 FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000002')) THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_backup_other;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL different actor replay'; EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000002','d0710000-0000-0000-0000-000000000002');
 IF (SELECT count(*) FROM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000002'))<>1 THEN RAISE EXCEPTION 'FAIL second tenant'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_backup_staff;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL staff write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL staff read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_backup_mixed;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL mixed write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL mixed read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_backup_unmapped;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unmapped read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_backup_tenant;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL tenant write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL tenant read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM * FROM ops.tenant_backup_jobs; RAISE EXCEPTION 'FAIL tenant direct read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
UPDATE iam.platform_staff_assignments SET revoked_at=clock_timestamp() WHERE login_role='upc_backup_admin';
SET SESSION AUTHORIZATION upc_backup_admin;
DO $$ BEGIN
 BEGIN PERFORM ops.request_tenant_backup('a0710000-0000-0000-0000-000000000001','d0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL revoked retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.list_tenant_backup_requests('a0710000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL revoked read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.tenant_backup_jobs)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='ops.tenant_backup_jobs')<>2
 OR (SELECT count(*) FROM ops.audit_events e JOIN ops.tenant_backup_jobs b ON e.tenant_id=b.tenant_id AND e.entity_id=b.job_id AND e.actor_user_id=b.requested_by WHERE e.entity_type='ops.tenant_backup_jobs' AND e.event_type='insert')<>2
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.tenant_backup_jobs'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_platform_approver','ops.tenant_backup_jobs','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_table_privilege('upc_runtime','ops.tenant_backup_jobs','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_function_privilege('upc_runtime','ops.request_tenant_backup(uuid,uuid)','EXECUTE')
 OR has_function_privilege('upc_runtime','ops.list_tenant_backup_requests(uuid)','EXECUTE')
 OR pg_has_role('upc_platform_approver','upc_backup_request_executor','MEMBER')
 OR has_table_privilege('upc_backup_request_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_backup_request_executor','ops.audit_events','SELECT,UPDATE,DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='ops.request_tenant_backup(uuid,uuid)'::regprocedure AND r.rolname='upc_backup_request_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural and audit contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant tenant backup requests: platform-only, tenant scope, exact retry, conflict, audit, rollback and no backup execution

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_iam_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_iam_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_iam_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_iam_staff LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_iam_unknown LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_iam_a,upc_iam_b,upc_iam_unknown;
-- Deliberately grant function EXECUTE capability to untrusted roles to prove
-- the function independently enforces platform-superadmin assignment.
GRANT upc_platform_approver TO upc_iam_admin,upc_iam_staff,upc_iam_a;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('20000000-0000-0000-0000-000000000001','iam-a','Synthetic A'),
 ('20000000-0000-0000-0000-000000000002','iam-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('30000000-0000-0000-0000-000000000001','test','iam-shared-user'),
 ('30000000-0000-0000-0000-000000000003','test','iam-admin'),
 ('30000000-0000-0000-0000-000000000004','test','iam-staff');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001');
INSERT INTO iam.db_principals VALUES
 ('upc_iam_a','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001'),
 ('upc_iam_b','20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_iam_admin','30000000-0000-0000-0000-000000000003',true),
 ('upc_iam_staff','30000000-0000-0000-0000-000000000004',false);
INSERT INTO iam.permissions VALUES ('crm.read','Read CRM'),('crm.write','Write CRM');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES
 ('20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','reader'),
 ('20000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','writer');
INSERT INTO iam.role_grants VALUES
 ('20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','crm.read'),
 ('20000000-0000-0000-0000-000000000002','40000000-0000-0000-0000-000000000002','crm.write');
INSERT INTO iam.membership_roles VALUES
 ('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001'),
 ('20000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002');
INSERT INTO platform.modules(module_id,module_key,version_label) VALUES
 ('50000000-0000-0000-0000-000000000001','crm','0.1');

DO $$ BEGIN
 IF EXISTS (
 SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
 JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('iam','crm','platform') AND p.prosecdef
 AND (r.rolsuper OR r.rolbypassrls OR r.rolcanlogin)
 ) THEN RAISE EXCEPTION 'FAIL privileged function owner'; END IF;
 BEGIN
   INSERT INTO iam.membership_roles VALUES
    ('20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002');
   RAISE EXCEPTION 'FAIL cross tenant role FK';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;

SET SESSION AUTHORIZATION upc_iam_a;
DO $$ BEGIN
 IF NOT iam.has_permission('crm.read') OR iam.has_permission('crm.write')
  OR platform.module_enabled('crm') THEN RAISE EXCEPTION 'FAIL A permission or default disabled'; END IF;
 BEGIN
  INSERT INTO iam.role_grants VALUES
   ('20000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001','crm.write');
  RAISE EXCEPTION 'FAIL direct privilege escalation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',true,NULL,'Forbidden');
  RAISE EXCEPTION 'FAIL tenant can approve';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_staff;
DO $$ BEGIN
 BEGIN
  PERFORM platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',true,NULL,'Forbidden');
  RAISE EXCEPTION 'FAIL staff can approve';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_admin;
SELECT platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',true,NULL,'Synthetic approval');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_a;
DO $$ BEGIN
 IF NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'FAIL approval not visible'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_b;
DO $$ BEGIN
 IF iam.has_permission('crm.read') OR NOT iam.has_permission('crm.write') OR platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'FAIL tenant B permissions or grant leakage'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_unknown;
DO $$ BEGIN
 IF iam.has_permission('crm.read') OR platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'FAIL unmapped default denial'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_iam_admin;
SELECT platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',false,NULL,'Synthetic revocation');
SELECT platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',true,clock_timestamp()+interval '1 second','Synthetic expiring grant');
RESET SESSION AUTHORIZATION;
SELECT pg_sleep(1.1);
SET SESSION AUTHORIZATION upc_iam_a;
DO $$ BEGIN
 IF platform.module_enabled('crm') THEN RAISE EXCEPTION 'FAIL expired approval falls back'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM platform.tenant_module_grants) <> 3 OR EXISTS(
 SELECT 1 FROM platform.tenant_module_grants WHERE decided_by <> '30000000-0000-0000-0000-000000000003')
 THEN RAISE EXCEPTION 'FAIL approval history attribution'; END IF;
END $$;
UPDATE iam.platform_staff_assignments SET revoked_at=now() WHERE login_role='upc_iam_admin';
SET SESSION AUTHORIZATION upc_iam_admin;
DO $$ BEGIN
 BEGIN
  PERFORM platform.record_module_decision('20000000-0000-0000-0000-000000000001','crm',true,NULL,'Forbidden after revoke');
  RAISE EXCEPTION 'FAIL revoked admin can approve';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS IAM: function owners, tenant-scoped roles, denied escalation, platform approvals, expiration and audit history

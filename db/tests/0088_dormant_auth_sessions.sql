\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_authmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_authmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_authmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_authmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_authmeta_a,upc_authmeta_b,upc_authmeta_unmapped;
GRANT upc_platform_approver TO upc_authmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0880000-0000-0000-0000-000000000001','authmeta-a','Synthetic A'),
 ('a0880000-0000-0000-0000-000000000002','authmeta-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0880000-0000-0000-0000-000000000001','test','authmeta-a'),
 ('b0880000-0000-0000-0000-000000000002','test','authmeta-b'),
 ('b0880000-0000-0000-0000-000000000003','test','authmeta-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000001'),
 ('a0880000-0000-0000-0000-000000000002','b0880000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_authmeta_a','a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000001'),
 ('upc_authmeta_b','a0880000-0000-0000-0000-000000000002','b0880000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_authmeta_platform','b0880000-0000-0000-0000-000000000003',true);
INSERT INTO iam.user_auth_sessions(tenant_id,user_id,session_id) VALUES
 ('a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000001','c0880000-0000-0000-0000-000000000001'),
 ('a0880000-0000-0000-0000-000000000002','b0880000-0000-0000-0000-000000000002','c0880000-0000-0000-0000-000000000001');
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='iam.user_auth_sessions'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='iam.user_auth_sessions'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer']) AS r(role_name)
 WHERE has_table_privilege(r.role_name,'iam.user_auth_sessions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL dormant ACL or RLS'; END IF;
 BEGIN
  INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES('a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL cross-tenant membership accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  INSERT INTO iam.user_auth_sessions(tenant_id,user_id,session_id) VALUES('a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000001','c0880000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL duplicate session accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES('a0880000-0000-0000-0000-000000000001','b0880000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM iam.user_auth_sessions)<>2 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_authmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0880000-0000-0000-0000-000000000001'::uuid
 OR iam.current_user_id() IS DISTINCT FROM 'b0880000-0000-0000-0000-000000000001'::uuid
 THEN RAISE EXCEPTION 'FAIL existing trusted identity'; END IF;
 BEGIN PERFORM 1 FROM iam.user_auth_sessions; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES(iam.current_tenant_id(),iam.current_user_id()); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_authmeta_b;
DO $$ BEGIN
 BEGIN PERFORM 1 FROM iam.user_auth_sessions; RAISE EXCEPTION 'FAIL other tenant read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_authmeta_unmapped;
DO $$ BEGIN
 IF iam.current_tenant_id() IS NOT NULL THEN RAISE EXCEPTION 'FAIL unmapped principal'; END IF;
 BEGIN PERFORM 1 FROM iam.user_auth_sessions; RAISE EXCEPTION 'FAIL unmapped read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Deliberate synthetic grant inside rolled-back test verifies RLS independently of ACL.
GRANT USAGE ON SCHEMA iam TO upc_authmeta_a,upc_authmeta_b,upc_authmeta_unmapped,upc_authmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON iam.user_auth_sessions TO upc_authmeta_a,upc_authmeta_b,upc_authmeta_unmapped,upc_authmeta_platform;
SET SESSION AUTHORIZATION upc_authmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM iam.user_auth_sessions) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO iam.user_auth_sessions(tenant_id,user_id) VALUES(iam.current_tenant_id(),iam.current_user_id()); RAISE EXCEPTION 'FAIL RLS write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE iam.user_auth_sessions SET recorded_at=clock_timestamp();
 IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM iam.user_auth_sessions;
 IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_authmeta_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM iam.user_auth_sessions) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_authmeta_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM iam.user_auth_sessions) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_authmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM iam.user_auth_sessions) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.memberships WHERE tenant_id='a0880000-0000-0000-0000-000000000001';
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM iam.user_auth_sessions WHERE tenant_id='a0880000-0000-0000-0000-000000000001')
 OR (SELECT count(*) FROM iam.user_auth_sessions WHERE tenant_id='a0880000-0000-0000-0000-000000000002')<>1
 OR EXISTS(SELECT 1 FROM iam.db_principals WHERE login_role='upc_authmeta_a')
 THEN RAISE EXCEPTION 'FAIL membership deletion regression'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_authmeta_a;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR iam.current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'FAIL revoked membership'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant auth session metadata: composite membership, duplicate denial, rollback, deny-all RLS, no runtime access and membership removal regression

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_secmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_secmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_secmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_secmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_secmeta_a,upc_secmeta_b,upc_secmeta_unmapped;
GRANT upc_platform_approver TO upc_secmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0990000-0000-0000-0000-000000000001','security-test-a','Synthetic A'),
 ('a0990000-0000-0000-0000-000000000002','security-test-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0990000-0000-0000-0000-000000000001','test','secmeta-a'),
 ('b0990000-0000-0000-0000-000000000002','test','secmeta-b'),
 ('b0990000-0000-0000-0000-000000000003','test','secmeta-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0990000-0000-0000-0000-000000000001','b0990000-0000-0000-0000-000000000001'),
 ('a0990000-0000-0000-0000-000000000002','b0990000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_secmeta_a','a0990000-0000-0000-0000-000000000001','b0990000-0000-0000-0000-000000000001'),
 ('upc_secmeta_b','a0990000-0000-0000-0000-000000000002','b0990000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_secmeta_platform','b0990000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a0990000-0000-0000-0000-000000000001'; b uuid:='a0990000-0000-0000-0000-000000000002';
BEGIN
 INSERT INTO iam.security_policies(tenant_id,source_network) VALUES(a,'192.0.2.0/24'),(b,'192.0.2.0/24'),(a,'2001:db8::/32');
 -- ZZ is a synthetic two-letter token, not a validated country.
 INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(a,'ZZ'),(b,'ZZ');
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_network) VALUES(a,'192.0.2/24'); RAISE EXCEPTION 'FAIL duplicate network'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(a,'ZZ'); RAISE EXCEPTION 'FAIL duplicate country'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id) VALUES(a); RAISE EXCEPTION 'FAIL absent selector'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_network,source_country) VALUES(a,'198.51.100.0/24','ZZ'); RAISE EXCEPTION 'FAIL multiple selectors'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(a,'zz'); RAISE EXCEPTION 'FAIL invalid syntax'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(a,'ZZZ'); RAISE EXCEPTION 'FAIL invalid length'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_network) VALUES(a,'192.0.2.1/24'); RAISE EXCEPTION 'FAIL noncanonical CIDR'; EXCEPTION WHEN invalid_text_representation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(gen_random_uuid(),'ZZ'); RAISE EXCEPTION 'FAIL missing tenant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_network) VALUES(a,'198.51.100.0/24'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM iam.security_policies WHERE tenant_id IN(a,b))<>5
 OR EXISTS(SELECT 1 FROM core.tenant_settings WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM iam.user_auth_sessions WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.audit_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='iam.security_policies'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='iam.security_policies'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS r(role_name)
 WHERE has_table_privilege(r.role_name,'iam.security_policies','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL rollback, domain effects or dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_secmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0990000-0000-0000-0000-000000000001'::uuid OR iam.current_user_id() IS DISTINCT FROM 'b0990000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM iam.security_policies; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(iam.current_tenant_id(),'XY'); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA iam TO upc_secmeta_a,upc_secmeta_b,upc_secmeta_unmapped,upc_secmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON iam.security_policies TO upc_secmeta_a,upc_secmeta_b,upc_secmeta_unmapped,upc_secmeta_platform;
SET SESSION AUTHORIZATION upc_secmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM iam.security_policies) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO iam.security_policies(tenant_id,source_country) VALUES(iam.current_tenant_id(),'XY'); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE iam.security_policies SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM iam.security_policies; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_secmeta_b;
DO $$ BEGIN IF iam.current_tenant_id() IS DISTINCT FROM 'a0990000-0000-0000-0000-000000000002'::uuid OR EXISTS(SELECT 1 FROM iam.security_policies) THEN RAISE EXCEPTION 'FAIL other tenant IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_secmeta_unmapped;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR EXISTS(SELECT 1 FROM iam.security_policies) THEN RAISE EXCEPTION 'FAIL unmapped IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_secmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM iam.security_policies) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant security selectors: typed CIDR and country syntax, exact duplicate rejection, tenant isolation, rollback, deny-all RLS and unchanged IAM

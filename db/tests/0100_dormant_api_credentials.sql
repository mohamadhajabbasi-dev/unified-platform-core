\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_credmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_credmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_credmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_credmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_credmeta_a,upc_credmeta_b,upc_credmeta_unmapped;
GRANT upc_platform_approver TO upc_credmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1000000-0000-0000-0000-000000000001','credential-test-a','Synthetic A'),
 ('a1000000-0000-0000-0000-000000000002','credential-test-b','Synthetic B');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','one','synthetic'),
 ('a1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000002','two','synthetic'),
 ('a1000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000003','one','synthetic');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1000000-0000-0000-0000-000000000001','test','credmeta-a'),
 ('b1000000-0000-0000-0000-000000000002','test','credmeta-b'),
 ('b1000000-0000-0000-0000-000000000003','test','credmeta-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001'),
 ('a1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_credmeta_a','a1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001'),
 ('upc_credmeta_b','a1000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_credmeta_platform','b1000000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a1000000-0000-0000-0000-000000000001'; b uuid:='a1000000-0000-0000-0000-000000000002';
 ca uuid:='c1000000-0000-0000-0000-000000000001'; ca2 uuid:='c1000000-0000-0000-0000-000000000002'; cb uuid:='c1000000-0000-0000-0000-000000000003';
 cr uuid:='d1000000-0000-0000-0000-000000000001'; vr uuid:='e1000000-0000-0000-0000-000000000001'; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(c) ORDER BY tenant_id,connection_id) INTO prior FROM ops.integration_connections c WHERE tenant_id IN(a,b);
 INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,credential_id,vault_reference_id) VALUES
 (a,ca,cr,vr),(b,cb,cr,'e1000000-0000-0000-0000-000000000002'),
 (a,ca,gen_random_uuid(),'e1000000-0000-0000-0000-000000000003');
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,credential_id,vault_reference_id) VALUES(a,ca,cr,gen_random_uuid()); RAISE EXCEPTION 'FAIL duplicate credential identity'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(a,ca2,vr); RAISE EXCEPTION 'FAIL duplicate reference across connections'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(b,cb,vr); RAISE EXCEPTION 'FAIL reference reuse across tenants'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(a,cb,gen_random_uuid()); RAISE EXCEPTION 'FAIL cross-tenant connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(a,gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'FAIL missing connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(a,ca,NULL); RAISE EXCEPTION 'FAIL null reference'; EXCEPTION WHEN not_null_violation THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(a,ca2,gen_random_uuid()); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM iam.api_credentials_metadata WHERE tenant_id IN(a,b))<>3
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY tenant_id,connection_id) FROM ops.integration_connections c WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM iam.user_auth_sessions WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM iam.security_policies WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.audit_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='iam.api_credentials_metadata'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='iam.api_credentials_metadata'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r)
 WHERE has_table_privilege(r,'iam.api_credentials_metadata','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL rollback, domain effect or dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_credmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a1000000-0000-0000-0000-000000000001'::uuid OR iam.current_user_id() IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM iam.api_credentials_metadata; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(iam.current_tenant_id(),'c1000000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA iam TO upc_credmeta_a,upc_credmeta_b,upc_credmeta_unmapped,upc_credmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON iam.api_credentials_metadata TO upc_credmeta_a,upc_credmeta_b,upc_credmeta_unmapped,upc_credmeta_platform;
SET SESSION AUTHORIZATION upc_credmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM iam.api_credentials_metadata) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO iam.api_credentials_metadata(tenant_id,connection_id,vault_reference_id) VALUES(iam.current_tenant_id(),'c1000000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE iam.api_credentials_metadata SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM iam.api_credentials_metadata; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_credmeta_b;
DO $$ BEGIN IF iam.current_tenant_id() IS DISTINCT FROM 'a1000000-0000-0000-0000-000000000002'::uuid OR EXISTS(SELECT 1 FROM iam.api_credentials_metadata) THEN RAISE EXCEPTION 'FAIL other tenant IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_credmeta_unmapped;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR EXISTS(SELECT 1 FROM iam.api_credentials_metadata) THEN RAISE EXCEPTION 'FAIL unmapped IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_credmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM iam.api_credentials_metadata) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant API credential metadata: scoped connection FK, unique opaque reference, rollback, deny-all RLS and unchanged IAM

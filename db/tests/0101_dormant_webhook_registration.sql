\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_hookmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_hookmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_hookmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_hookmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_hookmeta_a,upc_hookmeta_b,upc_hookmeta_unmapped;
GRANT upc_platform_approver TO upc_hookmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1010000-0000-0000-0000-000000000001','webhook-test-a','Synthetic A'),
 ('a1010000-0000-0000-0000-000000000002','webhook-test-b','Synthetic B');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a1010000-0000-0000-0000-000000000001','c1010000-0000-0000-0000-000000000001','one','synthetic'),
 ('a1010000-0000-0000-0000-000000000001','c1010000-0000-0000-0000-000000000002','two','synthetic'),
 ('a1010000-0000-0000-0000-000000000002','c1010000-0000-0000-0000-000000000003','one','synthetic');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1010000-0000-0000-0000-000000000001','test','hookmeta-a'),
 ('b1010000-0000-0000-0000-000000000002','test','hookmeta-b'),
 ('b1010000-0000-0000-0000-000000000003','test','hookmeta-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a1010000-0000-0000-0000-000000000001','b1010000-0000-0000-0000-000000000001'),
 ('a1010000-0000-0000-0000-000000000002','b1010000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_hookmeta_a','a1010000-0000-0000-0000-000000000001','b1010000-0000-0000-0000-000000000001'),
 ('upc_hookmeta_b','a1010000-0000-0000-0000-000000000002','b1010000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_hookmeta_platform','b1010000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a1010000-0000-0000-0000-000000000001'; b uuid:='a1010000-0000-0000-0000-000000000002';
 ca uuid:='c1010000-0000-0000-0000-000000000001'; ca2 uuid:='c1010000-0000-0000-0000-000000000002'; cb uuid:='c1010000-0000-0000-0000-000000000003';
 rid uuid:='d1010000-0000-0000-0000-000000000001'; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(c) ORDER BY tenant_id,connection_id) INTO prior FROM ops.integration_connections c WHERE tenant_id IN(a,b);
 INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES
 (a,ca,rid),(a,ca2,rid),(b,cb,rid),(a,ca,'d1010000-0000-0000-0000-000000000002');
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(a,ca,rid); RAISE EXCEPTION 'FAIL duplicate registration'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(a,cb,gen_random_uuid()); RAISE EXCEPTION 'FAIL cross-tenant connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(a,gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'FAIL missing connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(a,ca,NULL); RAISE EXCEPTION 'FAIL null registration'; EXCEPTION WHEN not_null_violation THEN NULL; END;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(a,ca,gen_random_uuid()); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.webhook_registrations WHERE tenant_id IN(a,b))<>4
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY tenant_id,connection_id) FROM ops.integration_connections c WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM iam.api_credentials_metadata WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM iam.user_auth_sessions WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumers WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.audit_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.webhook_registrations'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='ops.webhook_registrations'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r)
 WHERE has_table_privilege(r,'ops.webhook_registrations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL rollback, domain effect or dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_hookmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a1010000-0000-0000-0000-000000000001'::uuid OR iam.current_user_id() IS DISTINCT FROM 'b1010000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.webhook_registrations; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(iam.current_tenant_id(),'c1010000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_hookmeta_a,upc_hookmeta_b,upc_hookmeta_unmapped,upc_hookmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.webhook_registrations TO upc_hookmeta_a,upc_hookmeta_b,upc_hookmeta_unmapped,upc_hookmeta_platform;
SET SESSION AUTHORIZATION upc_hookmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.webhook_registrations) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.webhook_registrations(tenant_id,connection_id,registration_id) VALUES(iam.current_tenant_id(),'c1010000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.webhook_registrations SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.webhook_registrations; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hookmeta_b;
DO $$ BEGIN IF iam.current_tenant_id() IS DISTINCT FROM 'a1010000-0000-0000-0000-000000000002'::uuid OR EXISTS(SELECT 1 FROM ops.webhook_registrations) THEN RAISE EXCEPTION 'FAIL other tenant IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hookmeta_unmapped;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR EXISTS(SELECT 1 FROM ops.webhook_registrations) THEN RAISE EXCEPTION 'FAIL unmapped IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hookmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.webhook_registrations) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant inbound webhook registration: scoped connection FK and identity, rollback, deny-all RLS and no domain effect

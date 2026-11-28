\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_flowmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_flowmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_flowmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_flowmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_flowmeta_a,upc_flowmeta_b,upc_flowmeta_unmapped;
GRANT upc_platform_approver TO upc_flowmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1030000-0000-0000-0000-000000000001','workflow-test-a','Synthetic A'),
 ('a1030000-0000-0000-0000-000000000002','workflow-test-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1030000-0000-0000-0000-000000000001','test','flowmeta-a'),
 ('b1030000-0000-0000-0000-000000000002','test','flowmeta-b'),
 ('b1030000-0000-0000-0000-000000000003','test','flowmeta-platform'),
 ('b1030000-0000-0000-0000-000000000004','test','flowmeta-extra');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a1030000-0000-0000-0000-000000000001','b1030000-0000-0000-0000-000000000001'),
 ('a1030000-0000-0000-0000-000000000002','b1030000-0000-0000-0000-000000000002'),
 ('a1030000-0000-0000-0000-000000000001','b1030000-0000-0000-0000-000000000004'),
 ('a1030000-0000-0000-0000-000000000002','b1030000-0000-0000-0000-000000000001');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_flowmeta_a','a1030000-0000-0000-0000-000000000001','b1030000-0000-0000-0000-000000000001'),
 ('upc_flowmeta_b','a1030000-0000-0000-0000-000000000002','b1030000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_flowmeta_platform','b1030000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a1030000-0000-0000-0000-000000000001'; b uuid:='a1030000-0000-0000-0000-000000000002';
 wid uuid:='d1030000-0000-0000-0000-000000000001'; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id) INTO prior FROM core.tenants t WHERE tenant_id IN(a,b);
 INSERT INTO ops.workflow_definitions(tenant_id,workflow_id,workflow_key) VALUES(a,wid,'synthetic-one'),(b,wid,'synthetic-one');
 INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,'synthetic-two');
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,'synthetic-one'); RAISE EXCEPTION 'FAIL duplicate workflow key'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_id,workflow_key) VALUES(a,wid,'another-key'); RAISE EXCEPTION 'FAIL duplicate workflow identity'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(gen_random_uuid(),'missing-tenant'); RAISE EXCEPTION 'FAIL missing tenant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,NULL); RAISE EXCEPTION 'FAIL null workflow key'; EXCEPTION WHEN not_null_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,'Invalid key'); RAISE EXCEPTION 'FAIL invalid workflow key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,repeat('a',81)); RAISE EXCEPTION 'FAIL long workflow key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,''); RAISE EXCEPTION 'FAIL empty workflow key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(a,'rolled-back'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.workflow_definitions WHERE tenant_id IN(a,b))<>3
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id) FROM core.tenants t WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM crm.service_queues WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM procurement.procurement_requests WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM platform.tenant_module_grants WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.notifications WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.audit_events WHERE tenant_id IN(a,b))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.workflow_definitions'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='ops.workflow_definitions'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r) WHERE has_table_privilege(r,'ops.workflow_definitions','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL rollback, domain effect or dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_flowmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a1030000-0000-0000-0000-000000000001'::uuid OR iam.current_user_id() IS DISTINCT FROM 'b1030000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.workflow_definitions; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(iam.current_tenant_id(),'denied'); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_flowmeta_a,upc_flowmeta_b,upc_flowmeta_unmapped,upc_flowmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.workflow_definitions TO upc_flowmeta_a,upc_flowmeta_b,upc_flowmeta_unmapped,upc_flowmeta_platform;
SET SESSION AUTHORIZATION upc_flowmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.workflow_definitions) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.workflow_definitions(tenant_id,workflow_key) VALUES(iam.current_tenant_id(),'denied'); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.workflow_definitions SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.workflow_definitions; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_flowmeta_b;
DO $$ BEGIN IF iam.current_tenant_id() IS DISTINCT FROM 'a1030000-0000-0000-0000-000000000002'::uuid OR EXISTS(SELECT 1 FROM ops.workflow_definitions) THEN RAISE EXCEPTION 'FAIL other tenant IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_flowmeta_unmapped;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR EXISTS(SELECT 1 FROM ops.workflow_definitions) THEN RAISE EXCEPTION 'FAIL unmapped IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_flowmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.workflow_definitions) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant workflow definition: scoped unique key and identity, tenant FK, validation, rollback, deny-all RLS and no domain effects

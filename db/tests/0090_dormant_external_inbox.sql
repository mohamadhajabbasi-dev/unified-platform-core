\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_inbox_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inbox_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inbox_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inbox_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_inbox_a,upc_inbox_b,upc_inbox_unmapped;
GRANT upc_platform_approver TO upc_inbox_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0900000-0000-0000-0000-000000000001','inbox-a','Synthetic A'),
 ('a0900000-0000-0000-0000-000000000002','inbox-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0900000-0000-0000-0000-000000000001','test','inbox-a'),
 ('b0900000-0000-0000-0000-000000000002','test','inbox-b'),
 ('b0900000-0000-0000-0000-000000000003','test','inbox-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0900000-0000-0000-0000-000000000001','b0900000-0000-0000-0000-000000000001'),
 ('a0900000-0000-0000-0000-000000000002','b0900000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_inbox_a','a0900000-0000-0000-0000-000000000001','b0900000-0000-0000-0000-000000000001'),
 ('upc_inbox_b','a0900000-0000-0000-0000-000000000002','b0900000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_inbox_platform','b0900000-0000-0000-0000-000000000003',true);
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a0900000-0000-0000-0000-000000000001','c0900000-0000-0000-0000-000000000001','external-a','synthetic-adapter'),
 ('a0900000-0000-0000-0000-000000000001','c0900000-0000-0000-0000-000000000002','external-b','synthetic-adapter'),
 ('a0900000-0000-0000-0000-000000000002','c0900000-0000-0000-0000-000000000003','external-a','synthetic-adapter');
DO $$
DECLARE a uuid:='a0900000-0000-0000-0000-000000000001'; b uuid:='a0900000-0000-0000-0000-000000000002';
 ca uuid:='c0900000-0000-0000-0000-000000000001'; ca2 uuid:='c0900000-0000-0000-0000-000000000002'; cb uuid:='c0900000-0000-0000-0000-000000000003';
 eid uuid:='d0900000-0000-0000-0000-000000000001'; rel regclass;
BEGIN
 INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES(a,ca,eid),(a,ca2,eid),(b,cb,eid);
 BEGIN INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES(a,ca,eid);
  RAISE EXCEPTION 'FAIL duplicate inbound identity'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.integration_connections(tenant_id,connection_key,adapter_key) VALUES(a,'external-a','different-adapter');
  RAISE EXCEPTION 'FAIL duplicate connection'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.integration_connections(tenant_id,connection_key,adapter_key) VALUES(a,'invalid-key','https://invalid.example');
  RAISE EXCEPTION 'FAIL invalid adapter key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES(a,cb,eid);
  RAISE EXCEPTION 'FAIL cross-tenant connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN DELETE FROM ops.integration_connections WHERE tenant_id=a AND connection_id=ca;
  RAISE EXCEPTION 'FAIL referenced connection deletion'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES(a,ca,gen_random_uuid());
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.integration_connections WHERE tenant_id IN(a,b))<>3
 OR (SELECT count(*) FROM ops.inbound_inbox WHERE tenant_id IN(a,b))<>3
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumers WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM catalog.products WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or automatic domain effect'; END IF;
 FOREACH rel IN ARRAY ARRAY['ops.integration_connections'::regclass,'ops.inbound_inbox'::regclass] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
  OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) r(role_name)
    WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
 END LOOP;
END $$;
SET SESSION AUTHORIZATION upc_inbox_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0900000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.integration_connections; RAISE EXCEPTION 'FAIL direct connection read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.inbound_inbox; RAISE EXCEPTION 'FAIL direct inbox read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_inbox_a,upc_inbox_b,upc_inbox_unmapped,upc_inbox_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.integration_connections,ops.inbound_inbox TO upc_inbox_a,upc_inbox_b,upc_inbox_unmapped,upc_inbox_platform;
SET SESSION AUTHORIZATION upc_inbox_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.integration_connections) OR EXISTS(SELECT 1 FROM ops.inbound_inbox) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.integration_connections(tenant_id,connection_key,adapter_key) VALUES(iam.current_tenant_id(),'forbidden','synthetic'); RAISE EXCEPTION 'FAIL RLS connection insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id) VALUES(iam.current_tenant_id(),'c0900000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL RLS inbox insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.inbound_inbox SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.integration_connections; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inbox_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.integration_connections) OR EXISTS(SELECT 1 FROM ops.inbound_inbox) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inbox_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.integration_connections) OR EXISTS(SELECT 1 FROM ops.inbound_inbox) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inbox_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.integration_connections) OR EXISTS(SELECT 1 FROM ops.inbound_inbox) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant external inbox: connection identity, scoped deduplication, tenant FKs, rollback, deny-all RLS and no automatic domain effect

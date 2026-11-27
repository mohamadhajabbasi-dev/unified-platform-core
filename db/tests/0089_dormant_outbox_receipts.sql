\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_receipt_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_receipt_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_receipt_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_receipt_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_receipt_a,upc_receipt_b,upc_receipt_unmapped;
GRANT upc_platform_approver TO upc_receipt_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0890000-0000-0000-0000-000000000001','receipt-a','Synthetic A'),
 ('a0890000-0000-0000-0000-000000000002','receipt-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0890000-0000-0000-0000-000000000001','test','receipt-a'),
 ('b0890000-0000-0000-0000-000000000002','test','receipt-b'),
 ('b0890000-0000-0000-0000-000000000003','test','receipt-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0890000-0000-0000-0000-000000000001','b0890000-0000-0000-0000-000000000001'),
 ('a0890000-0000-0000-0000-000000000002','b0890000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_receipt_a','a0890000-0000-0000-0000-000000000001','b0890000-0000-0000-0000-000000000001'),
 ('upc_receipt_b','a0890000-0000-0000-0000-000000000002','b0890000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_receipt_platform','b0890000-0000-0000-0000-000000000003',true);
-- Actual canonical brand capture through unchanged 0087 trigger.
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a0890000-0000-0000-0000-000000000001','d0890000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0890000-0000-0000-0000-000000000002','d0890000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a0890000-0000-0000-0000-000000000001','c0890000-0000-0000-0000-000000000001','cache-test'),
 ('a0890000-0000-0000-0000-000000000001','c0890000-0000-0000-0000-000000000002','observer-test'),
 ('a0890000-0000-0000-0000-000000000002','c0890000-0000-0000-0000-000000000003','cache-test');
DO $$
DECLARE a uuid:='a0890000-0000-0000-0000-000000000001'; b uuid:='a0890000-0000-0000-0000-000000000002';
 ca uuid:='c0890000-0000-0000-0000-000000000001'; ca2 uuid:='c0890000-0000-0000-0000-000000000002'; cb uuid:='c0890000-0000-0000-0000-000000000003';
 ea uuid; eb uuid; rel regclass; prior jsonb;
BEGIN
 SELECT event_id INTO STRICT ea FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.brand.changed';
 SELECT event_id INTO STRICT eb FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.brand.changed';
 SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events WHERE tenant_id IN(a,b);
 INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,ca,ea),(a,ca2,ea),(b,cb,eb);
 BEGIN INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,ca,ea);
  RAISE EXCEPTION 'FAIL duplicate receipt'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumers(tenant_id,consumer_key) VALUES(a,'cache-test');
  RAISE EXCEPTION 'FAIL duplicate consumer key'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumers(tenant_id,consumer_key) VALUES(a,'https://invalid.example');
  RAISE EXCEPTION 'FAIL invalid consumer key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,ca,eb);
  RAISE EXCEPTION 'FAIL cross-tenant event'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,cb,ea);
  RAISE EXCEPTION 'FAIL cross-tenant consumer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN DELETE FROM ops.outbox_events WHERE tenant_id=a AND event_id=ea;
  RAISE EXCEPTION 'FAIL referenced event deletion'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumers(tenant_id,consumer_key) VALUES(a,'rollback-test');
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.outbox_consumers WHERE tenant_id IN(a,b))<>3
 OR (SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))<>3
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) FROM ops.outbox_events WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or existing event mutation'; END IF;
 FOREACH rel IN ARRAY ARRAY['ops.outbox_consumers'::regclass,'ops.outbox_consumer_receipts'::regclass] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
  OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) r(role_name)
    WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
 END LOOP;
END $$;
SET SESSION AUTHORIZATION upc_receipt_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0890000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.outbox_consumers; RAISE EXCEPTION 'FAIL direct consumer read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.outbox_consumer_receipts; RAISE EXCEPTION 'FAIL direct receipt read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_receipt_a,upc_receipt_b,upc_receipt_unmapped,upc_receipt_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.outbox_consumers,ops.outbox_consumer_receipts TO upc_receipt_a,upc_receipt_b,upc_receipt_unmapped,upc_receipt_platform;
SET SESSION AUTHORIZATION upc_receipt_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.outbox_consumers) OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.outbox_consumers(tenant_id,consumer_key) VALUES(iam.current_tenant_id(),'forbidden'); RAISE EXCEPTION 'FAIL RLS consumer insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(iam.current_tenant_id(),'c0890000-0000-0000-0000-000000000001',gen_random_uuid()); RAISE EXCEPTION 'FAIL RLS receipt insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.outbox_consumer_receipts SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.outbox_consumers; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_receipt_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.outbox_consumers) OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_receipt_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.outbox_consumers) OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_receipt_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.outbox_consumers) OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
UPDATE catalog.brands SET name='Synthetic A updated' WHERE tenant_id='a0890000-0000-0000-0000-000000000001';
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0890000-0000-0000-0000-000000000001')<>2
 OR (SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id='a0890000-0000-0000-0000-000000000001')<>2
 THEN RAISE EXCEPTION 'FAIL existing capture changed or receipt automatically created'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant outbox consumer receipts: existing capture, independent consumers, tenant FKs, duplicate denial, rollback, deny-all RLS and no automatic delivery

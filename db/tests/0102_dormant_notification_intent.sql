\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_notifmeta_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_notifmeta_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_notifmeta_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_notifmeta_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_notifmeta_a,upc_notifmeta_b,upc_notifmeta_unmapped;
GRANT upc_platform_approver TO upc_notifmeta_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1020000-0000-0000-0000-000000000001','notification-test-a','Synthetic A'),
 ('a1020000-0000-0000-0000-000000000002','notification-test-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1020000-0000-0000-0000-000000000001','test','notifmeta-a'),
 ('b1020000-0000-0000-0000-000000000002','test','notifmeta-b'),
 ('b1020000-0000-0000-0000-000000000003','test','notifmeta-platform'),
 ('b1020000-0000-0000-0000-000000000004','test','notifmeta-extra');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a1020000-0000-0000-0000-000000000001','b1020000-0000-0000-0000-000000000001'),
 ('a1020000-0000-0000-0000-000000000002','b1020000-0000-0000-0000-000000000002'),
 ('a1020000-0000-0000-0000-000000000001','b1020000-0000-0000-0000-000000000004'),
 ('a1020000-0000-0000-0000-000000000002','b1020000-0000-0000-0000-000000000001');
-- Synthetic event fixtures only; no capture or delivery behavior implied.
INSERT INTO ops.outbox_events(tenant_id,event_id,event_kind) VALUES
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000001','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000001','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000002','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000011','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000011','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000001','c1020000-0000-0000-0000-000000000012','catalog.price_entry.changed'),
 ('a1020000-0000-0000-0000-000000000002','c1020000-0000-0000-0000-000000000012','catalog.price_entry.changed');
INSERT INTO iam.db_principals(login_role,tenant_id,user_id) VALUES
 ('upc_notifmeta_a','a1020000-0000-0000-0000-000000000001','b1020000-0000-0000-0000-000000000001'),
 ('upc_notifmeta_b','a1020000-0000-0000-0000-000000000002','b1020000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_notifmeta_platform','b1020000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a1020000-0000-0000-0000-000000000001'; b uuid:='a1020000-0000-0000-0000-000000000002';
 u uuid:='b1020000-0000-0000-0000-000000000001'; ub uuid:='b1020000-0000-0000-0000-000000000002'; ux uuid:='b1020000-0000-0000-0000-000000000004';
 e uuid:='c1020000-0000-0000-0000-000000000001'; eb uuid:='c1020000-0000-0000-0000-000000000002'; prior jsonb; members jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events t WHERE tenant_id IN(a,b);
 SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id,user_id) INTO members FROM iam.memberships t WHERE tenant_id IN(a,b);
 INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,e,u),(a,e,ux),(b,e,u);
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,e,u); RAISE EXCEPTION 'FAIL duplicate intent'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,eb,u); RAISE EXCEPTION 'FAIL cross-tenant event'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,e,ub); RAISE EXCEPTION 'FAIL cross-tenant membership'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,gen_random_uuid(),u); RAISE EXCEPTION 'FAIL missing event'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,e,gen_random_uuid()); RAISE EXCEPTION 'FAIL missing member'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(a,e,NULL); RAISE EXCEPTION 'FAIL null recipient'; EXCEPTION WHEN not_null_violation THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(b,e,ub); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  DELETE FROM iam.memberships WHERE tenant_id=a AND user_id=ux;
  IF EXISTS(SELECT 1 FROM ops.notifications WHERE tenant_id=a AND user_id=ux) OR NOT EXISTS(SELECT 1 FROM ops.notifications WHERE tenant_id=b AND user_id=u) THEN RAISE EXCEPTION 'FAIL membership deletion scope'; END IF;
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.notifications WHERE tenant_id IN(a,b))<>3
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id,event_id) FROM ops.outbox_events t WHERE tenant_id IN(a,b))
 OR members IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(t) ORDER BY tenant_id,user_id) FROM iam.memberships t WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM crm.conversation_messages WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumers WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.audit_events WHERE tenant_id IN(a,b))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.notifications'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='ops.notifications'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r) WHERE has_table_privilege(r,'ops.notifications','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL rollback, domain effect or dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_notifmeta_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a1020000-0000-0000-0000-000000000001'::uuid OR iam.current_user_id() IS DISTINCT FROM 'b1020000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.notifications; RAISE EXCEPTION 'FAIL runtime read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(iam.current_tenant_id(),'c1020000-0000-0000-0000-000000000001',iam.current_user_id()); RAISE EXCEPTION 'FAIL runtime write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_notifmeta_a,upc_notifmeta_b,upc_notifmeta_unmapped,upc_notifmeta_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.notifications TO upc_notifmeta_a,upc_notifmeta_b,upc_notifmeta_unmapped,upc_notifmeta_platform;
SET SESSION AUTHORIZATION upc_notifmeta_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.notifications) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.notifications(tenant_id,event_id,user_id) VALUES(iam.current_tenant_id(),'c1020000-0000-0000-0000-000000000001',iam.current_user_id()); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.notifications SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.notifications; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_notifmeta_b;
DO $$ BEGIN IF iam.current_tenant_id() IS DISTINCT FROM 'a1020000-0000-0000-0000-000000000002'::uuid OR EXISTS(SELECT 1 FROM ops.notifications) THEN RAISE EXCEPTION 'FAIL other tenant IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_notifmeta_unmapped;
DO $$ BEGIN IF iam.current_tenant_id() IS NOT NULL OR EXISTS(SELECT 1 FROM ops.notifications) THEN RAISE EXCEPTION 'FAIL unmapped IAM/RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_notifmeta_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.notifications) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant internal notification intent: scoped event and membership FKs, unique intent, membership cascade rollback, deny-all RLS and unchanged source facts

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_feedback_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_feedback_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_feedback_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_feedback_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_feedback_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_feedback_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_feedback_a,upc_feedback_b,upc_feedback_reader,upc_feedback_nocrm,upc_feedback_unmapped,upc_feedback_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0800000-0000-0000-0000-000000000001','feedback-a','Synthetic A'),('a0800000-0000-0000-0000-000000000002','feedback-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0800000-0000-0000-0000-00000000000'||i)::uuid,'test','feedback-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0800000-0000-0000-0000-000000000002'::uuid ELSE 'a0800000-0000-0000-0000-000000000001'::uuid END,
 ('b0800000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_feedback_a','upc_feedback_b','upc_feedback_reader','upc_feedback_nocrm','upc_feedback_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0800000-0000-0000-0000-000000000002'::uuid ELSE 'a0800000-0000-0000-0000-000000000001'::uuid END,
 ('b0800000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0800000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'feedback-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0800000-0000-0000-0000-000000000001','a0800000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='feedback-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0800000-0000-0000-0000-000000000001','a0800000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0800000-0000-0000-0000-000000000001','a0800000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('feedback-1','feedback-2') AND p.permission_key IN ('crm.engagement.read','crm.engagement.write','crm.feedback.read','crm.feedback.write','ops.audit.read'))
 OR (r.role_key='feedback-3' AND p.permission_key IN ('crm.engagement.read','crm.feedback.read'))
 OR (r.role_key='feedback-4' AND p.permission_key IN ('crm.engagement.read','crm.engagement.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0800000-0000-0000-0000-000000000001','d0800000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0800000-0000-0000-0000-000000000001','d0800000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0800000-0000-0000-0000-000000000002','d0800000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0800000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('feedback-a','feedback-b') AND m.module_key='crm';

INSERT INTO crm.support_tickets(tenant_id,ticket_id,ticket_key,customer_id,subject) VALUES
 ('a0800000-0000-0000-0000-000000000001','e0800000-0000-0000-0000-000000000001','A1','d0800000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0800000-0000-0000-0000-000000000002','e0800000-0000-0000-0000-000000000002','B1','d0800000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO crm.support_tickets(tenant_id,ticket_id,ticket_key,subject) VALUES
 ('a0800000-0000-0000-0000-000000000001','e0800000-0000-0000-0000-000000000003','A2','Synthetic rollback');
SET SESSION AUTHORIZATION upc_feedback_a;
DO $$
DECLARE fid uuid; cmd text;
BEGIN
 fid:=crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4);
 IF fid IS NULL OR crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4) IS DISTINCT FROM fid OR (SELECT count(*) FROM crm.support_feedback)<>1
 OR NOT EXISTS(SELECT 1 FROM crm.support_feedback WHERE feedback_id=fid AND score=4 AND recorded_by=iam.current_user_id())
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.support_feedback' AND entity_id=fid AND actor_user_id=iam.current_user_id())<>1 THEN RAISE EXCEPTION 'FAIL exact retry or audit'; END IF;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',5); RAISE EXCEPTION 'FAIL changed score'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000002',4); RAISE EXCEPTION 'FAIL foreign ticket'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',0); RAISE EXCEPTION 'FAIL low score'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',6); RAISE EXCEPTION 'FAIL high score'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback(NULL,4); RAISE EXCEPTION 'FAIL null ticket'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null score'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000003',3); RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO crm.support_feedback(tenant_id,ticket_id,score,recorded_by) VALUES(iam.current_tenant_id(),''e0800000-0000-0000-0000-000000000003'',1,iam.current_user_id())','UPDATE crm.support_feedback SET score=5','DELETE FROM crm.support_feedback','TRUNCATE crm.support_feedback','SET ROLE upc_feedback_executor'] LOOP
 BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 IF (SELECT count(*) FROM crm.support_feedback)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.support_feedback')<>1 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_feedback_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.support_feedback) THEN RAISE EXCEPTION 'FAIL tenant isolation'; END IF;
 PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000002',2);
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_feedback_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.support_feedback)<>1 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_feedback_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.support_feedback) THEN RAISE EXCEPTION 'FAIL missing dedicated read'; END IF;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4); RAISE EXCEPTION 'FAIL missing dedicated write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_feedback_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.support_feedback) THEN RAISE EXCEPTION 'FAIL unmapped'; END IF;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0800000-0000-0000-0000-000000000001',module_id,false,'b0800000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_feedback_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.support_feedback) THEN RAISE EXCEPTION 'FAIL disabled read'; END IF;
 BEGIN PERFORM crm.record_support_feedback('e0800000-0000-0000-0000-000000000001',4); RAISE EXCEPTION 'FAIL disabled write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.support_feedback WHERE tenant_id IN ('a0800000-0000-0000-0000-000000000001','a0800000-0000-0000-0000-000000000002'))<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.support_feedback' AND tenant_id IN ('a0800000-0000-0000-0000-000000000001','a0800000-0000-0000-0000-000000000002'))<>2
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='crm.support_feedback'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','crm.support_feedback','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_feedback_executor','MEMBER')
 OR has_table_privilege('upc_feedback_executor','crm.support_tickets','INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
ROLLBACK;
\echo PASS support feedback: scoped ticket, score bounds, recorded actor, exact retry, conflict, audit, rollback and permission gates

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_queue_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_queue_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_queue_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_queue_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_queue_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_queue_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_queue_a,upc_queue_b,upc_queue_reader,upc_queue_nocrm,upc_queue_unmapped,upc_queue_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0640000-0000-0000-0000-000000000001','queue-a','Synthetic A'),('a0640000-0000-0000-0000-000000000002','queue-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0640000-0000-0000-0000-00000000000'||i)::uuid,'test','queue-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0640000-0000-0000-0000-000000000002'::uuid ELSE 'a0640000-0000-0000-0000-000000000001'::uuid END,
 ('b0640000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_queue_a','upc_queue_b','upc_queue_reader','upc_queue_nocrm','upc_queue_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0640000-0000-0000-0000-000000000002'::uuid ELSE 'a0640000-0000-0000-0000-000000000001'::uuid END,
 ('b0640000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0640000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'queue-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0640000-0000-0000-0000-000000000001','a0640000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='queue-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0640000-0000-0000-0000-000000000001','a0640000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0640000-0000-0000-0000-000000000001','a0640000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('queue-1','queue-2') AND p.permission_key IN ('crm.engagement.read','crm.engagement.write','crm.queues.write','ops.audit.read'))
 OR (r.role_key='queue-3' AND p.permission_key IN ('crm.engagement.read'))
 OR (r.role_key='queue-4' AND p.permission_key IN ('crm.engagement.read','crm.engagement.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0640000-0000-0000-0000-000000000001','d0640000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0640000-0000-0000-0000-000000000001','d0640000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0640000-0000-0000-0000-000000000002','d0640000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0640000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('queue-a','queue-b') AND m.module_key='crm';

INSERT INTO crm.support_tickets(tenant_id,ticket_id,ticket_key,customer_id,subject) VALUES
 ('a0640000-0000-0000-0000-000000000001','e0640000-0000-0000-0000-000000000001','A1','d0640000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0640000-0000-0000-0000-000000000002','e0640000-0000-0000-0000-000000000002','B1','d0640000-0000-0000-0000-000000000002','Synthetic B');
SET SESSION AUTHORIZATION upc_queue_b;
SELECT crm.register_service_queue('main','Synthetic queue') AS bqueue \gset
SELECT crm.set_ticket_queue('e0640000-0000-0000-0000-000000000002',:'bqueue');
RESET SESSION AUTHORIZATION;
SELECT set_config('upc.test_foreign_queue',:'bqueue',true);
SET SESSION AUTHORIZATION upc_queue_a;
DO $$
DECLARE q uuid; q2 uuid; result uuid; ticket uuid:='e0640000-0000-0000-0000-000000000001'; orig jsonb; snap jsonb; bad text; cmd text;
BEGIN
 SELECT to_jsonb(t)-'queue_id' INTO STRICT orig FROM crm.support_tickets AS t WHERE ticket_id=ticket;
 q:=crm.register_service_queue('main','Synthetic queue');
 q2:=crm.register_service_queue('second','Synthetic second');
 SELECT to_jsonb(s) INTO STRICT snap FROM crm.service_queues s WHERE queue_id=q;
 result:=crm.register_service_queue('main','Synthetic queue');
 IF result IS DISTINCT FROM q OR snap IS DISTINCT FROM (SELECT to_jsonb(s) FROM crm.service_queues s WHERE queue_id=q) THEN RAISE EXCEPTION 'FAIL queue replay'; END IF;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','UPPER','bad key',repeat('a',81)] LOOP
  BEGIN PERFORM crm.register_service_queue(bad,'Synthetic'); RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.register_service_queue('main','Conflict'); RAISE EXCEPTION 'FAIL payload conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM crm.register_service_queue('duplicate',' synthetic queue '); RAISE EXCEPTION 'FAIL duplicate name'; EXCEPTION WHEN unique_violation THEN NULL; END;
 result:=crm.set_ticket_queue(ticket,NULL);
 IF result IS DISTINCT FROM ticket THEN RAISE EXCEPTION 'FAIL initial unassign'; END IF;
 result:=crm.set_ticket_queue(ticket,q);
 IF result IS DISTINCT FROM ticket OR NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE ticket_id=ticket AND queue_id=q) THEN RAISE EXCEPTION 'FAIL assignment'; END IF;
 result:=crm.set_ticket_queue(ticket,q);
 IF result IS DISTINCT FROM ticket THEN RAISE EXCEPTION 'FAIL assignment replay'; END IF;
 result:=crm.set_ticket_queue(ticket,q2);
 IF result IS DISTINCT FROM ticket OR NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE ticket_id=ticket AND queue_id=q2) THEN RAISE EXCEPTION 'FAIL transfer'; END IF;
 result:=crm.set_ticket_queue(ticket,q2);
 IF result IS DISTINCT FROM ticket THEN RAISE EXCEPTION 'FAIL transfer replay'; END IF;
 result:=crm.set_ticket_queue(ticket,NULL);
 IF result IS DISTINCT FROM ticket OR NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE ticket_id=ticket AND queue_id IS NULL) THEN RAISE EXCEPTION 'FAIL unassign'; END IF;
 result:=crm.set_ticket_queue(ticket,NULL);
 IF result IS DISTINCT FROM ticket OR orig IS DISTINCT FROM (SELECT to_jsonb(t)-'queue_id' FROM crm.support_tickets AS t WHERE ticket_id=ticket) THEN RAISE EXCEPTION 'FAIL unassign replay or original fields'; END IF;
 SELECT jsonb_build_object('queues',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.queue_id) FROM crm.service_queues s),'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.ticket_id) FROM crm.support_tickets t),'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events e)) INTO snap;
 BEGIN PERFORM crm.set_ticket_queue(ticket,current_setting('upc.test_foreign_queue')::uuid); RAISE EXCEPTION 'FAIL cross tenant queue'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_ticket_queue('e0640000-0000-0000-0000-000000000002',q); RAISE EXCEPTION 'FAIL cross tenant ticket'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_ticket_queue(ticket,'e0640000-0000-0000-0000-000000000099'); RAISE EXCEPTION 'FAIL missing queue'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_ticket_queue('e0640000-0000-0000-0000-000000000099',NULL); RAISE EXCEPTION 'FAIL missing ticket'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_ticket_queue(NULL,q); RAISE EXCEPTION 'FAIL null ticket'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN INSERT INTO crm.support_tickets(tenant_id,ticket_key,subject,queue_id) VALUES(iam.current_tenant_id(),'BYPASS','Synthetic',q); RAISE EXCEPTION 'FAIL direct assignment INSERT'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE crm.support_tickets SET queue_id=q WHERE ticket_id=ticket; RAISE EXCEPTION 'FAIL direct assignment UPDATE'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO crm.service_queues(tenant_id,queue_key,display_name) VALUES(iam.current_tenant_id(),''bypass'',''Invalid'')','UPDATE crm.service_queues SET display_name=''Forbidden''','DELETE FROM crm.service_queues','TRUNCATE crm.service_queues','DELETE FROM crm.support_tickets','SET ROLE upc_queue_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct DML or role %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.set_ticket_queue(ticket,q); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF snap IS DISTINCT FROM jsonb_build_object('queues',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.queue_id) FROM crm.service_queues s),'tickets',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.ticket_id) FROM crm.support_tickets t),'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events e)) THEN RAISE EXCEPTION 'FAIL rejected/replay/rollback changed facts'; END IF;
 IF (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.service_queues')<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.support_tickets' AND entity_id=ticket AND actor_user_id=iam.current_user_id() AND event_type='update')<>3 THEN RAISE EXCEPTION 'FAIL exact audit'; END IF;
 INSERT INTO crm.support_tickets(tenant_id,ticket_key,subject,customer_id,assigned_user_id) VALUES(iam.current_tenant_id(),'NEW','Synthetic','d0640000-0000-0000-0000-000000000003',iam.current_user_id());
 UPDATE crm.support_tickets SET subject='Synthetic revised',priority='high' WHERE ticket_key='NEW';
 IF NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE ticket_key='NEW' AND priority='high' AND queue_id IS NULL) OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.support_tickets')<>3 THEN RAISE EXCEPTION 'FAIL legacy write or audit isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_queue_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.service_queues)<>2 OR (SELECT count(*) FROM crm.support_tickets)<>2 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM crm.register_service_queue('main','Synthetic queue'); RAISE EXCEPTION 'FAIL reader replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_queue_nocrm;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.service_queues)<>2 THEN RAISE EXCEPTION 'FAIL engagement read'; END IF;
 UPDATE crm.support_tickets SET subject='Ordinary permitted update' WHERE ticket_key='NEW';
 IF NOT FOUND THEN RAISE EXCEPTION 'FAIL ordinary writer'; END IF;
 BEGIN PERFORM crm.set_ticket_queue('e0640000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL missing queue write permission'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_queue_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.service_queues) OR EXISTS(SELECT 1 FROM crm.support_tickets) THEN RAISE EXCEPTION 'FAIL no grants'; END IF;
 BEGIN PERFORM crm.register_service_queue('main','Synthetic queue'); RAISE EXCEPTION 'FAIL no grants write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_queue_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.service_queues) THEN RAISE EXCEPTION 'FAIL unmapped'; END IF;
 BEGIN PERFORM crm.set_ticket_queue(gen_random_uuid(),NULL); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_queue_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.service_queues)<>1 OR (SELECT count(*) FROM crm.support_tickets WHERE queue_id IS NOT NULL)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type IN ('crm.service_queues','crm.support_tickets'))<>2 THEN RAISE EXCEPTION 'FAIL B isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0640000-0000-0000-0000-000000000001',module_id,false,'b0640000-0000-0000-0000-000000000001','Synthetic revoke' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_queue_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.service_queues) OR EXISTS(SELECT 1 FROM crm.support_tickets) THEN RAISE EXCEPTION 'FAIL disabled CRM read'; END IF;
 BEGIN PERFORM crm.register_service_queue('main','Synthetic queue'); RAISE EXCEPTION 'FAIL disabled CRM replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
DECLARE c text;
BEGIN
 FOREACH c IN ARRAY ARRAY['tenant_id','ticket_id','ticket_key','customer_id','conversation_id','assigned_user_id','subject','priority','state','created_at','resolved_at'] LOOP
 IF NOT has_column_privilege('upc_runtime','crm.support_tickets',c,'INSERT') THEN RAISE EXCEPTION 'FAIL lost insert column %',c; END IF;
 END LOOP;
 FOREACH c IN ARRAY ARRAY['subject','priority','state','assigned_user_id','resolved_at','customer_id','conversation_id'] LOOP
 IF NOT has_column_privilege('upc_runtime','crm.support_tickets',c,'UPDATE') THEN RAISE EXCEPTION 'FAIL lost update column %',c; END IF;
 END LOOP;
 IF (SELECT count(*) FROM crm.customers)<>3 OR (SELECT count(*) FROM crm.service_queues)<>3 OR (SELECT count(*) FROM crm.support_tickets)<>3
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type IN ('crm.service_queues','crm.support_tickets'))<>7
 OR has_column_privilege('upc_runtime','crm.support_tickets','queue_id','INSERT,UPDATE')
 OR has_column_privilege('upc_queue_executor','crm.support_tickets','subject','SELECT,UPDATE')
 OR pg_has_role('upc_runtime','upc_queue_executor','MEMBER')
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='crm.service_queues'::regclass AND relrowsecurity AND relforcerowsecurity)
 THEN RAISE EXCEPTION 'FAIL global count or ACL'; END IF;
END $$;
ROLLBACK;
\echo PASS CRM service queues: canonical ticket, legacy ACL, exact assignment replay, tenant isolation, audit and rollback

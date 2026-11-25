\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_tag_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tag_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tag_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tag_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tag_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tag_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_tag_a,upc_tag_b,upc_tag_reader,upc_tag_nocrm,upc_tag_unmapped,upc_tag_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0630000-0000-0000-0000-000000000001','tag-a','Synthetic A'),('a0630000-0000-0000-0000-000000000002','tag-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0630000-0000-0000-0000-00000000000'||i)::uuid,'test','tag-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0630000-0000-0000-0000-000000000002'::uuid ELSE 'a0630000-0000-0000-0000-000000000001'::uuid END,
 ('b0630000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_tag_a','upc_tag_b','upc_tag_reader','upc_tag_nocrm','upc_tag_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0630000-0000-0000-0000-000000000002'::uuid ELSE 'a0630000-0000-0000-0000-000000000001'::uuid END,
 ('b0630000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0630000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'tag-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0630000-0000-0000-0000-000000000001','a0630000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='tag-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0630000-0000-0000-0000-000000000001','a0630000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0630000-0000-0000-0000-000000000001','a0630000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('tag-1','tag-2') AND p.permission_key IN ('crm.read','crm.tags.read','crm.tags.write','ops.audit.read'))
 OR (r.role_key='tag-3' AND p.permission_key IN ('crm.read','crm.tags.read'))
 OR (r.role_key='tag-4' AND p.permission_key IN ('crm.tags.read','crm.tags.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0630000-0000-0000-0000-000000000001','d0630000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0630000-0000-0000-0000-000000000001','d0630000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0630000-0000-0000-0000-000000000002','d0630000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0630000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('tag-a','tag-b') AND m.module_key='crm';
-- Seed B tag with a deterministic ID through bootstrap only using a mapped actor via API.
SET SESSION AUTHORIZATION upc_tag_b;
SELECT crm.register_customer_tag('main','Synthetic tag') AS btag \gset
SELECT crm.set_customer_tag('d0630000-0000-0000-0000-000000000002',:'btag',true);
RESET SESSION AUTHORIZATION;
-- Pass foreign ID only as synthetic test input; do not expose via runtime query.
SELECT set_config('upc.test_foreign_tag',:'btag',true);
SET SESSION AUTHORIZATION upc_tag_a;
DO $$
DECLARE tid uuid; second_tag uuid; lid uuid; cust uuid:='d0630000-0000-0000-0000-000000000001'; before_facts jsonb; before_replay jsonb; replay_id uuid; bad text; cmd text;
BEGIN
 tid:=crm.register_customer_tag('main','Synthetic tag');
 second_tag:=crm.register_customer_tag('second','Synthetic second');
 IF crm.register_customer_tag('main','Synthetic tag') IS DISTINCT FROM tid THEN RAISE EXCEPTION 'FAIL tag replay'; END IF;
 IF crm.set_customer_tag(cust,tid,false) IS NOT NULL THEN RAISE EXCEPTION 'FAIL missing detach'; END IF;
 -- Separate volatile mutations from assertions: a subquery in the same
 -- expression can use its pre-mutation snapshot, and OR order is not guaranteed.
 lid:=crm.set_customer_tag(cust,tid,true);
 IF lid IS NULL OR NOT EXISTS(SELECT 1 FROM crm.customer_tag_links WHERE link_id=lid AND is_active)
 THEN RAISE EXCEPTION 'FAIL initial attach state'; END IF;
 SELECT to_jsonb(l) INTO STRICT before_replay FROM crm.customer_tag_links AS l WHERE l.link_id=lid;
 replay_id:=crm.set_customer_tag(cust,tid,true);
 IF replay_id IS DISTINCT FROM lid
 OR before_replay IS DISTINCT FROM (SELECT to_jsonb(l) FROM crm.customer_tag_links AS l WHERE l.link_id=lid)
 THEN RAISE EXCEPTION 'FAIL attach retry identity or unchanged row'; END IF;
 replay_id:=crm.set_customer_tag(cust,tid,false);
 IF replay_id IS DISTINCT FROM lid THEN RAISE EXCEPTION 'FAIL detach identity'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customer_tag_links WHERE link_id=lid AND NOT is_active)
 THEN RAISE EXCEPTION 'FAIL detach persisted state'; END IF;
 SELECT to_jsonb(l) INTO STRICT before_replay FROM crm.customer_tag_links AS l WHERE l.link_id=lid;
 replay_id:=crm.set_customer_tag(cust,tid,false);
 IF replay_id IS DISTINCT FROM lid
 OR before_replay IS DISTINCT FROM (SELECT to_jsonb(l) FROM crm.customer_tag_links AS l WHERE l.link_id=lid)
 THEN RAISE EXCEPTION 'FAIL detach retry identity or unchanged row'; END IF;
 replay_id:=crm.set_customer_tag(cust,tid,true);
 IF replay_id IS DISTINCT FROM lid OR NOT EXISTS(SELECT 1 FROM crm.customer_tag_links WHERE link_id=lid AND is_active)
 THEN RAISE EXCEPTION 'FAIL reattach identity or persisted state'; END IF;
 PERFORM crm.set_customer_tag(cust,second_tag,true);
 PERFORM crm.set_customer_tag('d0630000-0000-0000-0000-000000000003',tid,true);
 IF (SELECT count(*) FROM crm.customer_tags)<>2 OR (SELECT count(*) FROM crm.customer_tag_links WHERE is_active)<>3
 OR (SELECT count(*) FROM crm.customers)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.customer_tags')<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.customer_tag_links')<>5
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_id=lid AND entity_type='crm.customer_tag_links' AND actor_user_id=iam.current_user_id())<>3
 THEN RAISE EXCEPTION 'FAIL relationship or audit count'; END IF;
 SELECT jsonb_build_object('tags',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tag_id) FROM crm.customer_tags AS t),
 'links',(SELECT jsonb_agg(to_jsonb(l) ORDER BY l.link_id) FROM crm.customer_tag_links AS l),
 'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events AS e)) INTO before_facts;
 BEGIN PERFORM crm.register_customer_tag('main','Conflict'); RAISE EXCEPTION 'FAIL tag conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM crm.register_customer_tag('duplicate',' synthetic tag '); RAISE EXCEPTION 'FAIL duplicate name'; EXCEPTION WHEN unique_violation THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','UPPER','bad key',repeat('a',81)] LOOP
  BEGIN PERFORM crm.register_customer_tag(bad,'Synthetic'); RAISE EXCEPTION 'FAIL bad key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.register_customer_tag('invalid',E' \t'); RAISE EXCEPTION 'FAIL blank name'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.set_customer_tag(cust,tid,NULL); RAISE EXCEPTION 'FAIL null state'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.set_customer_tag('d0630000-0000-0000-0000-000000000002',tid,true); RAISE EXCEPTION 'FAIL cross tenant customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_customer_tag(cust,current_setting('upc.test_foreign_tag')::uuid,true); RAISE EXCEPTION 'FAIL cross tenant tag'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.set_customer_tag(cust,'d0630000-0000-0000-0000-000000000099',false); RAISE EXCEPTION 'FAIL nonexistent tag'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO crm.customer_tags(tenant_id,tag_key,display_name) VALUES(iam.current_tenant_id(),''bypass'',''Invalid'')',
 'UPDATE crm.customer_tags SET display_name=''Forbidden''','DELETE FROM crm.customer_tags','TRUNCATE crm.customer_tags',
 'INSERT INTO crm.customer_tag_links(tenant_id,customer_id,tag_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid())',
 'UPDATE crm.customer_tag_links SET is_active=false','DELETE FROM crm.customer_tag_links','SET ROLE upc_tag_executor','DELETE FROM ops.audit_events'] LOOP
 BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct DML/role %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.set_customer_tag(cust,tid,false); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF before_facts IS DISTINCT FROM jsonb_build_object('tags',(SELECT jsonb_agg(to_jsonb(t) ORDER BY t.tag_id) FROM crm.customer_tags AS t),
 'links',(SELECT jsonb_agg(to_jsonb(l) ORDER BY l.link_id) FROM crm.customer_tag_links AS l),
 'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events AS e)) THEN RAISE EXCEPTION 'FAIL replay/rejection/rollback changed facts'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tag_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customer_tags)<>2 OR (SELECT count(*) FROM crm.customer_tag_links)<>3 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM crm.register_customer_tag('main','Synthetic tag'); RAISE EXCEPTION 'FAIL reader replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tag_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_tags) OR EXISTS(SELECT 1 FROM crm.customer_tag_links) THEN RAISE EXCEPTION 'FAIL missing CRM read'; END IF;
 BEGIN PERFORM crm.register_customer_tag('main','Synthetic tag'); RAISE EXCEPTION 'FAIL missing CRM read write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tag_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_tags) OR EXISTS(SELECT 1 FROM crm.customer_tag_links) THEN RAISE EXCEPTION 'FAIL no grants'; END IF;
 BEGIN PERFORM crm.register_customer_tag('main','Synthetic tag'); RAISE EXCEPTION 'FAIL no grants write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tag_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_tags) THEN RAISE EXCEPTION 'FAIL unmapped'; END IF;
 BEGIN PERFORM crm.set_customer_tag(gen_random_uuid(),gen_random_uuid(),false); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tag_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customer_tags)<>1 OR (SELECT count(*) FROM crm.customer_tag_links)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type LIKE 'crm.customer_tag%')<>2 THEN RAISE EXCEPTION 'FAIL B isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0630000-0000-0000-0000-000000000001',module_id,false,'b0630000-0000-0000-0000-000000000001','Synthetic revoke' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_tag_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_tags) OR EXISTS(SELECT 1 FROM crm.customer_tag_links) THEN RAISE EXCEPTION 'FAIL disabled CRM read'; END IF;
 BEGIN PERFORM crm.register_customer_tag('main','Synthetic tag'); RAISE EXCEPTION 'FAIL disabled CRM replay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customers)<>3 OR (SELECT count(*) FROM crm.customer_tags)<>3 OR (SELECT count(*) FROM crm.customer_tag_links)<>4
 OR EXISTS(SELECT 1 FROM crm.customer_identifiers) OR EXISTS(SELECT 1 FROM crm.customer_consent_events)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type LIKE 'crm.customer_tag%')<>9
 OR (SELECT count(*) FROM pg_class WHERE oid IN ('crm.customer_tags'::regclass,'crm.customer_tag_links'::regclass) AND relrowsecurity AND relforcerowsecurity)<>2
 OR has_table_privilege('upc_runtime','crm.customer_tags','INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_table_privilege('upc_runtime','crm.customer_tag_links','INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_column_privilege('upc_tag_executor','crm.customers','display_name','SELECT')
 OR pg_has_role('upc_runtime','upc_tag_executor','MEMBER')
 THEN RAISE EXCEPTION 'FAIL global canonical count or ACL'; END IF;
END $$;
ROLLBACK;
\echo PASS CRM tags: existing customer identity, exact retry, reversible link, RLS, module revoke, audit and rollback

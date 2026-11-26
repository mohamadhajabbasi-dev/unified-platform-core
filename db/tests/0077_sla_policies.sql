\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_sla_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sla_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sla_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sla_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sla_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_sla_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_sla_a,upc_sla_b,upc_sla_reader,upc_sla_nocrm,upc_sla_unmapped,upc_sla_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0770000-0000-0000-0000-000000000001','sla-policy-a','Synthetic A'),('a0770000-0000-0000-0000-000000000002','sla-policy-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0770000-0000-0000-0000-00000000000'||i)::uuid,'test','sla-policy-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0770000-0000-0000-0000-000000000002'::uuid ELSE 'a0770000-0000-0000-0000-000000000001'::uuid END,
 ('b0770000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_sla_a','upc_sla_b','upc_sla_reader','upc_sla_nocrm','upc_sla_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0770000-0000-0000-0000-000000000002'::uuid ELSE 'a0770000-0000-0000-0000-000000000001'::uuid END,
 ('b0770000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0770000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'sla-policy-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0770000-0000-0000-0000-000000000001','a0770000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='sla-policy-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0770000-0000-0000-0000-000000000001','a0770000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0770000-0000-0000-0000-000000000001','a0770000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('sla-policy-1','sla-policy-2') AND p.permission_key IN ('crm.engagement.read','crm.engagement.write','crm.sla.read','crm.sla.write','ops.audit.read'))
 OR (r.role_key='sla-policy-3' AND p.permission_key IN ('crm.engagement.read','crm.sla.read'))
 OR (r.role_key='sla-policy-4' AND p.permission_key IN ('crm.sla.read','crm.sla.write')));
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0770000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('sla-policy-a','sla-policy-b') AND m.module_key='crm';
SET SESSION AUTHORIZATION upc_sla_b;
SELECT crm.register_sla_policy('standard',60,240);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_a;
DO $$
DECLARE pid uuid; previous jsonb; cmd text; bad text;
BEGIN
 pid:=crm.register_sla_policy('standard',15,120);
 SELECT to_jsonb(v) INTO previous FROM crm.sla_policies v WHERE policy_id=pid;
 IF pid IS NULL OR previous IS NULL OR crm.register_sla_policy('standard',15,120) IS DISTINCT FROM pid
 OR (SELECT to_jsonb(v) FROM crm.sla_policies v WHERE policy_id=pid) IS DISTINCT FROM previous
 OR (SELECT count(*) FROM crm.sla_policies)<>1
 OR NOT EXISTS(SELECT 1 FROM crm.sla_policies WHERE response_minutes=15 AND resolution_minutes=120)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.sla_policies' AND entity_id=pid AND actor_user_id=iam.current_user_id() AND event_type='insert')<>1
 THEN RAISE EXCEPTION 'FAIL replay or audit'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',16,120); RAISE EXCEPTION 'FAIL response conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM crm.register_sla_policy('standard',15,121); RAISE EXCEPTION 'FAIL resolution conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','STANDARD','with space',repeat('a',81)] LOOP
 BEGIN PERFORM crm.register_sla_policy(bad,15,120); RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.register_sla_policy('bad',0,120); RAISE EXCEPTION 'FAIL zero target'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.register_sla_policy('bad',-1,120); RAISE EXCEPTION 'FAIL negative target'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.register_sla_policy('bad',120,15); RAISE EXCEPTION 'FAIL inverted targets'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.register_sla_policy('bad',NULL,120); RAISE EXCEPTION 'FAIL null response'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.register_sla_policy('bad',15,NULL); RAISE EXCEPTION 'FAIL null resolution'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO crm.sla_policies(tenant_id,policy_key,response_minutes,resolution_minutes) VALUES(iam.current_tenant_id(),''direct'',1,2)','UPDATE crm.sla_policies SET response_minutes=1','DELETE FROM crm.sla_policies','TRUNCATE crm.sla_policies','SET ROLE upc_sla_executor','DELETE FROM ops.audit_events'] LOOP
 BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.register_sla_policy('rollback',5,5); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM crm.sla_policies)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.sla_policies')<>1 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.sla_policies)<>1 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL reader retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.sla_policies) THEN RAISE EXCEPTION 'FAIL missing base read'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL missing base write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.sla_policies) THEN RAISE EXCEPTION 'FAIL no permission'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL no write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.sla_policies) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants WHERE tenant_id='a0770000-0000-0000-0000-000000000001' AND permission_key='crm.engagement.write';
SET SESSION AUTHORIZATION upc_sla_a;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.sla_policies)<>1 THEN RAISE EXCEPTION 'FAIL read after write revoke'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL revoked base write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason) SELECT 'a0770000-0000-0000-0000-000000000001',module_id,false,'b0770000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_sla_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.sla_policies) THEN RAISE EXCEPTION 'FAIL disabled CRM'; END IF;
 BEGIN PERFORM crm.register_sla_policy('standard',15,120); RAISE EXCEPTION 'FAIL disabled CRM write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_sla_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.sla_policies)<>1 OR NOT EXISTS(SELECT 1 FROM crm.sla_policies WHERE policy_key='standard' AND response_minutes=60 AND resolution_minutes=240) THEN RAISE EXCEPTION 'FAIL other tenant'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.sla_policies)<>2 OR (SELECT count(DISTINCT policy_id) FROM crm.sla_policies)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.sla_policies')<>2
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='crm.sla_policies'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','crm.sla_policies','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_sla_executor','MEMBER')
 OR has_table_privilege('upc_sla_executor','crm.support_tickets','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_sla_executor','crm.service_queues','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_sla_executor','crm.customers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_sla_executor','ops.audit_events','SELECT,INSERT,UPDATE,DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='crm.register_sla_policy(text,integer,integer)'::regprocedure AND r.rolname='upc_sla_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS SLA policy definitions: tenant scope, module and permission gates, target bounds, exact retry, immutable conflict, audit and rollback

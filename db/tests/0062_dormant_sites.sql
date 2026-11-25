\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_site_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_site_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_site_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_site_none LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_site_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_site_a,upc_site_b,upc_site_reader,upc_site_none,upc_site_unmapped;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0620000-0000-0000-0000-000000000001','site-a','Synthetic A'),
 ('a0620000-0000-0000-0000-000000000002','site-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0620000-0000-0000-0000-00000000000'||i)::uuid,'test','site-'||i FROM generate_series(1,4) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0620000-0000-0000-0000-000000000002'::uuid ELSE 'a0620000-0000-0000-0000-000000000001'::uuid END,
 ('b0620000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_site_a','upc_site_b','upc_site_reader','upc_site_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0620000-0000-0000-0000-000000000002'::uuid ELSE 'a0620000-0000-0000-0000-000000000001'::uuid END,
 ('b0620000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0620000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'site-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0620000-0000-0000-0000-000000000001','a0620000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='site-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0620000-0000-0000-0000-000000000001','a0620000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0620000-0000-0000-0000-000000000001','a0620000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('site-1','site-2') AND p.permission_key IN ('tenant.sites.read','tenant.sites.write','ops.audit.read','tenant.settings.read','tenant.settings.write'))
 OR (r.role_key='site-3' AND p.permission_key='tenant.sites.read'));
SET SESSION AUTHORIZATION upc_site_b;
INSERT INTO core.tenant_settings(tenant_id,locale,timezone,website_host) VALUES(iam.current_tenant_id(),'en-US','UTC','shared.example.invalid');
SELECT core.register_site('main','Synthetic B');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_site_a;
INSERT INTO core.tenant_settings(tenant_id,locale,timezone,website_host) VALUES(iam.current_tenant_id(),'en-US','UTC','shared.example.invalid');
DO $$
DECLARE sid uuid; t uuid:=iam.current_tenant_id(); bad text; cmd text; old_facts jsonb;
BEGIN
 IF platform.commerce_eligible() THEN RAISE EXCEPTION 'FAIL fixture has commerce'; END IF;
 sid:=core.register_site('main','Synthetic A');
 IF core.register_site('main','Synthetic A') IS DISTINCT FROM sid THEN RAISE EXCEPTION 'FAIL exact retry'; END IF;
 PERFORM core.register_site('secondary','Synthetic second site');
 IF (SELECT count(*) FROM core.sites)<>2 OR EXISTS(SELECT 1 FROM core.sites WHERE tenant_id<>t)
 THEN RAISE EXCEPTION 'FAIL site scope'; END IF;
 IF (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.sites')<>2
 OR NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='core.sites' AND entity_id=sid AND actor_user_id=iam.current_user_id() AND event_type='insert')
 THEN RAISE EXCEPTION 'FAIL exact audit'; END IF;
 SELECT jsonb_build_object('sites',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.site_id) FROM core.sites AS s),'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events AS e),'settings',(SELECT to_jsonb(s) FROM core.tenant_settings s)) INTO old_facts;
 BEGIN PERFORM core.register_site('main','Different'); RAISE EXCEPTION 'FAIL conflicting retry'; EXCEPTION WHEN unique_violation THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','UPPER','bad key',repeat('a',81)] LOOP
  BEGIN PERFORM core.register_site(bad,'Synthetic'); RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',E' \t',repeat('a',201)] LOOP
  BEGIN PERFORM core.register_site('bad-name',bad); RAISE EXCEPTION 'FAIL invalid name'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO core.sites(tenant_id,site_key,display_name) VALUES(iam.current_tenant_id(),''bypass'',''Invalid'')',
 'INSERT INTO core.sites(tenant_id,site_key,display_name) VALUES(''a0620000-0000-0000-0000-000000000002'',''cross'',''Invalid'')',
 'UPDATE core.sites SET display_name=''Forbidden''','DELETE FROM core.sites','TRUNCATE core.sites',
 'SET ROLE upc_site_executor','DELETE FROM ops.audit_events'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct DML/role: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM core.register_site('rollback','Synthetic'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF old_facts IS DISTINCT FROM jsonb_build_object('sites',(SELECT jsonb_agg(to_jsonb(s) ORDER BY s.site_id) FROM core.sites AS s),'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events AS e),'settings',(SELECT to_jsonb(s) FROM core.tenant_settings s))
 OR platform.commerce_eligible() THEN RAISE EXCEPTION 'FAIL rejected/retry operations changed facts or activated commerce'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_site_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM core.sites)<>2 THEN RAISE EXCEPTION 'FAIL read scope'; END IF;
 BEGIN PERFORM core.register_site('main','Synthetic A'); RAISE EXCEPTION 'FAIL read-only retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_site_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.sites) THEN RAISE EXCEPTION 'FAIL no permission read'; END IF;
 BEGIN PERFORM core.register_site('main','Synthetic A'); RAISE EXCEPTION 'FAIL no permission create'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_site_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.sites) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM core.register_site('main','Synthetic A'); RAISE EXCEPTION 'FAIL unmapped create'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_site_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM core.sites)<>1 OR NOT EXISTS(SELECT 1 FROM core.sites WHERE site_key='main' AND display_name='Synthetic B')
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.sites')<>1
 THEN RAISE EXCEPTION 'FAIL independent same-key site'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM core.sites)<>3 OR (SELECT count(DISTINCT site_id) FROM core.sites)<>3
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.sites')<>3
 OR (SELECT count(*) FROM core.tenant_settings WHERE website_host='shared.example.invalid')<>2
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='core.sites'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','core.sites','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_site_executor','MEMBER')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='core.register_site(text,text)'::regprocedure AND r.rolname='upc_site_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural or isolation contract'; END IF;
END $$;
-- Diagnostic count from actual user schemas, not a decision ID or hardcoded total.
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant site identity: tenant scope, exact retry, conflicting payload, ACL, audit, unchanged host and no commerce activation

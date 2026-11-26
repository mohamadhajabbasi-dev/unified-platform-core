\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_incident_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_incident_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_incident_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_incident_none LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_incident_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_incident_a,upc_incident_b,upc_incident_reader,upc_incident_none,upc_incident_unmapped;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0700000-0000-0000-0000-000000000001','incident-a','Synthetic A'),
 ('a0700000-0000-0000-0000-000000000002','incident-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0700000-0000-0000-0000-00000000000'||i)::uuid,'test','incident-'||i FROM generate_series(1,4) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0700000-0000-0000-0000-000000000002'::uuid ELSE 'a0700000-0000-0000-0000-000000000001'::uuid END,
 ('b0700000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_incident_a','upc_incident_b','upc_incident_reader','upc_incident_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0700000-0000-0000-0000-000000000002'::uuid ELSE 'a0700000-0000-0000-0000-000000000001'::uuid END,
 ('b0700000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0700000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'incident-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0700000-0000-0000-0000-000000000001','a0700000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='incident-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0700000-0000-0000-0000-000000000001','a0700000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0700000-0000-0000-0000-000000000001','a0700000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('incident-1','incident-2') AND p.permission_key IN ('ops.incidents.read','ops.incidents.write','ops.audit.read'))
 OR (r.role_key='incident-3' AND p.permission_key='ops.incidents.read') OR (r.role_key='incident-4' AND p.permission_key='ops.incidents.write'));
SET SESSION AUTHORIZATION upc_incident_b;
SELECT ops.register_incident_report('d0700000-0000-0000-0000-000000000001','security');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_incident_a;
DO $$
DECLARE iid uuid; before_row jsonb; bad text; cmd text;
BEGIN
 iid:=ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability');
 SELECT to_jsonb(s) INTO before_row FROM ops.incidents s WHERE incident_id=iid;
 IF ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability') IS DISTINCT FROM iid
 OR (SELECT to_jsonb(s) FROM ops.incidents s WHERE incident_id=iid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM ops.incidents)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='ops.incidents' AND entity_id=iid AND actor_user_id=iam.current_user_id() AND event_type='insert')<>1
 THEN RAISE EXCEPTION 'FAIL replay, tenant scope or audit'; END IF;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000001','security'); RAISE EXCEPTION 'FAIL conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM ops.register_incident_report(NULL,'availability'); RAISE EXCEPTION 'FAIL null key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.register_incident_report('00000000-0000-0000-0000-000000000000','availability'); RAISE EXCEPTION 'FAIL zero key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','SECURITY','unverified','raw log'] LOOP
  BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000002',bad); RAISE EXCEPTION 'FAIL invalid kind'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO ops.incidents(tenant_id,report_key,report_kind) VALUES(iam.current_tenant_id(),gen_random_uuid(),''availability'')',
 'INSERT INTO ops.incidents(tenant_id,report_key,report_kind) VALUES(''a0700000-0000-0000-0000-000000000002'',gen_random_uuid(),''security'')',
 'UPDATE ops.incidents SET report_kind=''security''','DELETE FROM ops.incidents','TRUNCATE ops.incidents',
 'SET ROLE upc_incident_executor','DELETE FROM ops.audit_events'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000002','security'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.incidents)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='ops.incidents')<>1
 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_incident_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.incidents)<>1 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability'); RAISE EXCEPTION 'FAIL reader retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_incident_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.incidents) THEN RAISE EXCEPTION 'FAIL missing read permission'; END IF;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability'); RAISE EXCEPTION 'FAIL write-only'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_incident_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.incidents) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability'); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants WHERE tenant_id='a0700000-0000-0000-0000-000000000001' AND permission_key='ops.incidents.write';
SET SESSION AUTHORIZATION upc_incident_a;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.incidents)<>1 THEN RAISE EXCEPTION 'FAIL read after revoke'; END IF;
 BEGIN PERFORM ops.register_incident_report('d0700000-0000-0000-0000-000000000001','availability'); RAISE EXCEPTION 'FAIL revoked write retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_incident_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.incidents)<>1 OR NOT EXISTS(SELECT 1 FROM ops.incidents WHERE report_key='d0700000-0000-0000-0000-000000000001' AND report_kind='security') THEN RAISE EXCEPTION 'FAIL other tenant'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM ops.incidents)<>2 OR (SELECT count(DISTINCT incident_id) FROM ops.incidents)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='ops.incidents')<>2
 OR EXISTS(SELECT 1 FROM platform.tenant_module_grants WHERE tenant_id IN ('a0700000-0000-0000-0000-000000000001','a0700000-0000-0000-0000-000000000002'))
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.incidents'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','ops.incidents','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_incident_executor','MEMBER')
 OR has_table_privilege('upc_incident_executor','ops.audit_events','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_incident_executor','analytics.events','SELECT,INSERT,UPDATE,DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='ops.register_incident_report(uuid,text)'::regprocedure AND r.rolname='upc_incident_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural or isolation contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS incident report metadata: tenant isolation, explicit permission, exact retry, conflict, audit, rollback, no module activation

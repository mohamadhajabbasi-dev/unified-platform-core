\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_shipping_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_shipping_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_shipping_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_shipping_none LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_shipping_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_shipping_a,upc_shipping_b,upc_shipping_reader,upc_shipping_none,upc_shipping_unmapped;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0690000-0000-0000-0000-000000000001','shipping-a','Synthetic A'),
 ('a0690000-0000-0000-0000-000000000002','shipping-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0690000-0000-0000-0000-00000000000'||i)::uuid,'test','shipping-'||i FROM generate_series(1,4) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0690000-0000-0000-0000-000000000002'::uuid ELSE 'a0690000-0000-0000-0000-000000000001'::uuid END,
 ('b0690000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_shipping_a','upc_shipping_b','upc_shipping_reader','upc_shipping_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0690000-0000-0000-0000-000000000002'::uuid ELSE 'a0690000-0000-0000-0000-000000000001'::uuid END,
 ('b0690000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0690000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'shipping-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0690000-0000-0000-0000-000000000001','a0690000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='shipping-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0690000-0000-0000-0000-000000000001','a0690000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0690000-0000-0000-0000-000000000001','a0690000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('shipping-1','shipping-2') AND p.permission_key IN ('sales.read','sales.shipping.write','ops.audit.read'))
 OR (r.role_key='shipping-3' AND p.permission_key='sales.read') OR (r.role_key='shipping-4' AND p.permission_key='sales.shipping.write'));
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0690000-0000-0000-0000-000000000001','Synthetic shipping approval'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('shipping-a','shipping-b') AND m.module_key='sales';
SET SESSION AUTHORIZATION upc_shipping_b;
SELECT sales.register_shipping_method('standard','Synthetic B');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_shipping_a;
DO $$
DECLARE mid uuid; before_row jsonb; bad text; cmd text;
BEGIN
 mid:=sales.register_shipping_method('standard','Synthetic A');
 SELECT to_jsonb(s) INTO before_row FROM sales.shipping_methods s WHERE method_id=mid;
 IF sales.register_shipping_method('standard','Synthetic A') IS DISTINCT FROM mid
 OR (SELECT to_jsonb(s) FROM sales.shipping_methods s WHERE method_id=mid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM sales.shipping_methods)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='sales.shipping_methods' AND entity_id=mid AND actor_user_id=iam.current_user_id() AND event_type='insert')<>1
 THEN RAISE EXCEPTION 'FAIL replay, tenant scope or audit'; END IF;
 BEGIN PERFORM sales.register_shipping_method('standard','Different'); RAISE EXCEPTION 'FAIL conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'','UPPER','bad key',repeat('a',81)] LOOP
  BEGIN PERFORM sales.register_shipping_method(bad,'Synthetic'); RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',E' \\t',E'a\\nb',repeat('a',201)] LOOP
  BEGIN PERFORM sales.register_shipping_method('invalid',bad); RAISE EXCEPTION 'FAIL invalid name'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO sales.shipping_methods(tenant_id,method_key,display_name) VALUES(iam.current_tenant_id(),''bypass'',''Invalid'')',
 'INSERT INTO sales.shipping_methods(tenant_id,method_key,display_name) VALUES(''a0690000-0000-0000-0000-000000000002'',''cross'',''Invalid'')',
 'UPDATE sales.shipping_methods SET display_name=''Forbidden''','DELETE FROM sales.shipping_methods','TRUNCATE sales.shipping_methods',
 'SET ROLE upc_shipping_executor','DELETE FROM ops.audit_events'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM sales.register_shipping_method('rollback','Synthetic'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM sales.shipping_methods)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='sales.shipping_methods')<>1
 OR EXISTS(SELECT 1 FROM sales.orders) OR EXISTS(SELECT 1 FROM sales.payments)
 THEN RAISE EXCEPTION 'FAIL rollback or side effect'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_shipping_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.shipping_methods)<>1 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM sales.register_shipping_method('standard','Synthetic A'); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_shipping_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.shipping_methods) THEN RAISE EXCEPTION 'FAIL missing read permission'; END IF;
 BEGIN PERFORM sales.register_shipping_method('standard','Synthetic A'); RAISE EXCEPTION 'FAIL write-only'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_shipping_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.shipping_methods) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM sales.register_shipping_method('standard','Synthetic A'); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0690000-0000-0000-0000-000000000001',module_id,false,'b0690000-0000-0000-0000-000000000001','Synthetic revoke' FROM platform.modules WHERE module_key='sales';
SET SESSION AUTHORIZATION upc_shipping_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.shipping_methods) THEN RAISE EXCEPTION 'FAIL disabled module read'; END IF;
 BEGIN PERFORM sales.register_shipping_method('standard','Synthetic A'); RAISE EXCEPTION 'FAIL disabled module retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_shipping_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.shipping_methods)<>1 OR NOT EXISTS(SELECT 1 FROM sales.shipping_methods WHERE method_key='standard' AND display_name='Synthetic B') THEN RAISE EXCEPTION 'FAIL other tenant'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.shipping_methods)<>2 OR (SELECT count(DISTINCT method_id) FROM sales.shipping_methods)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='sales.shipping_methods')<>2
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='sales.shipping_methods'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','sales.shipping_methods','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_shipping_executor','MEMBER')
 OR has_table_privilege('upc_shipping_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_shipping_executor','inventory.stock_ledger','SELECT,INSERT,UPDATE,DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='sales.register_shipping_method(text,text)'::regprocedure AND r.rolname='upc_shipping_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural or isolation contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant shipping methods: tenant, module, read/write permission, exact retry, conflict, audit, rollback and no order effect

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_reorder_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_reorder_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_reorder_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_reorder_nowrite LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_reorder_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_reorder_a,upc_reorder_b,upc_reorder_reader,upc_reorder_nowrite,upc_reorder_unmapped;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0680000-0000-0000-0000-000000000001','reorder-a','Synthetic reorder A'),
 ('a0680000-0000-0000-0000-000000000002','reorder-b','Synthetic reorder B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0680000-0000-0000-0000-00000000000'||i)::uuid,'test','reorder-'||i FROM generate_series(1,4) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0680000-0000-0000-0000-000000000002'::uuid ELSE 'a0680000-0000-0000-0000-000000000001'::uuid END,
 ('b0680000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_reorder_a','upc_reorder_b','upc_reorder_reader','upc_reorder_nowrite'])[i]::name,
 CASE WHEN i=2 THEN 'a0680000-0000-0000-0000-000000000002'::uuid ELSE 'a0680000-0000-0000-0000-000000000001'::uuid END,
 ('b0680000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,4) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT m.tenant_id,('c0680000-0000-0000-0000-00000000000'||right(m.user_id::text,1))::uuid,'reorder-'||right(m.user_id::text,1)
 FROM iam.memberships m WHERE m.tenant_id IN ('a0680000-0000-0000-0000-000000000001','a0680000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='reorder-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0680000-0000-0000-0000-000000000001','a0680000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0680000-0000-0000-0000-000000000001','a0680000-0000-0000-0000-000000000002')
 AND ((r.role_key IN ('reorder-1','reorder-2') AND p.permission_key IN ('inventory.read','inventory.reorder.write','ops.audit.read'))
 OR (r.role_key='reorder-3' AND p.permission_key='inventory.read')
 OR (r.role_key='reorder-4' AND p.permission_key='inventory.reorder.write'));
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0680000-0000-0000-0000-000000000001','Synthetic approval'
 FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('reorder-a','reorder-b') AND m.module_key='inventory';
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('a0680000-0000-0000-0000-000000000001','f0680000-0000-0000-0000-000000000001','main','Synthetic A'),
 ('a0680000-0000-0000-0000-000000000002','f0680000-0000-0000-0000-000000000002','main','Synthetic B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0680000-0000-0000-0000-000000000001','d0680000-0000-0000-0000-000000000001','Physical A','physical'),
 ('a0680000-0000-0000-0000-000000000002','d0680000-0000-0000-0000-000000000002','Physical B','physical'),
 ('a0680000-0000-0000-0000-000000000001','d0680000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0680000-0000-0000-0000-000000000001','e0680000-0000-0000-0000-000000000001','d0680000-0000-0000-0000-000000000001','reorder-a','A'),
 ('a0680000-0000-0000-0000-000000000002','e0680000-0000-0000-0000-000000000002','d0680000-0000-0000-0000-000000000002','reorder-b','B'),
 ('a0680000-0000-0000-0000-000000000001','e0680000-0000-0000-0000-000000000003','d0680000-0000-0000-0000-000000000003','reorder-d','Digital');
SET SESSION AUTHORIZATION upc_reorder_b;
SELECT inventory.set_reorder_policy('f0680000-0000-0000-0000-000000000002','e0680000-0000-0000-0000-000000000002',2,7) AS b_policy \gset
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_reorder_a;
DO $$
DECLARE wid uuid:='f0680000-0000-0000-0000-000000000001'; vid uuid:='e0680000-0000-0000-0000-000000000001';
 id uuid; first_row jsonb; before_rejected jsonb; cmd text; bad bigint; aid bigint;
BEGIN
 IF NOT platform.module_enabled('inventory') THEN RAISE EXCEPTION 'FAIL missing inventory module'; END IF;
 id:=inventory.set_reorder_policy(wid,vid,0,1);
 IF inventory.set_reorder_policy(wid,vid,0,1) IS DISTINCT FROM id THEN RAISE EXCEPTION 'FAIL exact replay ID'; END IF;
 SELECT to_jsonb(p) INTO first_row FROM inventory.reorder_policies p WHERE policy_id=id;
 IF (SELECT count(*) FROM inventory.reorder_policies)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='inventory.reorder_policies')<>1
 OR (SELECT count(*) FROM inventory.stock_ledger)<>0
 OR (SELECT count(*) FROM procurement.purchase_orders)<>0 THEN RAISE EXCEPTION 'FAIL single metadata row/audit'; END IF;
 PERFORM inventory.set_reorder_policy(wid,vid,0,1);
 IF (SELECT to_jsonb(p) FROM inventory.reorder_policies p WHERE policy_id=id) IS DISTINCT FROM first_row THEN RAISE EXCEPTION 'FAIL exact row replay'; END IF;
 IF (SELECT count(*) FROM ops.audit_events WHERE entity_type='inventory.reorder_policies')<>1 THEN RAISE EXCEPTION 'FAIL replay audit'; END IF;
 IF inventory.set_reorder_policy(wid,vid,8,12) IS DISTINCT FROM id THEN RAISE EXCEPTION 'FAIL state update ID'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.reorder_policies p WHERE policy_id=id AND reorder_point=8 AND suggested_units=12 AND changed_at>=created_at)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='inventory.reorder_policies' AND entity_id=id)<>2 THEN RAISE EXCEPTION 'FAIL update and audit'; END IF;
 SELECT jsonb_build_object('rows',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.policy_id) FROM inventory.reorder_policies p),
  'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events e)) INTO before_rejected;
 FOREACH bad IN ARRAY ARRAY[-1::bigint] LOOP
  BEGIN PERFORM inventory.set_reorder_policy(wid,vid,bad,10); RAISE EXCEPTION 'FAIL negative point'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM inventory.set_reorder_policy(wid,vid,10,bad); RAISE EXCEPTION 'FAIL negative quantity'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 BEGIN PERFORM inventory.set_reorder_policy(wid,vid,NULL,1); RAISE EXCEPTION 'FAIL null point'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM inventory.set_reorder_policy(wid,vid,0,NULL); RAISE EXCEPTION 'FAIL null units'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM inventory.set_reorder_policy(wid,vid,0,0); RAISE EXCEPTION 'FAIL zero units'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM inventory.set_reorder_policy('f0680000-0000-0000-0000-000000000002',vid,2,7); RAISE EXCEPTION 'FAIL foreign warehouse'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM inventory.set_reorder_policy(wid,'e0680000-0000-0000-0000-000000000002',2,7); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM inventory.set_reorder_policy(wid,'e0680000-0000-0000-0000-000000000003',2,7); RAISE EXCEPTION 'FAIL digital variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO inventory.reorder_policies(tenant_id,warehouse_id,variant_id,reorder_point,suggested_units) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid(),2,7)',
 'UPDATE inventory.reorder_policies SET reorder_point=99','DELETE FROM inventory.reorder_policies','TRUNCATE inventory.reorder_policies',
 'SET ROLE upc_reorder_executor','DELETE FROM ops.audit_events'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM inventory.set_reorder_policy(wid,vid,100,100); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF jsonb_build_object('rows',(SELECT jsonb_agg(to_jsonb(p) ORDER BY p.policy_id) FROM inventory.reorder_policies p),
  'audit',(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.event_id) FROM ops.audit_events e)) IS DISTINCT FROM before_rejected
 OR (SELECT count(*) FROM inventory.stock_ledger)<>0 OR (SELECT count(*) FROM procurement.purchase_orders)<>0
 THEN RAISE EXCEPTION 'FAIL rejection/rollback altered facts'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_reorder_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM inventory.reorder_policies)<>1 THEN RAISE EXCEPTION 'FAIL reader visibility'; END IF;
 BEGIN PERFORM inventory.set_reorder_policy('f0680000-0000-0000-0000-000000000001','e0680000-0000-0000-0000-000000000001',1,4);
 RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_reorder_nowrite;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM inventory.reorder_policies) THEN RAISE EXCEPTION 'FAIL no read scope'; END IF;
 BEGIN PERFORM inventory.set_reorder_policy('f0680000-0000-0000-0000-000000000001','e0680000-0000-0000-0000-000000000001',1,4);
 RAISE EXCEPTION 'FAIL no inventory.read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_reorder_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM inventory.reorder_policies) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM inventory.set_reorder_policy('f0680000-0000-0000-0000-000000000001','e0680000-0000-0000-0000-000000000001',1,4);
 RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_reorder_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM inventory.reorder_policies)<>1 OR NOT EXISTS(SELECT 1 FROM inventory.reorder_policies WHERE reorder_point=2 AND suggested_units=7)
 THEN RAISE EXCEPTION 'FAIL tenant separation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
BEGIN
 IF (SELECT count(*) FROM inventory.reorder_policies)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='inventory.reorder_policies')<>3
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='inventory.reorder_policies'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','inventory.reorder_policies','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_reorder_executor','MEMBER')
 OR has_table_privilege('upc_reorder_executor','inventory.stock_ledger','SELECT')
 OR has_table_privilege('upc_reorder_executor','procurement.purchase_orders','SELECT')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner
     WHERE p.oid='inventory.set_reorder_policy(uuid,uuid,bigint,bigint)'::regprocedure AND r.rolname='upc_reorder_executor'
     AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural, no-leak or exact audit contract'; END IF;
END $$;
-- A new independent metadata table, not an authoritative stock/purchase master.
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant reorder policy: tenant scope, minimum ACL, physical variant, exact replay, update, audit, no stock/procurement effect

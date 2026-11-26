\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_favorite_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_favorite_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_favorite_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_favorite_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_favorite_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_favorite_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_favorite_a,upc_favorite_b,upc_favorite_reader,upc_favorite_nocrm,upc_favorite_unmapped,upc_favorite_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0720000-0000-0000-0000-000000000001','favorite-a','Synthetic A'),('a0720000-0000-0000-0000-000000000002','favorite-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0720000-0000-0000-0000-00000000000'||i)::uuid,'test','favorite-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0720000-0000-0000-0000-000000000002'::uuid ELSE 'a0720000-0000-0000-0000-000000000001'::uuid END,
 ('b0720000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_favorite_a','upc_favorite_b','upc_favorite_reader','upc_favorite_nocrm','upc_favorite_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0720000-0000-0000-0000-000000000002'::uuid ELSE 'a0720000-0000-0000-0000-000000000001'::uuid END,
 ('b0720000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0720000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'favorite-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0720000-0000-0000-0000-000000000001','a0720000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='favorite-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0720000-0000-0000-0000-000000000001','a0720000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0720000-0000-0000-0000-000000000001','a0720000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('favorite-1','favorite-2') AND p.permission_key IN ('crm.read','catalog.read','catalog.favorites.read','catalog.favorites.write','ops.audit.read'))
 OR (r.role_key='favorite-3' AND p.permission_key IN ('crm.read','catalog.read','catalog.favorites.read'))
 OR (r.role_key='favorite-4' AND p.permission_key IN ('catalog.favorites.read','catalog.favorites.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0720000-0000-0000-0000-000000000001','d0720000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0720000-0000-0000-0000-000000000001','d0720000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0720000-0000-0000-0000-000000000002','d0720000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0720000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('favorite-a','favorite-b') AND m.module_key IN ('crm','catalog');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES ('a0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001','Synthetic A','physical'),('a0720000-0000-0000-0000-000000000002','e0720000-0000-0000-0000-000000000002','Synthetic B','physical'),('a0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000003','Synthetic A2','digital');
SET SESSION AUTHORIZATION upc_favorite_b;
SELECT catalog.set_product_favorite('d0720000-0000-0000-0000-000000000002','e0720000-0000-0000-0000-000000000002',true);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_favorite_a;
DO $$
DECLARE fid uuid; replay uuid; before_row jsonb; cmd text;
BEGIN
 IF catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',false) IS NOT NULL THEN RAISE EXCEPTION 'FAIL absent remove'; END IF;
 fid:=catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true);
 SELECT to_jsonb(f) INTO before_row FROM catalog.product_favorites f WHERE favorite_id=fid;
 replay:=catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true);
 IF fid IS NULL OR replay IS DISTINCT FROM fid OR before_row IS NULL
 OR (SELECT to_jsonb(f) FROM catalog.product_favorites f WHERE favorite_id=fid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM catalog.product_favorites)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.product_favorites' AND entity_id=fid AND event_type='insert' AND actor_user_id=iam.current_user_id())<>1
 THEN RAISE EXCEPTION 'FAIL add, scope, replay or audit'; END IF;
 replay:=catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM catalog.product_favorites WHERE favorite_id=fid AND NOT is_active) THEN RAISE EXCEPTION 'FAIL deactivate'; END IF;
 SELECT to_jsonb(f) INTO before_row FROM catalog.product_favorites f WHERE favorite_id=fid;
 replay:=catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR (SELECT to_jsonb(f) FROM catalog.product_favorites f WHERE favorite_id=fid) IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'FAIL remove replay'; END IF;
 replay:=catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM catalog.product_favorites WHERE favorite_id=fid AND is_active)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.product_favorites' AND entity_id=fid AND event_type='update')<>2 THEN RAISE EXCEPTION 'FAIL reactivate/audit'; END IF;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000002','e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL foreign customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000002',false); RAISE EXCEPTION 'FAIL foreign product'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_product_favorite(NULL,'e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL null customer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001',NULL,true); RAISE EXCEPTION 'FAIL null product'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null state'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO catalog.product_favorites(tenant_id,customer_id,product_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid())',
 'UPDATE catalog.product_favorites SET is_active=false','DELETE FROM catalog.product_favorites','TRUNCATE catalog.product_favorites','SET ROLE upc_favorite_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000003',true); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM catalog.product_favorites)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.product_favorites')<>3 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_favorite_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.product_favorites)<>1 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_favorite_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.product_favorites) THEN RAISE EXCEPTION 'FAIL missing base permissions'; END IF;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL missing base permission write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_favorite_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.product_favorites) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0720000-0000-0000-0000-000000000001',module_id,false,'b0720000-0000-0000-0000-000000000001','Synthetic disabled' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_favorite_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.product_favorites) THEN RAISE EXCEPTION 'FAIL disabled catalog read'; END IF;
 BEGIN PERFORM catalog.set_product_favorite('d0720000-0000-0000-0000-000000000001','e0720000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL disabled catalog write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_favorite_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.product_favorites)<>1 OR NOT EXISTS(SELECT 1 FROM catalog.product_favorites WHERE product_id='e0720000-0000-0000-0000-000000000002' AND customer_id='d0720000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.product_favorites)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.product_favorites')<>4
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='catalog.product_favorites'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','catalog.product_favorites','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_favorite_executor','MEMBER')
 OR has_column_privilege('upc_favorite_executor','crm.customers','display_name','SELECT')
 OR has_column_privilege('upc_favorite_executor','catalog.products','name','SELECT')
 OR has_table_privilege('upc_favorite_executor','crm.customer_identifiers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_favorite_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS product favorites: composite tenant FKs, read/write and module gates, add/remove/reactivate, idempotency, audit and rollback

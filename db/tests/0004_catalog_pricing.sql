\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_cat_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_cat_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_cat_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_cat_a,upc_cat_b,upc_cat_reader;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('80000000-0000-0000-0000-000000000001','cat-a','Synthetic A'),
 ('80000000-0000-0000-0000-000000000002','cat-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('81000000-0000-0000-0000-000000000001','test','cat-a'),
 ('81000000-0000-0000-0000-000000000002','test','cat-b'),
 ('81000000-0000-0000-0000-000000000003','test','cat-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('80000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001'),
 ('80000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000002'),
 ('80000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_cat_a','80000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000001'),
 ('upc_cat_b','80000000-0000-0000-0000-000000000002','81000000-0000-0000-0000-000000000002'),
 ('upc_cat_reader','80000000-0000-0000-0000-000000000001','81000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('80000000-0000-0000-0000-000000000001','catalog-editor'),
 ('80000000-0000-0000-0000-000000000002','catalog-editor'),
 ('80000000-0000-0000-0000-000000000001','catalog-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key
 FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.role_key='catalog-editor' AND p.permission_key IN ('catalog.read','catalog.write','catalog.price.write');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'catalog.read' FROM iam.roles WHERE role_key='catalog-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id
 FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='81000000-0000-0000-0000-000000000003' AND r.role_key='catalog-reader')
 OR (m.user_id<>'81000000-0000-0000-0000-000000000003' AND r.role_key='catalog-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'81000000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('cat-a','cat-b') AND m.module_key='catalog';

SET SESSION AUTHORIZATION upc_cat_b;
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 (iam.current_tenant_id(),'82000000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 (iam.current_tenant_id(),'83000000-0000-0000-0000-000000000002','82000000-0000-0000-0000-000000000002','same-sku','Default');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 (iam.current_tenant_id(),'84000000-0000-0000-0000-000000000002','retail','USD','Retail B');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION upc_cat_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); p uuid:='82000000-0000-0000-0000-000000000001';
 v uuid:='83000000-0000-0000-0000-000000000001'; l uuid:='84000000-0000-0000-0000-000000000001';
 c uuid; old_price uuid;
BEGIN
 IF EXISTS(SELECT 1 FROM catalog.products) THEN RAISE EXCEPTION 'FAIL cross tenant read'; END IF;
 INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES(t,p,'Synthetic A','physical');
 INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES(t,v,p,'same-sku','Default');
 BEGIN
  INSERT INTO catalog.variants(tenant_id,product_id,sku,name) VALUES(t,p,'SAME-SKU','Duplicate');
  RAISE EXCEPTION 'FAIL duplicate SKU';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.variants(tenant_id,product_id,sku,name) VALUES(t,'82000000-0000-0000-0000-000000000002','foreign','Foreign');
  RAISE EXCEPTION 'FAIL cross tenant product FK';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.products(tenant_id,name,kind) VALUES('80000000-0000-0000-0000-000000000002','Forbidden','physical');
  RAISE EXCEPTION 'FAIL RLS insert';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO catalog.categories(tenant_id,name) VALUES(t,'Synthetic category') RETURNING category_id INTO c;
 INSERT INTO catalog.product_categories VALUES(t,p,c);
 BEGIN
  INSERT INTO catalog.product_categories VALUES(t,p,c);
  RAISE EXCEPTION 'FAIL duplicate category relation';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES(t,l,'retail','IRR','Retail A');
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(t,v,l,1000,tstzrange('2026-01-01 00:00+00',NULL,'[)')) RETURNING price_id INTO old_price;
 BEGIN
  INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
  VALUES(t,v,l,2000,tstzrange('2026-02-01 00:00+00',NULL,'[)'));
  RAISE EXCEPTION 'FAIL overlapping price';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
  VALUES(t,v,'84000000-0000-0000-0000-000000000002',2000,tstzrange('2026-02-01 00:00+00',NULL,'[)'));
  RAISE EXCEPTION 'FAIL cross tenant price list FK';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  UPDATE catalog.price_entries SET amount=500 WHERE price_id=old_price;
  RAISE EXCEPTION 'FAIL overwrite historical price';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE catalog.price_entries SET valid_during=tstzrange('2026-01-01 00:00+00','2026-02-01 00:00+00','[)') WHERE price_id=old_price;
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(t,v,l,2000,tstzrange('2026-02-01 00:00+00',NULL,'[)'));
 IF (SELECT amount FROM catalog.price_at(v,l,'2026-01-15 00:00+00')) IS DISTINCT FROM 1000::numeric
 OR (SELECT amount FROM catalog.price_at(v,l,'2026-02-01 00:00+00')) IS DISTINCT FROM 2000::numeric
 OR (SELECT currency FROM catalog.price_at(v,l,'2026-02-01 00:00+00')) IS DISTINCT FROM 'IRR'
 THEN RAISE EXCEPTION 'FAIL price boundary or currency'; END IF;
 BEGIN
  UPDATE catalog.price_entries SET valid_during=tstzrange('2025-12-01 00:00+00','2026-02-01 00:00+00','[)') WHERE price_id=old_price;
  RAISE EXCEPTION 'FAIL move historical start';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM catalog.price_at('83000000-0000-0000-0000-000000000002','84000000-0000-0000-0000-000000000002','2026-02-01 00:00+00'))
 THEN RAISE EXCEPTION 'FAIL foreign price lookup'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_cat_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.products)<>1 OR (SELECT count(*) FROM catalog.price_entries)<>2 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN
  INSERT INTO catalog.products(tenant_id,name,kind) VALUES(iam.current_tenant_id(),'Forbidden','physical');
  RAISE EXCEPTION 'FAIL reader write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE catalog.products SET name='Forbidden';
 IF FOUND THEN RAISE EXCEPTION 'FAIL reader update'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants WHERE tenant_id='80000000-0000-0000-0000-000000000001' AND permission_key='catalog.price.write';
SET SESSION AUTHORIZATION upc_cat_a;
DO $$ BEGIN
 BEGIN
  INSERT INTO catalog.price_lists(tenant_id,list_key,currency,name) VALUES(iam.current_tenant_id(),'forbidden','USD','Forbidden');
  RAISE EXCEPTION 'FAIL revoked price permission';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF (SELECT count(*) FROM catalog.products)<>1 THEN RAISE EXCEPTION 'FAIL permission separation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '80000000-0000-0000-0000-000000000001',module_id,false,'81000000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_cat_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.products) OR EXISTS(SELECT 1 FROM catalog.price_entries) THEN RAISE EXCEPTION 'FAIL disabled catalog read'; END IF;
 BEGIN
  INSERT INTO catalog.products(tenant_id,name,kind) VALUES(iam.current_tenant_id(),'Forbidden','physical');
  RAISE EXCEPTION 'FAIL disabled catalog write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS catalog: tenant SKU, composite FKs, RLS, temporal prices, historical amount protection and permission revocation

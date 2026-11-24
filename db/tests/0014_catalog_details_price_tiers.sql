\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_catalog_detail_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_catalog_detail_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_catalog_detail_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_catalog_detail_admin;
GRANT upc_runtime TO upc_catalog_detail_a,upc_catalog_detail_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('e0000000-0000-0000-0000-000000000001','cat-detail-a','Synthetic A'),
 ('e0000000-0000-0000-0000-000000000002','cat-detail-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('e1000000-0000-0000-0000-000000000001','synthetic','cat-admin'),
 ('e1000000-0000-0000-0000-000000000002','synthetic','cat-a'),
 ('e1000000-0000-0000-0000-000000000003','synthetic','cat-b');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin)
 VALUES('upc_catalog_detail_admin','e1000000-0000-0000-0000-000000000001',true);
INSERT INTO iam.memberships VALUES
 ('e0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002',clock_timestamp()),
 ('e0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003',clock_timestamp());
INSERT INTO iam.db_principals VALUES
 ('upc_catalog_detail_a','e0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000002'),
 ('upc_catalog_detail_b','e0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('e0000000-0000-0000-0000-000000000001','cat-details-writer'),
 ('e0000000-0000-0000-0000-000000000002','cat-details-writer');
INSERT INTO iam.role_grants(tenant_id,role_id,permission_key)
 SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='cat-details-writer' AND p.permission_key IN ('catalog.read','catalog.write','catalog.price.write');
INSERT INTO iam.membership_roles(tenant_id,user_id,role_id)
 SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m
 JOIN iam.roles r ON r.tenant_id=m.tenant_id WHERE r.role_key='cat-details-writer';
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('e0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000001','Synthetic buyer A'),
 ('e0000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000002','Synthetic buyer B');
SET SESSION AUTHORIZATION upc_catalog_detail_admin;
SELECT platform.record_module_decision('e0000000-0000-0000-0000-000000000001','catalog',true,NULL,'Synthetic catalog approval');
SELECT platform.record_module_decision('e0000000-0000-0000-0000-000000000002','catalog',true,NULL,'Synthetic catalog approval');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION upc_catalog_detail_a;
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 (iam.current_tenant_id(),'e3000000-0000-0000-0000-000000000001','Synthetic Brand');
INSERT INTO catalog.measure_units(tenant_id,unit_id,unit_key,name) VALUES
 (iam.current_tenant_id(),'e4000000-0000-0000-0000-000000000001','piece','Piece');
INSERT INTO catalog.products(tenant_id,product_id,name,kind,brand_id,unit_id)
 VALUES(iam.current_tenant_id(),'e5000000-0000-0000-0000-000000000001','Synthetic product','physical',
 'e3000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000001');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name)
 VALUES(iam.current_tenant_id(),'e6000000-0000-0000-0000-000000000001',
 'e5000000-0000-0000-0000-000000000001','SYN-14','Synthetic variant');
INSERT INTO catalog.product_media(tenant_id,product_id,kind,storage_ref,alt_text)
 VALUES(iam.current_tenant_id(),'e5000000-0000-0000-0000-000000000001',
 'image','test-asset-ref-14','Synthetic media');
INSERT INTO catalog.product_warranties(tenant_id,product_id,provider_name,duration_months)
 VALUES(iam.current_tenant_id(),'e5000000-0000-0000-0000-000000000001',
 'Synthetic provider',12);
INSERT INTO catalog.product_reviews(tenant_id,product_id,customer_id,score,review_text)
 VALUES(iam.current_tenant_id(),'e5000000-0000-0000-0000-000000000001',
 'e2000000-0000-0000-0000-000000000001',5,'Synthetic review');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name)
 VALUES(iam.current_tenant_id(),'e7000000-0000-0000-0000-000000000001','standard','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,price_id,variant_id,price_list_id,amount,valid_during)
 VALUES(iam.current_tenant_id(),'e8000000-0000-0000-0000-000000000001',
 'e6000000-0000-0000-0000-000000000001','e7000000-0000-0000-0000-000000000001',
 100,tstzrange(clock_timestamp()-interval '1 hour',NULL,'[)'));
INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount)
 VALUES(iam.current_tenant_id(),'e8000000-0000-0000-0000-000000000001',
 int8range(10,NULL,'[)'),90);
DO $$
DECLARE low_price numeric; bulk_price numeric;
BEGIN
 SELECT amount INTO low_price FROM catalog.price_for_quantity(
 'e6000000-0000-0000-0000-000000000001','e7000000-0000-0000-0000-000000000001',1);
 SELECT amount INTO bulk_price FROM catalog.price_for_quantity(
 'e6000000-0000-0000-0000-000000000001','e7000000-0000-0000-0000-000000000001',10);
 IF low_price<>100 OR bulk_price<>90 OR
  (SELECT count(*) FROM catalog.product_media)<>1 OR
  (SELECT count(*) FROM catalog.product_reviews WHERE NOT is_approved)<>1 THEN
  RAISE EXCEPTION 'FAIL catalog detail / tier amount';
 END IF;
 BEGIN
  INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount)
  VALUES(iam.current_tenant_id(),'e8000000-0000-0000-0000-000000000001',
   int8range(12,20,'[)'),80);
  RAISE EXCEPTION 'FAIL overlapping tier';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.product_reviews(tenant_id,product_id,customer_id,score)
  VALUES(iam.current_tenant_id(),'e5000000-0000-0000-0000-000000000001',
   'e2000000-0000-0000-0000-000000000002',4);
  RAISE EXCEPTION 'FAIL cross tenant review customer';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_catalog_detail_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.brands) OR EXISTS(SELECT 1 FROM catalog.product_media)
 OR EXISTS(SELECT 1 FROM catalog.product_reviews) OR EXISTS(SELECT 1 FROM catalog.price_quantity_tiers)
 THEN RAISE EXCEPTION 'FAIL catalog tenant isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_catalog_detail_admin;
SELECT platform.record_module_decision('e0000000-0000-0000-0000-000000000001','catalog',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_catalog_detail_a;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM catalog.product_media) THEN
 RAISE EXCEPTION 'FAIL revocation of catalog module'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS product details + existing canonical price lists + non-overlapping quantity tiers + tenant RLS

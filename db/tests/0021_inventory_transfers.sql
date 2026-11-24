\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_inv_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_inv_a,upc_inv_b,upc_inv_reader;
GRANT upc_checkout_offline TO upc_inv_a,upc_inv_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('90000000-0000-0000-0000-000000000001','inv-a','Synthetic A'),
 ('90000000-0000-0000-0000-000000000002','inv-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('91000000-0000-0000-0000-000000000001','test','inv-a'),
 ('91000000-0000-0000-0000-000000000002','test','inv-b'),
 ('91000000-0000-0000-0000-000000000003','test','inv-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001'),
 ('90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002'),
 ('90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_inv_a','90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001'),
 ('upc_inv_b','90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002'),
 ('upc_inv_reader','90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('90000000-0000-0000-0000-000000000001','inventory-editor'),
 ('90000000-0000-0000-0000-000000000002','inventory-editor'),
 ('90000000-0000-0000-0000-000000000001','inventory-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='91000000-0000-0000-0000-000000000003' AND r.role_key='inventory-reader')
 OR (m.user_id<>'91000000-0000-0000-0000-000000000003' AND r.role_key='inventory-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','A','physical'),
 ('90000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','B','physical'),
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','stock-a','A'),
 ('90000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','stock-b','B'),
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','main','A'),
 ('90000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000002','main','B');

GRANT upc_payment_recorder TO upc_inv_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND (p.permission_key LIKE 'sales.%' OR p.permission_key IN ('crm.read','catalog.read'));
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'sales.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic sales test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key IN ('sales','crm','catalog');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('90000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('90000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000002','Synthetic customer B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000004','No stock','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000004','no-stock','No stock');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('90000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','original','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT '90000000-0000-0000-0000-000000000001',v.variant_id,'96000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='90000000-0000-0000-0000-000000000001';

INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'procurement.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'procurement.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic procurement'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='procurement';
GRANT upc_supplier_document_verifier,upc_supplier_payment_verifier TO upc_inv_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'finance.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic finance'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='finance';
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000004','second','Synthetic second');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); w uuid:='94000000-0000-0000-0000-000000000001'; dest uuid:='94000000-0000-0000-0000-000000000004';
 v uuid:='93000000-0000-0000-0000-000000000001'; v2 uuid:='93000000-0000-0000-0000-000000000004'; tid uuid; ln jsonb; hold uuid;
BEGIN
 PERFORM inventory.adjust_stock(w,v,10,'transfer-seed-a','Synthetic');
 PERFORM inventory.adjust_stock(w,v2,5,'transfer-seed-b','Synthetic');
 hold:=inventory.reserve_stock(w,v,4,'transfer-hold',clock_timestamp()+interval '1 hour');
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',6),jsonb_build_object('variant_id',v2,'quantity',3));
 BEGIN PERFORM inventory.transfer_stock('too-many',w,dest,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',7))); RAISE EXCEPTION 'FAIL reserved transfer'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.transfer_stock('bad-second',w,dest,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1),jsonb_build_object('variant_id',v2,'quantity',6))); RAISE EXCEPTION 'FAIL atomic transfer'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT count(*) FROM inventory.stock_ledger)<>2 OR EXISTS(SELECT 1 FROM inventory.warehouse_transfers) THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
 tid:=inventory.transfer_stock('transfer-1',w,dest,'Synthetic',ln);
 IF inventory.transfer_stock('transfer-1',w,dest,'Synthetic',jsonb_build_array(ln->1,ln->0))<>tid THEN RAISE EXCEPTION 'FAIL retry'; END IF;
 IF (SELECT count(*) FROM inventory.transfer_lines)<>2 OR (SELECT count(*) FROM inventory.stock_ledger WHERE adjustment_key LIKE 'transfer:%')<>4
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>15
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE warehouse_id=w AND variant_id=v)<>4
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE warehouse_id=dest AND variant_id=v)<>6 THEN RAISE EXCEPTION 'FAIL conservation'; END IF;
 BEGIN PERFORM inventory.transfer_stock('transfer-1',w,dest,'Changed',ln); RAISE EXCEPTION 'FAIL key conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM inventory.transfer_stock('foreign',w,'94000000-0000-0000-0000-000000000002','Synthetic',ln); RAISE EXCEPTION 'FAIL foreign warehouse'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM inventory.transfer_stock('same',w,w,'Synthetic',ln); RAISE EXCEPTION 'FAIL same warehouse'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM inventory.adjust_stock(w,v,1,'transfer:forged','Forbidden'); RAISE EXCEPTION 'FAIL forged transfer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM inventory.transfer_lines; RAISE EXCEPTION 'FAIL direct mutation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.warehouse_transfers) OR EXISTS(SELECT 1 FROM inventory.transfer_lines) THEN RAISE EXCEPTION 'FAIL leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM inventory.warehouse_transfers)<>1 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM inventory.transfer_stock('denied',gen_random_uuid(),gen_random_uuid(),'Forbidden','[]'); RAISE EXCEPTION 'FAIL reader transfer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS transfer: canonical paired ledger, conservation, reserved stock, atomic multi-line rollback, idempotency and tenant isolation

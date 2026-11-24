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
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000011','second','Second');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; dst uuid:='94000000-0000-0000-0000-000000000011';
 v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000004';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; l1 uuid; l2 uuid; expired uuid; s1 uuid; s2 uuid; supplier uuid; po uuid; rid uuid; tid uuid; alloc jsonb; bad jsonb; po2 uuid;
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 l1:=inventory.register_lot(v,'L1',d-1,d+10); l2:=inventory.register_lot(v,'L2',d-2,d+20);
 expired:=inventory.register_lot(v,'OLD',d-10,d);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 supplier:=procurement.register_counterparty('trace-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('trace-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5,'unit_cost',100),jsonb_build_object('variant_id',sv,'quantity',2,'unit_cost',200)));
 alloc:=jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',2),jsonb_build_object('variant_id',v,'lot_id',l2,'quantity',3),
 jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1),jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1));
 BEGIN PERFORM procurement.receive_purchase(po,'plain','Synthetic'); RAISE EXCEPTION 'FAIL ordinary receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM procurement.receive_purchase_allocated(po,'short','Synthetic',alloc-0); RAISE EXCEPTION 'FAIL incomplete allocation'; EXCEPTION WHEN check_violation THEN NULL; END;
 bad:=jsonb_set(alloc,'{1,lot_id}',to_jsonb(expired));
 BEGIN PERFORM procurement.receive_purchase_allocated(po,'expired','Synthetic',bad); RAISE EXCEPTION 'FAIL expired receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM inventory.stock_ledger) OR EXISTS(SELECT 1 FROM procurement.goods_receipts) THEN RAISE EXCEPTION 'FAIL atomic receipt rollback'; END IF;
 rid:=procurement.receive_purchase_allocated(po,'receipt','Synthetic',alloc);
 IF procurement.receive_purchase_allocated(po,'receipt','Synthetic',jsonb_build_array(alloc->3,alloc->1,alloc->2,alloc->0))<>rid
 OR (SELECT count(*) FROM procurement.receipt_items WHERE receipt_id=rid)<>4
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>7 THEN RAISE EXCEPTION 'FAIL receipt or retry'; END IF;
 BEGIN PERFORM procurement.receive_purchase(po,'receipt','Synthetic'); RAISE EXCEPTION 'FAIL changed retry'; EXCEPTION WHEN unique_violation THEN NULL; END;
 po2:=procurement.issue_purchase('duplicate-serial',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',100)));
 BEGIN PERFORM procurement.receive_purchase_allocated(po2,'duplicate-serial','Synthetic',jsonb_build_array(alloc->2)); RAISE EXCEPTION 'FAIL duplicate serial receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 bad:=jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',3));
 BEGIN PERFORM inventory.transfer_allocated('bad',w,dst,'Synthetic',bad); RAISE EXCEPTION 'FAIL wrong lot quantity'; EXCEPTION WHEN check_violation THEN NULL; END;
 tid:=inventory.transfer_allocated('transfer',w,dst,'Synthetic',jsonb_build_array(alloc->0,alloc->2));
 IF inventory.transfer_allocated('transfer',w,dst,'Synthetic',jsonb_build_array(alloc->2,alloc->0))<>tid
 OR (SELECT count(*) FROM inventory.transfer_lines WHERE transfer_id=tid)<>2
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>7
 OR NOT EXISTS(SELECT 1 FROM inventory.trace_balances WHERE warehouse_id=dst AND lot_id=l1 AND on_hand=2)
 OR NOT EXISTS(SELECT 1 FROM inventory.trace_balances WHERE warehouse_id=dst AND serial_id=s1 AND on_hand=1)
 OR EXISTS(SELECT 1 FROM inventory.trace_balances WHERE warehouse_id=w AND serial_id=s1)
 THEN RAISE EXCEPTION 'FAIL transfer conservation'; END IF;
 BEGIN PERFORM inventory.transfer_allocated('transfer',w,dst,'Synthetic',jsonb_build_array(alloc->1,alloc->2)); RAISE EXCEPTION 'FAIL transfer changed retry'; EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM inventory.release_reservation(inventory.reserve_stock(dst,sv,1,'trace-hold',clock_timestamp()+interval '1 hour'));
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM procurement.receipt_items) OR EXISTS(SELECT 1 FROM inventory.transfer_lines) OR EXISTS(SELECT 1 FROM inventory.trace_balances) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS trace receipt and transfer: exact split allocation, serial uniqueness, expiry rollback, conservation, retries and tenant isolation

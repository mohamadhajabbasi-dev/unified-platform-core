\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_inv_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_inv_a,upc_inv_b,upc_inv_reader;
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
 ('90000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','retail','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT '90000000-0000-0000-0000-000000000001',v.variant_id,'96000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='90000000-0000-0000-0000-000000000001';

GRANT upc_refund_recorder TO upc_inv_a;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 c uuid:='95000000-0000-0000-0000-000000000001'; l uuid:='96000000-0000-0000-0000-000000000001';
 deadline timestamptz:=clock_timestamp()+interval '1 hour'; captured timestamptz; refunded timestamptz;
 oid uuid; oid2 uuid; pid uuid; pid2 uuid; rid uuid; fid uuid;
 lines jsonb:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'expected_unit_price',1000));
BEGIN
 PERFORM inventory.adjust_stock(w,v,10,'return-test-receipt','Receipt');
 oid:=sales.create_checkout('return-1',c,w,l,'web',deadline,lines);
 captured:=clock_timestamp();
 pid:=sales.record_capture(oid,'synthetic','acct','capture-1',2000,'IRR',captured);
 PERFORM sales.fulfill_order(oid);
 BEGIN
  PERFORM sales.record_full_refund(pid,'refund-1',2000,'IRR',clock_timestamp());
  RAISE EXCEPTION 'FAIL refund before physical return';
 EXCEPTION WHEN check_violation THEN NULL; END;
 rid:=sales.receive_full_return(oid,'received-1','All items inspected');
 IF sales.receive_full_return(oid,'received-1','All items inspected')<>rid THEN RAISE EXCEPTION 'FAIL return retry'; END IF;
 BEGIN
  PERFORM sales.receive_full_return(oid,'received-1','Changed reason');
  RAISE EXCEPTION 'FAIL return key conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM inventory.adjust_stock(w,v,2,'sales-return:forged','Forbidden');
  RAISE EXCEPTION 'FAIL forged return ledger';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 refunded:=clock_timestamp();
 BEGIN
  PERFORM sales.record_full_refund(pid,'refund-1',2001,'IRR',refunded);
  RAISE EXCEPTION 'FAIL excessive refund';
 EXCEPTION WHEN check_violation THEN NULL; END;
 fid:=sales.record_full_refund(pid,'refund-1',2000,'IRR',refunded);
 IF sales.record_full_refund(pid,'refund-1',2000,'IRR',refunded)<>fid THEN RAISE EXCEPTION 'FAIL refund retry'; END IF;
 BEGIN
  PERFORM sales.record_full_refund(pid,'refund-2',2000,'IRR',refunded);
  RAISE EXCEPTION 'FAIL second refund';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=10 AND available=10) OR
  (SELECT count(*) FROM inventory.stock_ledger)<>3 OR (SELECT count(*) FROM sales.returns)<>1
 THEN RAISE EXCEPTION 'FAIL restock once'; END IF;
 -- Late capture after cancellation is recorded as review, never fulfilled.
 oid2:=sales.create_checkout('late-1',c,w,l,'app',deadline,lines);
 PERFORM sales.cancel_order(oid2);
 pid2:=sales.record_capture(oid2,'synthetic','acct','capture-2',2000,'IRR',clock_timestamp());
 IF NOT EXISTS(SELECT 1 FROM sales.orders WHERE order_id=oid2 AND state='payment_review')
 THEN RAISE EXCEPTION 'FAIL late capture not preserved'; END IF;
 BEGIN
  PERFORM sales.fulfill_order(oid2);
  RAISE EXCEPTION 'FAIL late capture fulfillment';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM sales.record_full_refund(pid2,'refund-1',2000,'IRR',clock_timestamp());
  RAISE EXCEPTION 'FAIL refund reference reuse';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM sales.record_full_refund(pid2,'refund-3',2000,'IRR',clock_timestamp());
 IF (SELECT count(*) FROM sales.refunds)<>2 OR (SELECT count(*) FROM sales.orders WHERE state='refunded')<>2
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=10 AND reserved=0 AND available=10)
 THEN RAISE EXCEPTION 'FAIL refund lifecycle'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.returns) OR EXISTS(SELECT 1 FROM sales.refunds) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF;
 BEGIN
  PERFORM sales.record_full_refund(gen_random_uuid(),'forbidden',1,'IRR',clock_timestamp());
  RAISE EXCEPTION 'FAIL unauthorized recorder';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS returns: full restock once, verified full refund, duplicate rejection, late capture review, tenant gates

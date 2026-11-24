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
 c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; early uuid; late uuid; s1 uuid; s2 uuid; oid uuid; r uuid; rid uuid; alloc jsonb; ln jsonb; dl timestamptz:=clock_timestamp()+interval '1 hour';
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true); PERFORM inventory.configure_tracking(sv,'serial',false);
 late:=inventory.register_lot(v,'LATE',d-1,d+20); early:=inventory.register_lot(v,'EARLY',d-1,d+2);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 PERFORM inventory.adjust_traced(w,v,late,NULL,5,'late','Synthetic'); PERFORM inventory.adjust_traced(w,v,early,NULL,2,'early','Synthetic');
 PERFORM inventory.adjust_traced(w,sv,NULL,s1,1,'serial1','Synthetic'); PERFORM inventory.adjust_traced(w,sv,NULL,s2,1,'serial2','Synthetic');
 BEGIN PERFORM inventory.reserve_stock(w,v,1,'expiry-too-long',dl+interval '30 days'); RAISE EXCEPTION 'FAIL reservation beyond expiry'; EXCEPTION WHEN check_violation THEN NULL; END;
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'expected_unit_price',1000),jsonb_build_object('variant_id',sv,'quantity',2,'expected_unit_price',1000));
 oid:=sales.create_checkout('trace-checkout',c,w,pl,'in_person',dl,ln);
 IF sales.create_checkout('trace-checkout',c,w,pl,'in_person',dl,ln)<>oid
 OR (SELECT count(*) FROM inventory.reservation_allocations)<>4
 OR NOT EXISTS(SELECT 1 FROM inventory.reservation_allocations WHERE lot_id=early AND quantity=2)
 OR NOT EXISTS(SELECT 1 FROM inventory.reservation_allocations WHERE lot_id=late AND quantity=1) THEN RAISE EXCEPTION 'FAIL FEFO allocation'; END IF;
 BEGIN PERFORM inventory.adjust_traced(w,v,early,NULL,-1,'steal-lot','Synthetic'); RAISE EXCEPTION 'FAIL reserved lot adjustment'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.transfer_allocated('steal-lot',w,dst,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',early,'quantity',1))); RAISE EXCEPTION 'FAIL reserved lot transfer'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.reserve_stock(w,sv,1,'steal-serial',dl); RAISE EXCEPTION 'FAIL duplicate serial reservation'; EXCEPTION WHEN check_violation THEN NULL; END;
 r:=inventory.reserve_stock(w,v,1,'extra-hold',dl);
 PERFORM inventory.release_reservation(r);
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE variant_id=v AND on_hand=7 AND reserved=3 AND available=4) THEN RAISE EXCEPTION 'FAIL released stock'; END IF;
 PERFORM sales.record_capture(oid,'synthetic','acct','trace-payment',5000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid); PERFORM sales.fulfill_order(oid);
 IF (SELECT count(*) FROM inventory.stock_ledger WHERE allocation_id IS NOT NULL)<>4
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>4
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE variant_id=v AND on_hand=4 AND reserved=0 AND available=4) THEN RAISE EXCEPTION 'FAIL fulfilled trace stock'; END IF;
 SELECT jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity)) INTO alloc
 FROM sales.order_items i JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id) WHERE i.order_id=oid;
 BEGIN PERFORM sales.receive_full_return(oid,'missing','Synthetic'); RAISE EXCEPTION 'FAIL unverified tracked return'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM sales.receive_full_return_allocated(oid,'wrong','Synthetic',alloc-0); RAISE EXCEPTION 'FAIL changed return allocation'; EXCEPTION WHEN check_violation THEN NULL; END;
 rid:=sales.receive_full_return_allocated(oid,'return','Synthetic',alloc);
 IF sales.receive_full_return_allocated(oid,'return','Synthetic',alloc)<>rid OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>9
 OR (SELECT count(*) FROM inventory.stock_ledger WHERE adjustment_key LIKE 'sales-return:%')<>4
 OR NOT EXISTS(SELECT 1 FROM sales.orders WHERE order_id=oid AND state='returned')
 THEN RAISE EXCEPTION 'FAIL trace return'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.reservation_allocations) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS tracked sales: FEFO, expiry deadline, exact holds, reserved-lot protection, paid fulfillment and confirmed full return

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

SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 c uuid:='95000000-0000-0000-0000-000000000001'; l uuid:='96000000-0000-0000-0000-000000000001';
 deadline timestamptz:=clock_timestamp()+interval '1 hour'; captured timestamptz; oid uuid; oid2 uuid; pid uuid; rid uuid;
 lines jsonb:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'expected_unit_price',1000));
BEGIN
 PERFORM inventory.adjust_stock(w,v,10,'sales-test-receipt','Receipt');
 BEGIN
  PERFORM sales.create_checkout('atomic-fail',c,w,l,'web',deadline,lines||jsonb_build_array(jsonb_build_object('variant_id','93000000-0000-0000-0000-000000000004','quantity',1,'expected_unit_price',1000)));
  RAISE EXCEPTION 'FAIL atomic checkout';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM sales.orders) OR EXISTS(SELECT 1 FROM inventory.reservations) THEN RAISE EXCEPTION 'FAIL partial checkout persisted'; END IF;
 BEGIN
  PERFORM sales.create_checkout('price-fail',c,w,l,'web',deadline,jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'expected_unit_price',999)));
  RAISE EXCEPTION 'FAIL stale price';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM sales.create_checkout('foreign','95000000-0000-0000-0000-000000000002',w,l,'web',deadline,lines);
  RAISE EXCEPTION 'FAIL foreign customer';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 oid:=sales.create_checkout('checkout-1',c,w,l,'web',deadline,lines);
 IF sales.create_checkout('checkout-1',c,w,l,'web',deadline,lines)<>oid THEN RAISE EXCEPTION 'FAIL checkout retry'; END IF;
 BEGIN
  PERFORM sales.create_checkout('checkout-1',c,w,l,'app',deadline,lines);
  RAISE EXCEPTION 'FAIL checkout payload conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT total FROM sales.order_totals WHERE order_id=oid) IS DISTINCT FROM 2000::numeric THEN RAISE EXCEPTION 'FAIL order total'; END IF;
 SELECT reservation_id INTO STRICT rid FROM sales.order_items WHERE order_id=oid;
 BEGIN
  PERFORM inventory.release_reservation(rid);
  RAISE EXCEPTION 'FAIL direct order reservation release';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM inventory.consume_reservation(rid);
  RAISE EXCEPTION 'FAIL direct order reservation consume';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM inventory.consume_reservation_internal(rid);
  RAISE EXCEPTION 'FAIL internal function exposed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM inventory.reserve_stock(w,v,1,'sales:forged',deadline);
  RAISE EXCEPTION 'FAIL reserved namespace';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM sales.fulfill_order(oid);
  RAISE EXCEPTION 'FAIL unpaid fulfillment';
 EXCEPTION WHEN check_violation THEN NULL; END;
 captured:=clock_timestamp();
 BEGIN
  PERFORM sales.record_capture(oid,'synthetic','acct','ref-1',1999,'IRR',captured);
  RAISE EXCEPTION 'FAIL wrong payment amount';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM sales.record_capture(oid,'synthetic','acct','ref-1',2000,'USD',captured);
  RAISE EXCEPTION 'FAIL wrong payment currency';
 EXCEPTION WHEN check_violation THEN NULL; END;
 pid:=sales.record_capture(oid,'synthetic','acct','ref-1',2000,'IRR',captured);
 IF sales.record_capture(oid,'synthetic','acct','ref-1',2000,'IRR',captured)<>pid THEN RAISE EXCEPTION 'FAIL duplicate payment'; END IF;
 BEGIN
  PERFORM sales.cancel_order(oid);
  RAISE EXCEPTION 'FAIL paid cancellation';
 EXCEPTION WHEN check_violation THEN NULL; END;
 oid2:=sales.create_checkout('checkout-2',c,w,l,'app',deadline,lines);
 BEGIN
  PERFORM sales.record_capture(oid2,'synthetic','acct','ref-1',2000,'IRR',captured);
  RAISE EXCEPTION 'FAIL cross order payment reuse';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM sales.cancel_order(oid2);
 PERFORM sales.cancel_order(oid2);
 PERFORM sales.fulfill_order(oid);
 PERFORM sales.fulfill_order(oid);
 IF (SELECT count(*) FROM sales.payments)<>1 OR (SELECT count(*) FROM inventory.stock_ledger)<>2
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=8 AND reserved=0 AND available=8)
 OR NOT EXISTS(SELECT 1 FROM sales.orders WHERE order_id=oid AND state='fulfilled')
 OR NOT EXISTS(SELECT 1 FROM sales.orders WHERE order_id=oid2 AND state='cancelled')
 THEN RAISE EXCEPTION 'FAIL lifecycle totals'; END IF;
 BEGIN
  UPDATE sales.order_items SET unit_price=1;
  RAISE EXCEPTION 'FAIL direct price snapshot edit';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Change the current price after checkout; the historical snapshot must be unchanged.
UPDATE catalog.price_entries SET valid_during=tstzrange('2020-01-01 00:00+00',clock_timestamp(),'[)')
 WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND variant_id='93000000-0000-0000-0000-000000000001';
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001',1200,tstzrange(clock_timestamp(),NULL,'[)'));
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.order_totals WHERE total<>2000) THEN RAISE EXCEPTION 'FAIL historical price changed'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.orders) OR EXISTS(SELECT 1 FROM sales.payments) OR EXISTS(SELECT 1 FROM sales.order_totals) THEN RAISE EXCEPTION 'FAIL cross-tenant sales visibility'; END IF;
 BEGIN
  PERFORM sales.record_capture(gen_random_uuid(),'synthetic','acct','unauthorized',1,'IRR',clock_timestamp());
  RAISE EXCEPTION 'FAIL ordinary role recorded capture';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.orders)<>2 THEN RAISE EXCEPTION 'FAIL sales reader'; END IF;
 BEGIN
  PERFORM sales.cancel_order((SELECT order_id FROM sales.orders LIMIT 1));
  RAISE EXCEPTION 'FAIL reader cancellation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,false,'91000000-0000-0000-0000-000000000001','Disable' FROM platform.modules WHERE module_key='sales';
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.orders) THEN RAISE EXCEPTION 'FAIL disabled sales read'; END IF;
 BEGIN
  PERFORM sales.fulfill_order(gen_random_uuid());
  RAISE EXCEPTION 'FAIL disabled sales write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS sales: atomic checkout, current price snapshot, verified capture idempotency, reserved stock ownership, cancellation, fulfillment and tenant gates

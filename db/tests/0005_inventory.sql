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

SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 expiry timestamptz:=clock_timestamp()+interval '1 hour'; m uuid; r uuid; r2 uuid; consumed uuid;
BEGIN
 m:=inventory.adjust_stock(w,v,10,'receipt-1','Receipt');
 IF inventory.adjust_stock(w,v,10,'receipt-1','Receipt')<>m THEN RAISE EXCEPTION 'FAIL adjustment retry'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock(w,v,11,'receipt-1','Receipt');
  RAISE EXCEPTION 'FAIL adjustment conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM inventory.adjust_stock(w,'93000000-0000-0000-0000-000000000002',1,'foreign','Forbidden');
  RAISE EXCEPTION 'FAIL foreign variant';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  PERFORM inventory.adjust_stock(w,'93000000-0000-0000-0000-000000000003',1,'digital','Forbidden');
  RAISE EXCEPTION 'FAIL digital variant';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 r:=inventory.reserve_stock(w,v,7,'checkout-1',expiry);
 IF inventory.reserve_stock(w,v,7,'checkout-1',expiry)<>r THEN RAISE EXCEPTION 'FAIL reserve retry'; END IF;
 BEGIN
  PERFORM inventory.reserve_stock(w,v,6,'checkout-1',expiry);
  RAISE EXCEPTION 'FAIL reservation conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM inventory.reserve_stock(w,v,4,'checkout-2',expiry);
  RAISE EXCEPTION 'FAIL oversell';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  PERFORM inventory.adjust_stock(w,v,-4,'adjust-1','Forbidden');
  RAISE EXCEPTION 'FAIL reserved stock withdrawn';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=10 AND reserved=7 AND available=3)
 THEN RAISE EXCEPTION 'FAIL balance after reserve'; END IF;
 r2:=inventory.reserve_stock(w,v,3,'checkout-3',expiry);
 PERFORM inventory.release_reservation(r2);
 PERFORM inventory.release_reservation(r2);
 consumed:=inventory.consume_reservation(r);
 IF inventory.consume_reservation(r)<>consumed THEN RAISE EXCEPTION 'FAIL consumption retry'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=3 AND reserved=0 AND available=3)
 OR (SELECT count(*) FROM inventory.stock_ledger)<>2 THEN RAISE EXCEPTION 'FAIL consumption balance or duplicate'; END IF;
 BEGIN
  PERFORM inventory.release_reservation(r);
  RAISE EXCEPTION 'FAIL consumed released';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  UPDATE inventory.stock_ledger SET quantity_delta=99;
  RAISE EXCEPTION 'FAIL ledger mutable';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,adjustment_key,reason,recorded_by)
  VALUES(iam.current_tenant_id(),w,v,9,'direct','Forbidden',iam.current_user_id());
  RAISE EXCEPTION 'FAIL bypass ledger';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
-- Separate statement after expiry: available quantity returns automatically.
SELECT inventory.reserve_stock('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',3,'expiry',clock_timestamp()+interval '1 second');
SELECT pg_sleep(1.1);
DO $$ DECLARE rid uuid; BEGIN
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=3 AND reserved=0 AND available=3) THEN RAISE EXCEPTION 'FAIL expired hold'; END IF;
 SELECT reservation_id INTO STRICT rid FROM inventory.reservations WHERE request_key='expiry';
 BEGIN
  PERFORM inventory.consume_reservation(rid);
  RAISE EXCEPTION 'FAIL expired consume';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM inventory.stock_balances) OR EXISTS(SELECT 1 FROM inventory.reservations) THEN RAISE EXCEPTION 'FAIL cross-tenant visibility'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',1,'foreign','Forbidden');
  RAISE EXCEPTION 'FAIL cross tenant adjustment';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE available=3) THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',1,'no-write','Forbidden');
  RAISE EXCEPTION 'FAIL reader adjust';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,false,'91000000-0000-0000-0000-000000000001','Disable' FROM platform.modules WHERE module_key='inventory';
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM inventory.stock_balances) THEN RAISE EXCEPTION 'FAIL disabled module read'; END IF;
 BEGIN
  PERFORM inventory.reserve_stock('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001',1,'disabled',clock_timestamp()+interval '1 hour');
  RAISE EXCEPTION 'FAIL disabled module write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS inventory: append-only stock, idempotency, release, consumption, expiry, derived balances, oversell and tenant permissions

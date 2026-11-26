\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_stockbox_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stockbox_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stockbox_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_stockbox_a,upc_stockbox_b,upc_stockbox_reader;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0790000-0000-0000-0000-000000000001','stockbox-a','Synthetic A'),
 ('a0790000-0000-0000-0000-000000000002','stockbox-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0790000-0000-0000-0000-000000000001','test','stockbox-a'),
 ('b0790000-0000-0000-0000-000000000002','test','stockbox-b'),
 ('b0790000-0000-0000-0000-000000000003','test','stockbox-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0790000-0000-0000-0000-000000000001','b0790000-0000-0000-0000-000000000001'),
 ('a0790000-0000-0000-0000-000000000002','b0790000-0000-0000-0000-000000000002'),
 ('a0790000-0000-0000-0000-000000000001','b0790000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_stockbox_a','a0790000-0000-0000-0000-000000000001','b0790000-0000-0000-0000-000000000001'),
 ('upc_stockbox_b','a0790000-0000-0000-0000-000000000002','b0790000-0000-0000-0000-000000000002'),
 ('upc_stockbox_reader','a0790000-0000-0000-0000-000000000001','b0790000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('a0790000-0000-0000-0000-000000000001','stockbox-editor'),
 ('a0790000-0000-0000-0000-000000000002','stockbox-editor'),
 ('a0790000-0000-0000-0000-000000000001','stockbox-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0790000-0000-0000-0000-000000000001','a0790000-0000-0000-0000-000000000002') AND r.role_key='stockbox-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND role_key='stockbox-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE m.tenant_id IN ('a0790000-0000-0000-0000-000000000001','a0790000-0000-0000-0000-000000000002') AND ((m.user_id='b0790000-0000-0000-0000-000000000003' AND r.role_key='stockbox-reader')
 OR (m.user_id<>'b0790000-0000-0000-0000-000000000003' AND r.role_key='stockbox-editor'));
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0790000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('stockbox-a','stockbox-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0790000-0000-0000-0000-000000000001','c0790000-0000-0000-0000-000000000001','A','physical'),
 ('a0790000-0000-0000-0000-000000000002','c0790000-0000-0000-0000-000000000002','B','physical'),
 ('a0790000-0000-0000-0000-000000000001','c0790000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0790000-0000-0000-0000-000000000001','d0790000-0000-0000-0000-000000000001','c0790000-0000-0000-0000-000000000001','stock-a','A'),
 ('a0790000-0000-0000-0000-000000000002','d0790000-0000-0000-0000-000000000002','c0790000-0000-0000-0000-000000000002','stock-b','B'),
 ('a0790000-0000-0000-0000-000000000001','d0790000-0000-0000-0000-000000000003','c0790000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('a0790000-0000-0000-0000-000000000001','e0790000-0000-0000-0000-000000000001','main','A'),
 ('a0790000-0000-0000-0000-000000000002','e0790000-0000-0000-0000-000000000002','main','B');

SET SESSION AUTHORIZATION upc_stockbox_a;
DO $$
DECLARE w uuid:='e0790000-0000-0000-0000-000000000001'; v uuid:='d0790000-0000-0000-0000-000000000001';
 expiry timestamptz:=clock_timestamp()+interval '1 hour'; m uuid; r uuid; r2 uuid; consumed uuid;
BEGIN
 m:=inventory.adjust_stock(w,v,10,'receipt-1','Receipt');
 IF inventory.adjust_stock(w,v,10,'receipt-1','Receipt') IS DISTINCT FROM m THEN RAISE EXCEPTION 'FAIL adjustment retry'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock(w,v,11,'receipt-1','Receipt');
  RAISE EXCEPTION 'FAIL adjustment conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 r:=inventory.reserve_stock(w,v,7,'checkout-1',expiry);
 IF inventory.reserve_stock(w,v,7,'checkout-1',expiry) IS DISTINCT FROM r THEN RAISE EXCEPTION 'FAIL reservation retry'; END IF;
 BEGIN
  PERFORM inventory.reserve_stock(w,v,4,'oversell',expiry);
  RAISE EXCEPTION 'FAIL oversell';
 EXCEPTION WHEN check_violation THEN NULL; END;
 r2:=inventory.reserve_stock(w,v,3,'checkout-2',expiry);
 PERFORM inventory.release_reservation(r2);
 PERFORM inventory.release_reservation(r2);
 consumed:=inventory.consume_reservation(r);
 IF inventory.consume_reservation(r) IS DISTINCT FROM consumed THEN RAISE EXCEPTION 'FAIL consumption retry'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock(w,v,5,'rollback-movement','Rollback');
  PERFORM inventory.reserve_stock(w,v,2,'rollback-reservation',expiry);
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE on_hand=3 AND reserved=0 AND available=3)
 THEN RAISE EXCEPTION 'FAIL canonical stock balance'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock('e0790000-0000-0000-0000-000000000002','d0790000-0000-0000-0000-000000000002',1,'foreign','Forbidden');
  RAISE EXCEPTION 'FAIL cross tenant adjustment';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(iam.current_tenant_id(),'inventory.stock_ledger.changed');
  RAISE EXCEPTION 'FAIL direct outbox write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM 1 FROM ops.outbox_events;
  RAISE EXCEPTION 'FAIL direct outbox read';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stockbox_b;
SELECT inventory.adjust_stock('e0790000-0000-0000-0000-000000000002','d0790000-0000-0000-0000-000000000002',4,'receipt-1','Receipt');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stockbox_reader;
DO $$ BEGIN
 BEGIN
  PERFORM inventory.adjust_stock('e0790000-0000-0000-0000-000000000001','d0790000-0000-0000-0000-000000000001',1,'forbidden','Forbidden');
  RAISE EXCEPTION 'FAIL reader mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
BEGIN
 IF (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND event_kind='inventory.stock_ledger.changed')<>2
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001' AND event_kind='inventory.reservation.changed')<>4
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000001')<>6
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000002' AND event_kind='inventory.stock_ledger.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0790000-0000-0000-0000-000000000002')<>1
 OR (SELECT count(*) FROM inventory.stock_ledger WHERE tenant_id='a0790000-0000-0000-0000-000000000001')<>2
 OR (SELECT count(*) FROM inventory.reservations WHERE tenant_id='a0790000-0000-0000-0000-000000000001')<>2
 THEN RAISE EXCEPTION 'FAIL exact inventory event counts, isolation, retry or rollback'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.outbox_events'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR (SELECT count(*) FROM pg_trigger WHERE tgfoid='ops.capture_price_entry_change()'::regprocedure AND NOT tgisinternal)<>3
 OR EXISTS(SELECT 1 FROM pg_auth_members WHERE roleid='upc_outbox_capture'::regrole)
 OR has_table_privilege('upc_outbox_capture','inventory.stock_ledger','SELECT')
 OR has_table_privilege('upc_outbox_capture','inventory.reservations','UPDATE')
 OR has_table_privilege('upc_runtime','ops.outbox_events','SELECT')
 THEN RAISE EXCEPTION 'FAIL shared writer security contract'; END IF;
END $$;
ROLLBACK;
\echo PASS inventory outbox: canonical ledger and reservation changes, exact retries, rollback, denied writes and tenant isolation

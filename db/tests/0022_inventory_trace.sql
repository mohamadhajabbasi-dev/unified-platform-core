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

INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000011','92000000-0000-0000-0000-000000000001','serial-a','Serial'),
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000012','92000000-0000-0000-0000-000000000001','ordinary-a','Ordinary');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000011','second','Second');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; dest uuid:='94000000-0000-0000-0000-000000000011';
 v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000011'; ov uuid:='93000000-0000-0000-0000-000000000012';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; l uuid; expired uuid; s uuid; m uuid;
BEGIN
 PERFORM inventory.adjust_stock(w,ov,1,'ordinary','Synthetic');
 BEGIN PERFORM inventory.configure_tracking(ov,'lot',false); RAISE EXCEPTION 'FAIL existing stock enrollment'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(v,'lot',true);
 BEGIN PERFORM inventory.configure_tracking(v,'serial',true); RAISE EXCEPTION 'FAIL policy conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM inventory.register_lot(v,'missing-expiry',d,NULL); RAISE EXCEPTION 'FAIL expiry required'; EXCEPTION WHEN check_violation THEN NULL; END;
 l:=inventory.register_lot(v,'BATCH-1',d-1,d+10);
 IF inventory.register_lot(v,'BATCH-1',d-1,d+10)<>l THEN RAISE EXCEPTION 'FAIL lot retry'; END IF;
 BEGIN PERFORM inventory.register_lot(v,'BATCH-1',d-1,d+11); RAISE EXCEPTION 'FAIL lot conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 expired:=inventory.register_lot(v,'EXPIRED',d-10,d);
 BEGIN PERFORM inventory.adjust_traced(w,v,expired,NULL,1,'expired','Synthetic'); RAISE EXCEPTION 'FAIL expired admission'; EXCEPTION WHEN check_violation THEN NULL; END;
 m:=inventory.adjust_traced(w,v,l,NULL,5,'lot-in','Synthetic');
 IF inventory.adjust_traced(w,v,l,NULL,5,'lot-in','Synthetic')<>m THEN RAISE EXCEPTION 'FAIL movement retry'; END IF;
 BEGIN PERFORM inventory.adjust_traced(w,v,l,NULL,6,'lot-in','Synthetic'); RAISE EXCEPTION 'FAIL movement conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM inventory.adjust_traced(w,v,l,NULL,-6,'lot-out-bad','Synthetic'); RAISE EXCEPTION 'FAIL lot negative'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM inventory.adjust_traced(w,v,l,NULL,-2,'lot-out','Synthetic disposal');
 BEGIN PERFORM inventory.adjust_stock(w,v,1,'plain-tracked','Synthetic'); RAISE EXCEPTION 'FAIL untracked adjustment'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.adjust_stock(w,ov,1,'trace:forged','Synthetic'); RAISE EXCEPTION 'FAIL forged namespace'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM inventory.reserve_stock(w,v,1,'trace-hold',clock_timestamp()+interval '1 hour'); RAISE EXCEPTION 'FAIL unallocated reservation'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.transfer_stock('trace-transfer',w,dest,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1))); RAISE EXCEPTION 'FAIL untracked transfer'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM inventory.configure_tracking(sv,'serial',false);
 s:=inventory.register_serial(sv,'SERIAL-1');
 PERFORM inventory.adjust_traced(w,sv,NULL,s,1,'serial-in','Synthetic');
 BEGIN PERFORM inventory.adjust_traced(dest,sv,NULL,s,1,'serial-duplicate','Synthetic'); RAISE EXCEPTION 'FAIL serial duplicated across warehouses'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.adjust_traced(w,sv,NULL,s,2,'serial-bad-qty','Synthetic'); RAISE EXCEPTION 'FAIL serial quantity'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM inventory.adjust_traced(dest,sv,NULL,s,-1,'serial-wrong-warehouse','Synthetic'); RAISE EXCEPTION 'FAIL serial negative'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM inventory.trace_balances WHERE lot_id=l AND on_hand=3 AND expiry_state='valid')
 OR NOT EXISTS(SELECT 1 FROM inventory.trace_balances WHERE serial_id=s AND on_hand=1)
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE variant_id=v AND on_hand=3 AND available=0)
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_balances WHERE variant_id=ov AND available=1) THEN RAISE EXCEPTION 'FAIL derived balances'; END IF;
 BEGIN UPDATE inventory.inventory_lots SET expires_on=d+100; RAISE EXCEPTION 'FAIL lot mutation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.tracking_policies) OR EXISTS(SELECT 1 FROM inventory.trace_balances) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN IF (SELECT count(*) FROM inventory.trace_balances)<>2 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM inventory.configure_tracking(gen_random_uuid(),'lot',false); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS trace foundation: lot and serial provenance, expiry admission, canonical balances, fail-closed unadapted paths and tenant isolation

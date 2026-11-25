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
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000003','second','Second warehouse');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000004','third','Third warehouse');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; dst uuid:='94000000-0000-0000-0000-000000000003'; third uuid:='94000000-0000-0000-0000-000000000004';
 v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000004';
 c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid();
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 l1 uuid; l2 uuid; s1 uuid; s2 uuid; supplier uuid; po uuid; po_pending uuid; tid1 uuid; tid2 uuid; tid3 uuid; oid uuid; n bigint;
 a record; b record; cc record; lines jsonb; move_id uuid;
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 PERFORM finance.configure_valuation_preview(v,'lot_fifo','IRR');
 PERFORM finance.configure_valuation_preview(sv,'serial_specific','IRR');
 l1:=inventory.register_lot(v,'L1',d-1,d+10); l2:=inventory.register_lot(v,'L2',d-1,d+20);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 supplier:=procurement.register_counterparty('trace-chain-supplier',NULL,'Synthetic');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 po:=procurement.issue_purchase('trace-chain-1',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',4,'unit_cost',100),jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',80)));
 PERFORM procurement.receive_purchase_allocated(po,'trace-chain-r1','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',4),jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1)));
 PERFORM finance.record_supplier_invoice(po,'TRACE-CHAIN-1',d,d+7,480,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('trace-chain-2',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'unit_cost',200),jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',190)));
 PERFORM procurement.receive_purchase_allocated(po,'trace-chain-r2','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l2,'quantity',3),jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1)));
 PERFORM finance.record_supplier_invoice(po,'TRACE-CHAIN-2',d,d+7,790,'IRR',digest,asset,ap);
 lines:=jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',3),jsonb_build_object('variant_id',v,'lot_id',l2,'quantity',2),
 jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1),jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1));
 tid1:=inventory.transfer_allocated('trace-chain-ab',w,dst,'Synthetic',lines);
 tid2:=inventory.transfer_allocated('trace-chain-bc',dst,third,'Synthetic',lines);
 tid3:=inventory.transfer_allocated('trace-chain-ca',third,w,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',1),jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1)));
 po_pending:=procurement.issue_purchase('trace-chain-pending',supplier,third,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1,'unit_cost',150)));
 PERFORM procurement.receive_purchase_allocated(po_pending,'trace-chain-r3','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',1)));
 BEGIN PERFORM finance.capture_transfer_costs(tid2,v); RAISE EXCEPTION 'FAIL uninvoiced chain accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) THEN RAISE EXCEPTION 'FAIL partial chain facts'; END IF;
 PERFORM finance.record_supplier_invoice(po_pending,'TRACE-CHAIN-3',d,d+7,150,'IRR',digest,asset,ap);
 n:=finance.capture_transfer_costs(tid2,v);
 IF n<>13 THEN RAISE EXCEPTION 'FAIL lot chain count %',n; END IF;
 n:=finance.capture_transfer_costs(tid3,sv);
 IF n<>12 THEN RAISE EXCEPTION 'FAIL serial chain count %',n; END IF;
 IF finance.capture_transfer_costs(tid1,v)<>0 OR finance.capture_transfer_costs(tid2,sv)<>0 THEN RAISE EXCEPTION 'FAIL chain retry'; END IF;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(dst,v);
 SELECT * INTO cc FROM finance.configured_inventory_preview(third,v);
 IF a.on_hand<>3 OR a.remaining_value<>400 OR b.on_hand<>0 OR b.remaining_value<>0 OR cc.on_hand<>5 OR cc.remaining_value<>750 OR cc.consumed_cost<>0
 THEN RAISE EXCEPTION 'FAIL lot chain balance'; END IF;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,sv);
 SELECT * INTO b FROM finance.configured_inventory_preview(dst,sv);
 SELECT * INTO cc FROM finance.configured_inventory_preview(third,sv);
 IF a.on_hand<>1 OR a.remaining_value<>80 OR b.on_hand<>0 OR b.remaining_value<>0 OR cc.on_hand<>1 OR cc.remaining_value<>190
 THEN RAISE EXCEPTION 'FAIL serial chain balance'; END IF;
 IF (SELECT count(*) FROM inventory.transfer_lines)<>10
 OR (SELECT count(*) FROM inventory.transfer_lines tl JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id WHERE fo.value_delta=-fi.value_delta AND fo.quantity_delta=-fi.quantity_delta)<>10
 OR (SELECT count(*) FROM finance.journal_entries)<>3
 OR (SELECT sum(value_delta) FROM finance.movement_cost_facts)<>1420
 THEN RAISE EXCEPTION 'FAIL paired chain and value conservation'; END IF;
 oid:=sales.create_checkout('trace-chain-sale',c,third,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'expected_unit_price',1000),jsonb_build_object('variant_id',sv,'quantity',1,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','trace-chain-payment',3000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 n:=finance.capture_movement_costs(third,v); IF n<>1 THEN RAISE EXCEPTION 'FAIL remote lot sale count'; END IF;
 n:=finance.capture_movement_costs(third,sv); IF n<>1 THEN RAISE EXCEPTION 'FAIL remote serial sale count'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id JOIN inventory.stock_ledger sl ON sl.tenant_id=fa.tenant_id AND sl.movement_id=fa.outgoing_movement_id WHERE sl.reservation_id IS NOT NULL AND sl.lot_id=l1 AND rb.warehouse_id=w AND fa.quantity=2 AND fa.cost=200)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id JOIN inventory.stock_ledger sl ON sl.tenant_id=fa.tenant_id AND sl.movement_id=fa.outgoing_movement_id WHERE sl.reservation_id IS NOT NULL AND sl.serial_id=s2 AND rb.warehouse_id=w AND fa.quantity=1 AND fa.cost=190)
 OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN inventory.stock_ledger src ON src.tenant_id=fa.tenant_id AND src.movement_id=fa.receipt_movement_id JOIN inventory.stock_ledger dest ON dest.tenant_id=fa.tenant_id AND dest.movement_id=fa.outgoing_movement_id WHERE src.lot_id IS DISTINCT FROM dest.lot_id OR src.serial_id IS DISTINCT FROM dest.serial_id)
 OR (SELECT sum(value_delta) FROM finance.movement_cost_facts)<>1030
 OR (SELECT count(*) FROM finance.journal_entries)<>3
 THEN RAISE EXCEPTION 'FAIL remote tracked sale provenance'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.capture_transfer_costs(gen_random_uuid(),'93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unauthorized transfer capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) THEN RAISE EXCEPTION 'FAIL cross tenant chain visibility'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS traced multiline transfer cost chain, rollback, exact lot and serial remote provenance and isolation

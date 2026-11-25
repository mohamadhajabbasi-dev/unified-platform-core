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
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; dst uuid:='94000000-0000-0000-0000-000000000003';
 v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000004';
 c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid();
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 late uuid; early uuid; s1 uuid; s2 uuid; supplier uuid; po uuid; oid uuid; n bigint;
 late_first uuid; late_second uuid; early_source uuid; serial_first uuid; serial_second uuid; late_sale uuid;
 a record; b record;
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 PERFORM finance.configure_valuation_preview(v,'lot_fifo','IRR');
 PERFORM finance.configure_valuation_preview(sv,'serial_specific','IRR');
 late:=inventory.register_lot(v,'LATE',d-1,d+20);
 early:=inventory.register_lot(v,'EARLY',d-1,d+10);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 supplier:=procurement.register_counterparty('tracked-cost-supplier',NULL,'Synthetic');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 po:=procurement.issue_purchase('tracked-cost-1',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1,'unit_cost',100)));
 PERFORM procurement.receive_purchase_allocated(po,'tracked-cost-r1','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',late,'quantity',1)));
 SELECT rb.movement_id INTO STRICT late_first FROM finance.receipt_cost_basis rb WHERE rb.purchase_id=po;
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL unconfirmed capture'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) THEN RAISE EXCEPTION 'FAIL unconfirmed write'; END IF;
 PERFORM finance.record_supplier_invoice(po,'TRACKED-1',d,d+7,100,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('tracked-cost-2',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'unit_cost',120)));
 PERFORM procurement.receive_purchase_allocated(po,'tracked-cost-r2','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',late,'quantity',3)));
 SELECT rb.movement_id INTO STRICT late_second FROM finance.receipt_cost_basis rb WHERE rb.purchase_id=po;
 PERFORM finance.record_supplier_invoice(po,'TRACKED-2',d,d+7,360,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('tracked-cost-3',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'unit_cost',200)));
 PERFORM procurement.receive_purchase_allocated(po,'tracked-cost-r3','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',early,'quantity',2)));
 SELECT rb.movement_id INTO STRICT early_source FROM finance.receipt_cost_basis rb WHERE rb.purchase_id=po;
 PERFORM finance.record_supplier_invoice(po,'TRACKED-3',d,d+7,400,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('tracked-cost-s1',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',80)));
 PERFORM procurement.receive_purchase_allocated(po,'tracked-cost-sr1','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1)));
 SELECT rb.movement_id INTO STRICT serial_first FROM finance.receipt_cost_basis rb WHERE rb.purchase_id=po;
 PERFORM finance.record_supplier_invoice(po,'TRACKED-S1',d,d+7,80,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('tracked-cost-s2',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',190)));
 PERFORM procurement.receive_purchase_allocated(po,'tracked-cost-sr2','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1)));
 SELECT rb.movement_id INTO STRICT serial_second FROM finance.receipt_cost_basis rb WHERE rb.purchase_id=po;
 PERFORM finance.record_supplier_invoice(po,'TRACKED-S2',d,d+7,190,'IRR',digest,asset,ap);
 oid:=sales.create_checkout('tracked-cost-sale',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',4,'expected_unit_price',1000),jsonb_build_object('variant_id',sv,'quantity',2,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','tracked-cost-payment',6000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(w,sv);
 IF a.on_hand<>2 OR a.remaining_value<>240 OR a.consumed_cost<>620 OR NOT a.all_receipts_invoiced
 OR b.on_hand<>0 OR b.remaining_value<>0 OR b.consumed_cost<>270 OR NOT b.all_receipts_invoiced
 THEN RAISE EXCEPTION 'FAIL tracked preview'; END IF;
 BEGIN PERFORM finance.preview_inventory_valuation(w,v,'IRR','fifo'); RAISE EXCEPTION 'FAIL ordinary method for traced stock'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.preview_inventory_valuation(w,v,'USD','lot_fifo'); RAISE EXCEPTION 'FAIL incompatible tracked currency'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) THEN RAISE EXCEPTION 'FAIL preview wrote facts'; END IF;
 n:=finance.capture_movement_costs(w,v);
 IF n<>5 THEN RAISE EXCEPTION 'FAIL lot cost capture count %',n; END IF;
 n:=finance.capture_movement_costs(w,sv);
 IF n<>4 THEN RAISE EXCEPTION 'FAIL serial cost capture count %',n; END IF;
 IF finance.capture_movement_costs(w,v)<>0 OR finance.capture_movement_costs(w,sv)<>0 THEN RAISE EXCEPTION 'FAIL exact tracked cost retry'; END IF;
 SELECT l.movement_id INTO STRICT late_sale FROM inventory.stock_ledger l WHERE l.variant_id=v AND l.lot_id=late AND l.quantity_delta=-2;
 IF (SELECT count(*) FROM finance.fifo_cost_allocations fa WHERE fa.outgoing_movement_id=late_sale)<>2
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa WHERE fa.outgoing_movement_id=late_sale AND fa.receipt_movement_id=late_first AND fa.quantity=1 AND fa.cost=100)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa WHERE fa.outgoing_movement_id=late_sale AND fa.receipt_movement_id=late_second AND fa.quantity=1 AND fa.cost=120)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN inventory.stock_ledger l ON l.tenant_id=fa.tenant_id AND l.movement_id=fa.outgoing_movement_id WHERE l.lot_id=early AND fa.receipt_movement_id=early_source AND fa.quantity=2 AND fa.cost=400)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN inventory.stock_ledger l ON l.tenant_id=fa.tenant_id AND l.movement_id=fa.outgoing_movement_id WHERE l.serial_id=s1 AND fa.receipt_movement_id=serial_first AND fa.quantity=1 AND fa.cost=80)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN inventory.stock_ledger l ON l.tenant_id=fa.tenant_id AND l.movement_id=fa.outgoing_movement_id WHERE l.serial_id=s2 AND fa.receipt_movement_id=serial_second AND fa.quantity=1 AND fa.cost=190)
 OR (SELECT count(*) FROM finance.fifo_cost_allocations)<>5
 OR (SELECT sum(value_delta) FROM finance.movement_cost_facts)<>240
 OR (SELECT count(*) FROM finance.journal_entries)<>5
 THEN RAISE EXCEPTION 'FAIL exact lot and serial receipt lineage'; END IF;
 -- Financial posting of traced sales remains pending, and no transfer may be costed yet.
 IF NOT EXISTS(SELECT 1 FROM finance.tenant_inventory_cost_issues() i WHERE i.variant_id=v AND i.issue_code='sale_cogs_missing')
 THEN RAISE EXCEPTION 'FAIL pending financial readiness hidden'; END IF;
 PERFORM inventory.transfer_allocated('tracked-cost-transfer',w,dst,'Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',late,'quantity',1)));
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL unsupported traced transfer capture'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT count(*) FROM finance.movement_cost_facts)<>9 THEN RAISE EXCEPTION 'FAIL partial unsupported capture'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.configured_inventory_preview('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unauthorized preview'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) THEN RAISE EXCEPTION 'FAIL tracked cost tenant isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS shared traced receipt and sale valuation, lot FIFO restricted layers, serial exact source, retries and fail closed

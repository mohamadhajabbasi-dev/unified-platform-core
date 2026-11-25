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
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000005','92000000-0000-0000-0000-000000000001','late-trace','Late trace policy');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000004';
 late_v uuid:='93000000-0000-0000-0000-000000000005';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
 lot uuid; serial uuid; late_lot uuid; supplier uuid; po uuid; rid uuid; mid uuid;
BEGIN
 -- Ordinary policy cannot be converted to a tracked policy, even with no history.
 BEGIN
  PERFORM finance.configure_valuation_preview(v,'fifo','IRR');
  BEGIN PERFORM inventory.configure_tracking(v,'lot',true); RAISE EXCEPTION 'FAIL tracking after ordinary policy'; EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE EXCEPTION USING ERRCODE='Z0005',MESSAGE='Rollback ordinary policy fixture';
 EXCEPTION WHEN SQLSTATE 'Z0005' THEN NULL;
 END;
 BEGIN PERFORM finance.configure_valuation_preview(v,'lot_fifo','IRR'); RAISE EXCEPTION 'FAIL tracked method before tracking'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 BEGIN PERFORM finance.configure_valuation_preview(v,'fifo','IRR'); RAISE EXCEPTION 'FAIL ordinary FIFO for lot'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview(v,'serial_specific','IRR'); RAISE EXCEPTION 'FAIL serial method for lot'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview(sv,'lot_fifo','IRR'); RAISE EXCEPTION 'FAIL lot method for serial'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview(sv,'moving_average','IRR'); RAISE EXCEPTION 'FAIL ordinary average for serial'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF finance.configure_valuation_preview(v,'lot_fifo','IRR')<>v OR finance.configure_valuation_preview(sv,'serial_specific','IRR')<>sv
 THEN RAISE EXCEPTION 'FAIL tracked enrollment'; END IF;
 IF finance.configure_valuation_preview(v,'lot_fifo','IRR')<>v OR inventory.configure_tracking(v,'lot',true)<>v
 OR finance.configure_valuation_preview(sv,'serial_specific','IRR')<>sv OR inventory.configure_tracking(sv,'serial',false)<>sv
 THEN RAISE EXCEPTION 'FAIL exact tracked retry'; END IF;
 BEGIN PERFORM finance.configure_valuation_preview(v,'fifo','IRR'); RAISE EXCEPTION 'FAIL immutable tracked method'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview(sv,'serial_specific','USD'); RAISE EXCEPTION 'FAIL immutable tracked currency'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN UPDATE finance.valuation_policies SET method='fifo'; RAISE EXCEPTION 'FAIL direct policy update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM inventory.configure_tracking(late_v,'lot',false);
 late_lot:=inventory.register_lot(late_v,'LATE',d-1,NULL);
 PERFORM inventory.adjust_traced(w,late_v,late_lot,NULL,1,'late-policy','Synthetic');
 BEGIN PERFORM finance.configure_valuation_preview(late_v,'lot_fifo','IRR'); RAISE EXCEPTION 'FAIL tracked policy after stock'; EXCEPTION WHEN check_violation THEN NULL; END;
 lot:=inventory.register_lot(v,'LOT',d-1,d+10);
 serial:=inventory.register_serial(sv,'SERIAL');
 supplier:=procurement.register_counterparty('tracked-policy-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('tracked-policy-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'unit_cost',100),jsonb_build_object('variant_id',sv,'quantity',1,'unit_cost',200)));
 rid:=procurement.receive_purchase_allocated(po,'tracked-policy-receipt','Synthetic',jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',lot,'quantity',2),jsonb_build_object('variant_id',sv,'serial_id',serial,'quantity',1)));
 IF finance.configure_valuation_preview(v,'lot_fifo','IRR')<>v OR finance.configure_valuation_preview(sv,'serial_specific','IRR')<>sv
 THEN RAISE EXCEPTION 'FAIL policy retry after receipt'; END IF;
 IF (SELECT count(*) FROM finance.valuation_policies WHERE (variant_id=v AND method='lot_fifo') OR (variant_id=sv AND method='serial_specific'))<>2
 THEN RAISE EXCEPTION 'FAIL canonical policy rows'; END IF;
 -- 0047 supersedes the earlier blanket engine block: unconfirmed preview is read-only,
 -- while capture still requires the supplier invoice.
 IF NOT EXISTS(SELECT 1 FROM finance.configured_inventory_preview(w,v) p WHERE p.on_hand=2 AND p.remaining_value=200 AND NOT p.all_receipts_invoiced)
 THEN RAISE EXCEPTION 'FAIL unconfirmed tracked preview'; END IF;
 BEGIN PERFORM finance.capture_movement_costs(w,sv); RAISE EXCEPTION 'FAIL unconfirmed tracked capture'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) OR EXISTS(SELECT 1 FROM finance.journal_entries)
 THEN RAISE EXCEPTION 'FAIL policy wrote financial facts'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.tenant_inventory_cost_issues() i WHERE i.variant_id=v AND i.issue_code='unsupported_movement')
 OR NOT EXISTS(SELECT 1 FROM finance.tenant_inventory_cost_issues() i WHERE i.variant_id=late_v AND i.issue_code='valuation_policy_missing')
 THEN RAISE EXCEPTION 'FAIL pending tracked financial readiness hidden'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.configure_valuation_preview('93000000-0000-0000-0000-000000000001','lot_fifo','IRR'); RAISE EXCEPTION 'FAIL unauthorized policy'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.valuation_policies) THEN RAISE EXCEPTION 'FAIL unauthorized policy visibility'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.valuation_policies) THEN RAISE EXCEPTION 'FAIL cross tenant policy visibility'; END IF;
 BEGIN PERFORM finance.configure_valuation_preview('93000000-0000-0000-0000-000000000001','lot_fifo','IRR'); RAISE EXCEPTION 'FAIL cross tenant enrollment'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS explicit tracked valuation enrollment, compatibility, immutable retry, unconfirmed receipt guard and tenant isolation

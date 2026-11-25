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
 l1 uuid; l2 uuid; s1 uuid; s2 uuid; supplier uuid; po uuid; rid uuid; tid uuid; oid uuid; ret uuid; inv uuid;
 alloc jsonb; mid uuid; x record;
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 l1:=inventory.register_lot(v,'L1',d-1,d+10); l2:=inventory.register_lot(v,'L2',d-2,d+20);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 supplier:=procurement.register_counterparty('trace-evidence-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('trace-evidence-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5,'unit_cost',100),jsonb_build_object('variant_id',sv,'quantity',2,'unit_cost',200)));
 alloc:=jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',2),jsonb_build_object('variant_id',v,'lot_id',l2,'quantity',3),
 jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1),jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1));
 rid:=procurement.receive_purchase_allocated(po,'trace-evidence-receipt','Synthetic',alloc);
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.evidence_kind='receipt' AND e.receipt_id=rid AND e.invoice_id IS NULL)<>4
 OR (SELECT sum(e.receipt_agreed_cost) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e)<>900
 THEN RAISE EXCEPTION 'FAIL split receipt evidence'; END IF;
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 PERFORM finance.record_supplier_invoice(po,'TRACE-EVIDENCE',d,d+7,900,'IRR',digest,asset,ap);
 SELECT invoice_id INTO STRICT inv FROM finance.supplier_invoices WHERE purchase_id=po;
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.invoice_id=inv AND e.receipt_currency='IRR')<>4
 OR (SELECT count(*) FROM finance.journal_entries)<>1
 THEN RAISE EXCEPTION 'FAIL invoice evidence'; END IF;
 tid:=inventory.transfer_allocated('trace-evidence-transfer',w,dst,'Synthetic',alloc);
 IF (SELECT count(*) FROM inventory.transfer_lines WHERE transfer_id=tid)<>4
 OR (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.transfer_id=tid AND e.evidence_kind IN ('transfer_in','transfer_out') AND e.related_movement_id IS NOT NULL)<>8
 THEN RAISE EXCEPTION 'FAIL multiline transfer evidence'; END IF;
 oid:=sales.create_checkout('trace-evidence-sale',c,dst,pl,'in_person',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'expected_unit_price',1000),jsonb_build_object('variant_id',sv,'quantity',2,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','trace-evidence-payment',5000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.order_id=oid AND e.evidence_kind='sale' AND e.allocation_id IS NOT NULL)<>4
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.order_id=oid AND e.lot_id=l1 AND e.quantity_delta=-2)
 THEN RAISE EXCEPTION 'FAIL sale allocation evidence'; END IF;
 SELECT jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity)) INTO alloc
 FROM sales.order_items i JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id) WHERE i.order_id=oid;
 ret:=sales.receive_full_return_allocated(oid,'trace-evidence-return','Inspected sellable',alloc);
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.return_id=ret AND e.evidence_kind='return' AND e.order_id=oid AND e.related_movement_id IS NOT NULL AND e.allocation_id IS NOT NULL)<>4
 THEN RAISE EXCEPTION 'FAIL exact return evidence'; END IF;
 FOR x IN SELECT e.* FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.return_id=ret LOOP
 IF NOT EXISTS(SELECT 1 FROM finance.tracked_movement_evidence(x.related_movement_id) orig WHERE orig.evidence_kind='sale' AND orig.allocation_id=x.allocation_id AND orig.lot_id IS NOT DISTINCT FROM x.lot_id AND orig.serial_id IS NOT DISTINCT FROM x.serial_id AND orig.quantity_delta=-x.quantity_delta)
 THEN RAISE EXCEPTION 'FAIL exact original return match'; END IF;
 END LOOP;
 mid:=inventory.adjust_traced(dst,v,l2,NULL,1,'unsupported-evidence','Synthetic adjustment');
 BEGIN PERFORM finance.tracked_movement_evidence(mid); RAISE EXCEPTION 'FAIL unsupported evidence accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.tracked_movement_evidence(gen_random_uuid()); RAISE EXCEPTION 'FAIL missing movement accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) OR (SELECT count(*) FROM finance.journal_entries)<>1
 THEN RAISE EXCEPTION 'FAIL evidence wrote valuation facts'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.tracked_movement_evidence(gen_random_uuid()); RAISE EXCEPTION 'FAIL unauthorized evidence'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Use a real foreign movement ID without granting cross-tenant table access.
SELECT movement_id AS foreign_mid FROM inventory.stock_ledger WHERE tenant_id='90000000-0000-0000-0000-000000000001' LIMIT 1 \gset
SET SESSION AUTHORIZATION upc_inv_b;
SELECT set_config('upc.test_foreign_mid', :'foreign_mid',true);
DO $$ BEGIN
 BEGIN PERFORM finance.tracked_movement_evidence(current_setting('upc.test_foreign_mid')::uuid); RAISE EXCEPTION 'FAIL cross tenant evidence'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS tracked movement evidence: split receipts, invoice, multiline transfer, exact sale and return, unsupported and tenant gates

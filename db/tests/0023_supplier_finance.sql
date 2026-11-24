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
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); cash uuid:=gen_random_uuid(); other uuid:=gen_random_uuid();
 s uuid; po uuid; po2 uuid; iid uuid; sid uuid; per uuid; now_at timestamptz; d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex'); ln jsonb;
BEGIN
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Supplier payable','liability','IRR'),(t,cash,'cash','Cash','asset','IRR'),(t,other,'other','Other','liability','IRR');
 per:=finance.open_period('Synthetic period',d,d+30);
 s:=procurement.register_counterparty('supplier-finance',NULL,'Synthetic');
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5,'unit_cost',400));
 po:=procurement.issue_purchase('invoice-po',s,w,'IRR',ln);
 BEGIN PERFORM finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,asset,ap); RAISE EXCEPTION 'FAIL invoice before receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM procurement.receive_purchase(po,'invoice-receipt','delivery');
 IF NOT EXISTS(SELECT 1 FROM finance.receipt_cost_basis WHERE purchase_id=po AND quantity=5 AND agreed_cost=2000 AND unit_cost=400 AND invoice_id IS NULL AND cost_status='agreed_uninvoiced')
 THEN RAISE EXCEPTION 'FAIL uninvoiced receipt cost basis'; END IF;
 IF EXISTS(SELECT 1 FROM finance.supplier_invoices) OR EXISTS(SELECT 1 FROM finance.journal_entries) THEN RAISE EXCEPTION 'FAIL receipt created liability'; END IF;
 BEGIN PERFORM finance.record_supplier_invoice(po,'INV-1',d,d+7,1999,'IRR',digest,asset,ap); RAISE EXCEPTION 'FAIL wrong amount'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'USD',digest,asset,ap); RAISE EXCEPTION 'FAIL wrong currency'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,ap,asset); RAISE EXCEPTION 'FAIL wrong accounts'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 iid:=finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,asset,ap);
 IF NOT EXISTS(SELECT 1 FROM finance.receipt_cost_basis WHERE purchase_id=po AND agreed_cost=2000 AND invoice_id=iid AND cost_status='invoiced_exact_cost')
 THEN RAISE EXCEPTION 'FAIL invoiced receipt cost basis'; END IF;
 IF finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,asset,ap)<>iid THEN RAISE EXCEPTION 'FAIL invoice retry'; END IF;
 BEGIN PERFORM finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,asset,other); RAISE EXCEPTION 'FAIL invoice account conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM finance.supplier_payables WHERE invoice_id=iid AND outstanding=2000 AND state='unpaid') THEN RAISE EXCEPTION 'FAIL initial payable'; END IF;
 now_at:=clock_timestamp();
 BEGIN PERFORM finance.record_supplier_settlement(iid,'bank','synthetic-bank','BAD-ASSET',1,'IRR',now_at,digest,asset); RAISE EXCEPTION 'FAIL inventory as cash'; EXCEPTION WHEN check_violation THEN NULL; END;
 sid:=finance.record_supplier_settlement(iid,'bank','synthetic-bank','PAY-1',800,'IRR',now_at,digest,cash);
 IF finance.record_supplier_settlement(iid,'bank','synthetic-bank','PAY-1',800,'IRR',now_at,digest,cash)<>sid THEN RAISE EXCEPTION 'FAIL settlement retry'; END IF;
 BEGIN PERFORM finance.record_supplier_settlement(iid,'bank','synthetic-bank','PAY-1',801,'IRR',now_at,digest,cash); RAISE EXCEPTION 'FAIL settlement conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM finance.record_supplier_settlement(iid,'bank','synthetic-bank','PAY-2',1201,'IRR',now_at,digest,cash); RAISE EXCEPTION 'FAIL overpayment'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM finance.supplier_payables WHERE invoice_id=iid AND outstanding=1200 AND state='partial') THEN RAISE EXCEPTION 'FAIL partial payable'; END IF;
 PERFORM finance.record_supplier_settlement(iid,'bank','synthetic-bank','PAY-2',1200,'IRR',now_at,digest,cash);
 IF NOT EXISTS(SELECT 1 FROM finance.supplier_payables WHERE invoice_id=iid AND outstanding=0 AND state='settled')
 OR (SELECT count(*) FROM finance.journal_entries)<>3 OR (SELECT count(*) FROM finance.journal_lines)<>6
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=ap)<>0
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>2000
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=cash)<>-2000
 OR (SELECT count(*) FROM inventory.stock_ledger)<>1 THEN RAISE EXCEPTION 'FAIL canonical journal or stock'; END IF;
 po2:=procurement.issue_purchase('invoice-po-2',s,w,'IRR',ln);
 PERFORM procurement.receive_purchase(po2,'invoice-receipt-2','delivery2');
 BEGIN PERFORM finance.record_supplier_invoice(po2,'INV-1',d,d+7,2000,'IRR',digest,asset,ap); RAISE EXCEPTION 'FAIL duplicate supplier invoice ref'; EXCEPTION WHEN unique_violation THEN NULL; END;
 DECLARE second_invoice uuid; BEGIN
 second_invoice:=finance.record_supplier_invoice(po2,'INV-2',d,d+7,2000,'IRR',digest,asset,ap);
 PERFORM finance.close_period(per);
 BEGIN PERFORM finance.record_supplier_settlement(second_invoice,'bank','synthetic-bank','CLOSED',1,'IRR',now_at,digest,cash); RAISE EXCEPTION 'FAIL closed period settlement'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM finance.supplier_payables WHERE invoice_id=second_invoice AND outstanding=2000) THEN RAISE EXCEPTION 'FAIL closed settlement rollback'; END IF;
 END;
 -- Third purchase remains uninvoiced to test closed-period invoice rollback.
 po2:=procurement.issue_purchase('invoice-po-3',s,w,'IRR',ln);
 PERFORM procurement.receive_purchase(po2,'invoice-receipt-3','delivery3');
 BEGIN PERFORM finance.record_supplier_invoice(po2,'INV-3',d,d+7,2000,'IRR',digest,asset,ap); RAISE EXCEPTION 'FAIL closed period'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF (SELECT count(*) FROM finance.supplier_invoices)<>2 OR (SELECT count(*) FROM finance.supplier_settlements)<>2 THEN RAISE EXCEPTION 'FAIL atomic failure'; END IF;
 IF finance.record_supplier_invoice(po,'INV-1',d,d+7,2000,'IRR',digest,asset,ap)<>iid THEN RAISE EXCEPTION 'FAIL closed period retry'; END IF;
 BEGIN UPDATE finance.supplier_invoices SET amount=1; RAISE EXCEPTION 'FAIL invoice mutation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET CONSTRAINTS ALL IMMEDIATE;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.supplier_payables) OR EXISTS(SELECT 1 FROM finance.supplier_settlements) OR EXISTS(SELECT 1 FROM finance.receipt_cost_basis) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF;
 BEGIN PERFORM finance.record_supplier_invoice(gen_random_uuid(),'forbidden',current_date,current_date,1,'IRR',decode(repeat('ab',32),'hex'),gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'FAIL verifier capability'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS supplier finance: received purchase match, verified invoice and partial settlements, no overpayment, balanced journal, period gate, idempotency and tenant isolation

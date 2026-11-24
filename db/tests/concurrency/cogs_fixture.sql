\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_cogs_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_cogs_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_cogs_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_cogs_a,upc_cogs_b,upc_cogs_reader;
GRANT upc_checkout_offline TO upc_cogs_a,upc_cogs_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('b6000000-0000-0000-0000-000000000001','cogs-race-a','Synthetic A'),
 ('b6000000-0000-0000-0000-000000000002','cogs-race-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b6100000-0000-0000-0000-000000000001','test','cogs-race-a'),
 ('b6100000-0000-0000-0000-000000000002','test','cogs-race-b'),
 ('b6100000-0000-0000-0000-000000000003','test','cogs-race-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6100000-0000-0000-0000-000000000001'),
 ('b6000000-0000-0000-0000-000000000002','b6100000-0000-0000-0000-000000000002'),
 ('b6000000-0000-0000-0000-000000000001','b6100000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_cogs_a','b6000000-0000-0000-0000-000000000001','b6100000-0000-0000-0000-000000000001'),
 ('upc_cogs_b','b6000000-0000-0000-0000-000000000002','b6100000-0000-0000-0000-000000000002'),
 ('upc_cogs_reader','b6000000-0000-0000-0000-000000000001','b6100000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('b6000000-0000-0000-0000-000000000001','cogs-race-editor'),
 ('b6000000-0000-0000-0000-000000000002','cogs-race-editor'),
 ('b6000000-0000-0000-0000-000000000001','cogs-race-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='cogs-race-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE role_key='cogs-race-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='b6100000-0000-0000-0000-000000000003' AND r.role_key='cogs-race-reader')
 OR (m.user_id<>'b6100000-0000-0000-0000-000000000003' AND r.role_key='cogs-race-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b6100000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('cogs-race-a','cogs-race-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6200000-0000-0000-0000-000000000001','A','physical'),
 ('b6000000-0000-0000-0000-000000000002','b6200000-0000-0000-0000-000000000002','B','physical'),
 ('b6000000-0000-0000-0000-000000000001','b6200000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6300000-0000-0000-0000-000000000001','b6200000-0000-0000-0000-000000000001','stock-a','A'),
 ('b6000000-0000-0000-0000-000000000002','b6300000-0000-0000-0000-000000000002','b6200000-0000-0000-0000-000000000002','stock-b','B'),
 ('b6000000-0000-0000-0000-000000000001','b6300000-0000-0000-0000-000000000003','b6200000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6400000-0000-0000-0000-000000000001','main','A'),
 ('b6000000-0000-0000-0000-000000000002','b6400000-0000-0000-0000-000000000002','main','B');

GRANT upc_payment_recorder TO upc_cogs_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='cogs-race-editor' AND (p.permission_key LIKE 'sales.%' OR p.permission_key IN ('crm.read','catalog.read'));
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'sales.read' FROM iam.roles WHERE role_key='cogs-race-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b6100000-0000-0000-0000-000000000001','Synthetic sales test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('cogs-race-a','cogs-race-b') AND m.module_key IN ('sales','crm','catalog');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6500000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('b6000000-0000-0000-0000-000000000002','b6500000-0000-0000-0000-000000000002','Synthetic customer B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6200000-0000-0000-0000-000000000004','No stock','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6300000-0000-0000-0000-000000000004','b6200000-0000-0000-0000-000000000004','no-stock','No stock');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('b6000000-0000-0000-0000-000000000001','b6600000-0000-0000-0000-000000000001','original','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT 'b6000000-0000-0000-0000-000000000001',v.variant_id,'b6600000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='b6000000-0000-0000-0000-000000000001';

INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='cogs-race-editor' AND p.permission_key LIKE 'procurement.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'procurement.read' FROM iam.roles WHERE role_key='cogs-race-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b6100000-0000-0000-0000-000000000001','Synthetic procurement'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('cogs-race-a','cogs-race-b') AND m.module_key='procurement';
GRANT upc_supplier_document_verifier,upc_supplier_payment_verifier TO upc_cogs_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='cogs-race-editor' AND p.permission_key LIKE 'finance.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b6100000-0000-0000-0000-000000000001','Synthetic finance'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('cogs-race-a','cogs-race-b') AND m.module_key='finance';
SET SESSION AUTHORIZATION upc_cogs_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); w uuid:='b6400000-0000-0000-0000-000000000001'; v uuid:='b6300000-0000-0000-0000-000000000001';
 c uuid:='b6500000-0000-0000-0000-000000000001'; pl uuid:='b6600000-0000-0000-0000-000000000001';
 asset uuid:='b6700000-0000-0000-0000-000000000001'; ap uuid:='b6700000-0000-0000-0000-000000000002';
 expense uuid:='b6700000-0000-0000-0000-000000000003'; other_expense uuid:='b6700000-0000-0000-0000-000000000004';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 s uuid; po uuid; oid uuid;
BEGIN
 PERFORM finance.configure_valuation_preview(v,'fifo','IRR');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR'),
 (t,expense,'cogs','COGS','expense','IRR'),(t,other_expense,'other-cogs','Other expense','expense','IRR');
 PERFORM finance.open_period('Synthetic COGS race',d,d+30);
 s:=procurement.register_counterparty('cogs-race-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('cogs-race-po1',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'cogs-race-r1','delivery');
 PERFORM finance.record_supplier_invoice(po,'COGS-RACE-1',d,d+7,1000,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('cogs-race-po2',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',120)));
 PERFORM procurement.receive_purchase(po,'cogs-race-r2','delivery');
 PERFORM finance.record_supplier_invoice(po,'COGS-RACE-2',d,d+7,1200,'IRR',digest,asset,ap);
 oid:=sales.create_checkout('cogs-race-sale',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',12,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','cogs-race-payment',12000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
END $$;
RESET SESSION AUTHORIZATION;
COMMIT;

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_time_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_time_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_time_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_time_a,upc_time_b,upc_time_reader;
GRANT upc_checkout_offline TO upc_time_a,upc_time_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('e5500000-0000-0000-0000-000000000001','temporal-0055-a','Synthetic A'),
 ('e5500000-0000-0000-0000-000000000002','temporal-0055-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('e5510000-0000-0000-0000-000000000001','test','temporal-0055-a'),
 ('e5510000-0000-0000-0000-000000000002','test','temporal-0055-b'),
 ('e5510000-0000-0000-0000-000000000003','test','temporal-0055-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5510000-0000-0000-0000-000000000001'),
 ('e5500000-0000-0000-0000-000000000002','e5510000-0000-0000-0000-000000000002'),
 ('e5500000-0000-0000-0000-000000000001','e5510000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_time_a','e5500000-0000-0000-0000-000000000001','e5510000-0000-0000-0000-000000000001'),
 ('upc_time_b','e5500000-0000-0000-0000-000000000002','e5510000-0000-0000-0000-000000000002'),
 ('upc_time_reader','e5500000-0000-0000-0000-000000000001','e5510000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('e5500000-0000-0000-0000-000000000001','inventory-editor'),
 ('e5500000-0000-0000-0000-000000000002','inventory-editor'),
 ('e5500000-0000-0000-0000-000000000001','inventory-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='e5510000-0000-0000-0000-000000000003' AND r.role_key='inventory-reader')
 OR (m.user_id<>'e5510000-0000-0000-0000-000000000003' AND r.role_key='inventory-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'e5510000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('temporal-0055-a','temporal-0055-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5520000-0000-0000-0000-000000000001','A','physical'),
 ('e5500000-0000-0000-0000-000000000002','e5520000-0000-0000-0000-000000000002','B','physical'),
 ('e5500000-0000-0000-0000-000000000001','e5520000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5530000-0000-0000-0000-000000000001','e5520000-0000-0000-0000-000000000001','stock-a','A'),
 ('e5500000-0000-0000-0000-000000000002','e5530000-0000-0000-0000-000000000002','e5520000-0000-0000-0000-000000000002','stock-b','B'),
 ('e5500000-0000-0000-0000-000000000001','e5530000-0000-0000-0000-000000000003','e5520000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5540000-0000-0000-0000-000000000001','main','A'),
 ('e5500000-0000-0000-0000-000000000002','e5540000-0000-0000-0000-000000000002','main','B');

GRANT upc_payment_recorder TO upc_time_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND (p.permission_key LIKE 'sales.%' OR p.permission_key IN ('crm.read','catalog.read'));
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'sales.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'e5510000-0000-0000-0000-000000000001','Synthetic sales test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('temporal-0055-a','temporal-0055-b') AND m.module_key IN ('sales','crm','catalog');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5550000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('e5500000-0000-0000-0000-000000000002','e5550000-0000-0000-0000-000000000002','Synthetic customer B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5520000-0000-0000-0000-000000000004','No stock','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5530000-0000-0000-0000-000000000004','e5520000-0000-0000-0000-000000000004','no-stock','No stock');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5560000-0000-0000-0000-000000000001','original','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT 'e5500000-0000-0000-0000-000000000001',v.variant_id,'e5560000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='e5500000-0000-0000-0000-000000000001';

INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'procurement.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'procurement.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'e5510000-0000-0000-0000-000000000001','Synthetic procurement'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('temporal-0055-a','temporal-0055-b') AND m.module_key='procurement';
GRANT upc_supplier_document_verifier,upc_supplier_payment_verifier TO upc_time_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'finance.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'e5510000-0000-0000-0000-000000000001','Synthetic finance'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('temporal-0055-a','temporal-0055-b') AND m.module_key='finance';
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('e5500000-0000-0000-0000-000000000001','e5540000-0000-0000-0000-000000000003','second','Second warehouse');

-- Fresh isolated synthetic tenant, run LAST after other COGS tests.
-- Project historical receipt and posting dates only in fixture triggers.
-- Cost capture uses real current clock. Remove projection before commit.
CREATE FUNCTION public.upc_test_late_history() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE base timestamptz:=(((clock_timestamp() AT TIME ZONE 'UTC')::date-5)::timestamp AT TIME ZONE 'UTC');
BEGIN
 IF current_database()<>'upc_greenfield_test' OR NEW.tenant_id<>'e5500000-0000-0000-0000-000000000001'::uuid
 THEN RAISE EXCEPTION 'Unexpected late-cost fixture scope'; END IF;
 CASE TG_TABLE_NAME
 WHEN 'counterparties' THEN NEW.created_at:=base;
 WHEN 'purchase_orders' THEN NEW.issued_at:=base+interval '1 minute';
 WHEN 'goods_receipts' THEN NEW.received_at:=base+interval '2 minutes';
 WHEN 'stock_ledger' THEN NEW.recorded_at:=base+interval '3 minutes';
 WHEN 'supplier_invoices' THEN NEW.recorded_at:=base+interval '4 minutes';
 WHEN 'journal_entries' THEN
  NEW.posted_at:=base+interval '5 minutes';
  SELECT period_id INTO STRICT NEW.period_id FROM finance.fiscal_periods
   WHERE tenant_id=NEW.tenant_id AND period_name='Synthetic late cutoff' AND dates @> (NEW.posted_at AT TIME ZONE 'UTC')::date AND closed_at IS NULL;
 ELSE RAISE EXCEPTION 'Unexpected late-cost fixture relation';
 END CASE;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.upc_test_late_history() FROM PUBLIC;
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON procurement.counterparties FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON procurement.purchase_orders FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON procurement.goods_receipts FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON inventory.stock_ledger FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON finance.supplier_invoices FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
CREATE TRIGGER zz_upc_test_late_history BEFORE INSERT ON finance.journal_entries FOR EACH ROW EXECUTE FUNCTION public.upc_test_late_history();
SET SESSION AUTHORIZATION upc_time_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); w uuid:='e5540000-0000-0000-0000-000000000001'; v uuid:='e5530000-0000-0000-0000-000000000001';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; a uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); supplier uuid; po uuid;
BEGIN
 PERFORM finance.open_period('Synthetic late cutoff',d-10,d-2);
 PERFORM finance.open_period('Synthetic late current',d,d+2);
 PERFORM finance.configure_valuation_preview(v,'fifo','IRR');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,a,'late-inventory','Synthetic inventory','asset','IRR'),(t,p,'late-payable','Synthetic payable','liability','IRR');
 supplier:=procurement.register_counterparty('late-cost-supplier',NULL,'Synthetic supplier');
 po:=procurement.issue_purchase('late-cost-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'late-cost-receipt','Synthetic receipt');
 PERFORM finance.record_supplier_invoice(po,'LATE-COST-0055',d-5,d+2,200,'IRR',decode(repeat('ab',32),'hex'),a,p);
 IF finance.capture_movement_costs(w,v)<>1 THEN RAISE EXCEPTION 'FAIL late-cost actual capture'; END IF;
 PERFORM finance.assert_tenant_inventory_cost_ready();
END $$;
RESET SESSION AUTHORIZATION;
DROP TRIGGER zz_upc_test_late_history ON procurement.counterparties;
DROP TRIGGER zz_upc_test_late_history ON procurement.purchase_orders;
DROP TRIGGER zz_upc_test_late_history ON procurement.goods_receipts;
DROP TRIGGER zz_upc_test_late_history ON inventory.stock_ledger;
DROP TRIGGER zz_upc_test_late_history ON finance.supplier_invoices;
DROP TRIGGER zz_upc_test_late_history ON finance.journal_entries;
DROP FUNCTION public.upc_test_late_history();
COMMIT;
-- Independent actual close transaction: no prior tenant mutation lock.
SET SESSION AUTHORIZATION upc_time_a;
DO $$
DECLARE p uuid; msg text;
BEGIN
 SELECT period_id INTO STRICT p FROM finance.fiscal_periods WHERE period_name='Synthetic late cutoff';
 IF (SELECT count(*) FROM finance.inventory_period_close_issues(p))<>1
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(p) i WHERE i.issue_code='inventory_cost_captured_after_period' AND i.currency='IRR' AND i.movement_id IS NOT NULL)
 THEN RAISE EXCEPTION 'FAIL isolated late evidence'; END IF;
 BEGIN PERFORM finance.close_period(p); RAISE EXCEPTION 'FAIL committed late-cost close accepted';
 EXCEPTION WHEN check_violation THEN
  GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT;
  IF msg NOT LIKE '%inventory_cost_captured_after_period%' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM finance.fiscal_periods WHERE period_id=p AND closed_at IS NOT NULL)
 OR (SELECT count(*) FROM inventory.stock_ledger)<>1
 OR (SELECT count(*) FROM finance.movement_cost_facts)<>1
 OR (SELECT count(*) FROM finance.journal_entries)<>1
 THEN RAISE EXCEPTION 'FAIL late close altered canonical history'; END IF;
 RAISE NOTICE 'TEMPORAL_GUARD actual close rejected isolated committed late cost';
END $$;
RESET SESSION AUTHORIZATION;

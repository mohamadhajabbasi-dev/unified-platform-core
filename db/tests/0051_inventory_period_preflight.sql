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
-- 0053: rollback-only fixture privilege for simulating a closed posting period.
-- Real close permission and cutoff are tested separately; no migration grants this.
GRANT UPDATE(closed_at,closed_by) ON finance.fiscal_periods TO upc_inv_a;
CREATE POLICY test_closed_period_fixture ON finance.fiscal_periods FOR UPDATE TO upc_inv_a
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); w uuid:='94000000-0000-0000-0000-000000000001';
 v uuid:='93000000-0000-0000-0000-000000000001'; v2 uuid:='93000000-0000-0000-0000-000000000004';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; old_period uuid; current_period uuid; future_period uuid;
 supplier uuid; po uuid; asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid();
 digest bytea:=decode(repeat('ab',32),'hex'); n bigint;
BEGIN
 old_period:=finance.open_period('Preflight ended',d-10,d);
 current_period:=finance.open_period('Preflight current',d,d+1);
 future_period:=finance.open_period('Preflight future',d+1,d+10);
 IF EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(old_period)) THEN RAISE EXCEPTION 'FAIL empty ended preflight'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='period_end_not_reached')
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(future_period) i WHERE i.issue_code='period_end_not_reached')
 THEN RAISE EXCEPTION 'FAIL early preflight'; END IF;
 IF EXISTS(SELECT 1 FROM finance.fiscal_periods fp WHERE fp.closed_at IS NOT NULL) THEN RAISE EXCEPTION 'FAIL preflight mutated periods'; END IF;
 BEGIN
  PERFORM inventory.adjust_stock(w,v2,1,'preflight-unknown','Synthetic adjustment');
  IF NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='valuation_policy_missing' AND i.variant_id=v2)
  OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(old_period) i WHERE i.issue_code='inventory_movements_after_period')
  THEN RAISE EXCEPTION 'FAIL unknown movement omitted'; END IF;
  RAISE EXCEPTION USING ERRCODE='Z0051',MESSAGE='Rollback synthetic unconfigured adjustment';
 EXCEPTION WHEN SQLSTATE 'Z0051' THEN NULL;
 END;
 PERFORM finance.configure_valuation_preview(v,'fifo','IRR');
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR');
 supplier:=procurement.register_counterparty('preflight-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('preflight-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'preflight-receipt','Synthetic');
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='purchase_invoice_missing' AND i.variant_id=v)
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='cost_not_captured' AND i.variant_id=v)
 THEN RAISE EXCEPTION 'FAIL unconfirmed receipt diagnostics'; END IF;
 PERFORM finance.record_supplier_invoice(po,'PREFLIGHT-INVOICE',d,d+1,200,'IRR',digest,asset,ap);
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(old_period) i WHERE i.issue_code='inventory_journals_after_period')
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='tenant_inventory_value_mismatch' AND i.currency='IRR')
 THEN RAISE EXCEPTION 'FAIL invoice/capture difference'; END IF;
 n:=finance.capture_movement_costs(w,v);
 IF n<>1 THEN RAISE EXCEPTION 'FAIL preflight fixture capture'; END IF;
 PERFORM finance.assert_tenant_inventory_cost_ready();
 IF (SELECT count(*) FROM finance.inventory_period_close_issues(current_period))<>1
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(current_period) i WHERE i.issue_code='period_end_not_reached')
 OR (SELECT count(*) FROM finance.inventory_period_close_issues(old_period))<>2
 THEN RAISE EXCEPTION 'FAIL cumulative readiness falsely certified historical period'; END IF;
 -- Test already-closed status without claiming preflight enforces closure.
 BEGIN PERFORM finance.close_period(old_period); RAISE EXCEPTION 'FAIL unsafe actual period close'; EXCEPTION WHEN invalid_transaction_state THEN NULL; END;
 -- Simulate closed state only inside this rolled-back test fixture.
 UPDATE finance.fiscal_periods SET closed_at=clock_timestamp(),closed_by=iam.current_user_id()
 WHERE period_id=old_period;
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_period_close_issues(old_period) i WHERE i.issue_code='period_already_closed')
 THEN RAISE EXCEPTION 'FAIL closed period status'; END IF;
 IF (SELECT count(*) FROM finance.fiscal_periods fp WHERE fp.closed_at IS NOT NULL)<>1
 OR (SELECT count(*) FROM finance.journal_entries)<>1
 OR (SELECT count(*) FROM finance.movement_cost_facts)<>1
 THEN RAISE EXCEPTION 'FAIL preflight side effects'; END IF;
 BEGIN PERFORM finance.inventory_period_close_issues(NULL); RAISE EXCEPTION 'FAIL null period'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM finance.inventory_period_close_issues(gen_random_uuid()); RAISE EXCEPTION 'FAIL nonexistent period'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SELECT period_id AS foreign_period FROM finance.fiscal_periods WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND period_name='Preflight current' \gset
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.inventory_period_close_issues(gen_random_uuid()); RAISE EXCEPTION 'FAIL unauthorized preflight'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
SELECT set_config('upc.test_foreign_period', :'foreign_period',true);
DO $$ BEGIN
 BEGIN PERFORM finance.inventory_period_close_issues(current_setting('upc.test_foreign_period')::uuid); RAISE EXCEPTION 'FAIL foreign preflight'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS conservative inventory period preflight, UTC cutoff, missing evidence, currency mismatch, read-only and tenant isolation

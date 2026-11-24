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
 ('90000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','retail','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT '90000000-0000-0000-0000-000000000001',v.variant_id,'96000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='90000000-0000-0000-0000-000000000001';

GRANT upc_refund_recorder TO upc_inv_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND p.permission_key LIKE 'finance.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'finance.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic finance test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='finance';
INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 ('90000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000001','clearing','Clearing','asset','IRR'),
 ('90000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000002','advance','Customer advances','liability','IRR'),
 ('90000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000003','usd','USD clearing','asset','USD'),
 ('90000000-0000-0000-0000-000000000002','97000000-0000-0000-0000-000000000004','clearing','Foreign tenant','asset','IRR');
INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 ('90000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000005','revenue','Sales revenue','revenue','IRR');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 c uuid:='95000000-0000-0000-0000-000000000001'; l uuid:='96000000-0000-0000-0000-000000000001';
 ca uuid:='97000000-0000-0000-0000-000000000001'; adv uuid:='97000000-0000-0000-0000-000000000002';
 rev uuid:='97000000-0000-0000-0000-000000000005'; d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date;
 p uuid; oid uuid; pid uuid; rid uuid; je uuid; rec uuid; lines jsonb;
BEGIN
 lines:=jsonb_build_array(jsonb_build_object('account_id',ca,'amount',100),jsonb_build_object('account_id',adv,'amount',-100));
 BEGIN
  PERFORM finance.post_manual('no-period','IRR','Denied',lines); RAISE EXCEPTION 'FAIL missing period';
 EXCEPTION WHEN check_violation THEN NULL; END;
 p:=finance.open_period('Current',d-1,d+2);
 IF finance.open_period('Current',d-1,d+2)<>p THEN RAISE EXCEPTION 'FAIL period retry'; END IF;
 BEGIN
  PERFORM finance.open_period('Overlap',d,d+3); RAISE EXCEPTION 'FAIL period overlap';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 PERFORM inventory.adjust_stock(w,v,10,'recognition-receipt','Receipt');
 oid:=sales.create_checkout('recognition-order',c,w,l,'web',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2,'expected_unit_price',1000)));
 pid:=sales.record_capture(oid,'synthetic','acct','recognition-pay',2000,'IRR',clock_timestamp());
 je:=finance.post_capture(pid,ca,adv);
 BEGIN
  PERFORM finance.recognize_order(oid,rev); RAISE EXCEPTION 'FAIL premature recognition';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM sales.fulfill_order(oid);
 rec:=finance.recognize_order(oid,rev);
 IF finance.recognize_order(oid,rev)<>rec THEN RAISE EXCEPTION 'FAIL recognition retry'; END IF;
 IF (SELECT net_debit FROM finance.trial_balance WHERE account_id=adv)<>0
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=rev)<>-2000 THEN RAISE EXCEPTION 'FAIL recognition balances'; END IF;
 PERFORM sales.receive_full_return(oid,'recognition-return','All inspected');
 rid:=sales.record_full_refund(pid,'recognition-refund',2000,'IRR',clock_timestamp());
 PERFORM finance.post_refund(rid);
 IF EXISTS(SELECT 1 FROM finance.trial_balance WHERE net_debit<>0) OR
 (SELECT count(*) FROM finance.journal_entries WHERE period_id=p)<>3 THEN RAISE EXCEPTION 'FAIL revenue reversal'; END IF;
 PERFORM finance.close_period(p);
 PERFORM finance.close_period(p);
 IF finance.post_capture(pid,ca,adv)<>je THEN RAISE EXCEPTION 'FAIL closed period retry'; END IF;
 BEGIN
  PERFORM finance.post_manual('closed','IRR','Denied',lines); RAISE EXCEPTION 'FAIL closed period posting';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET CONSTRAINTS ALL IMMEDIATE;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM finance.fiscal_periods) THEN RAISE EXCEPTION 'FAIL period leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM finance.fiscal_periods)<>1 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN
  PERFORM finance.close_period((SELECT period_id FROM finance.fiscal_periods LIMIT 1)); RAISE EXCEPTION 'FAIL unauthorized close';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS finance lifecycle: fiscal period gate, non-overlap, recognition after fulfillment, refund reversal, closed period and tenant isolation

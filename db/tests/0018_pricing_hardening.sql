\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_bill_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bill_staff LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bill_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bill_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver,upc_billing_recorder TO upc_bill_admin,upc_bill_staff,upc_bill_a;
GRANT upc_runtime TO upc_bill_a,upc_bill_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('b0000000-0000-0000-0000-000000000001','bill-a','Synthetic A'),('b0000000-0000-0000-0000-000000000002','bill-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b1000000-0000-0000-0000-000000000001','test','bill-admin'),('b1000000-0000-0000-0000-000000000002','test','bill-staff'),
 ('b1000000-0000-0000-0000-000000000003','test','bill-a'),('b1000000-0000-0000-0000-000000000004','test','bill-b');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_bill_admin','b1000000-0000-0000-0000-000000000001',true),('upc_bill_staff','b1000000-0000-0000-0000-000000000002',false);
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('b0000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003'),
 ('b0000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000004');
INSERT INTO iam.db_principals VALUES
 ('upc_bill_a','b0000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000003'),
 ('upc_bill_b','b0000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000004');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('b0000000-0000-0000-0000-000000000001','billing-reader'),('b0000000-0000-0000-0000-000000000002','billing-reader');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'platform.billing.read' FROM iam.roles WHERE role_key='billing-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id) WHERE r.role_key='billing-reader';
GRANT upc_web_collector TO upc_bill_a,upc_bill_b;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='billing-reader' AND p.permission_key LIKE 'web.analytics.%';
GRANT upc_app_collector TO upc_bill_a,upc_bill_b;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='billing-reader' AND p.permission_key LIKE 'app.%';
SET SESSION AUTHORIZATION upc_bill_admin;
DO $$
DECLARE ta uuid:='b0000000-0000-0000-0000-000000000001'; tb uuid:='b0000000-0000-0000-0000-000000000002';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; sa uuid; sb uuid; ia uuid; ib uuid;
BEGIN
 sa:=platform.create_subscription(ta,'both',d,d+30,'Synthetic both',1000,'IRR');
 sb:=platform.create_subscription(tb,'web-only',d,d+30,'Synthetic web',1000,'IRR');
 PERFORM platform.specify_purchased_module(ta,sa,'commerce');
 PERFORM platform.specify_purchased_module(ta,sa,'app.analytics');
 PERFORM platform.specify_purchased_module(tb,sb,'commerce');
 ia:=platform.issue_subscription_invoice(ta,sa,d+7);
 ib:=platform.issue_subscription_invoice(tb,sb,d+7);
 PERFORM platform.record_billing_payment(ta,ia,'synthetic','platform','both-paid',1000,'IRR',clock_timestamp());
 PERFORM platform.record_billing_payment(tb,ib,'synthetic','platform','web-paid',1000,'IRR',clock_timestamp());
 PERFORM platform.record_module_decision(ta,'commerce',true,NULL,'Synthetic approval');
 PERFORM platform.record_module_decision(tb,'commerce',true,NULL,'Synthetic approval');
 PERFORM platform.record_module_decision(ta,'app.analytics',true,NULL,'Synthetic approval');
 PERFORM platform.record_module_decision(tb,'app.analytics',true,NULL,'Synthetic approval but no purchase');
END $$;
RESET SESSION AUTHORIZATION;

GRANT upc_checkout_web,upc_checkout_app,upc_price_customer_verifier TO upc_bill_a;
GRANT upc_checkout_app TO upc_bill_b;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='billing-reader' AND (p.permission_key LIKE 'catalog.%' OR p.permission_key LIKE 'inventory.%' OR p.permission_key LIKE 'sales.%' OR p.permission_key='crm.read');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b1000000-0000-0000-0000-000000000001','Synthetic sales'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('bill-a','bill-b') AND m.module_key IN ('catalog','inventory','sales','crm');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('b0000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-000000000001','Synthetic buyer');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('b0000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000001','A','physical'),
 ('b0000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000002','B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('b0000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000001','A','A'),
 ('b0000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000002','b6000000-0000-0000-0000-000000000002','B','B');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('b0000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001','main','Synthetic');
-- Bootstrap validation must work without mapped tenant.
INSERT INTO catalog.price_lists(tenant_id,list_key,currency,name) VALUES('b0000000-0000-0000-0000-000000000001','original','IRR','Original');
DO $$ BEGIN
 BEGIN INSERT INTO catalog.price_lists(tenant_id,list_key,currency,name) VALUES('b0000000-0000-0000-0000-000000000001','discounted','USD','Mismatch'); RAISE EXCEPTION 'FAIL bootstrap currency';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); v1 uuid:='b7000000-0000-0000-0000-000000000001'; v2 uuid:='b7000000-0000-0000-0000-000000000002';
 c uuid:='b5000000-0000-0000-0000-000000000001'; w uuid:='b8000000-0000-0000-0000-000000000001';
 orig uuid; disc uuid; coll uuid; oid uuid; oid2 uuid; dl timestamptz:=clock_timestamp()+interval '1 hour'; ln jsonb;
BEGIN
 PERFORM catalog.initialize_standard_prices('IRR');
 SELECT price_list_id INTO orig FROM catalog.price_lists WHERE list_key='original';
 SELECT price_list_id INTO disc FROM catalog.price_lists WHERE list_key='discounted';
 SELECT price_list_id INTO coll FROM catalog.price_lists WHERE list_key='colleague';
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES
 (t,v1,orig,1000,tstzrange('2020-01-01',NULL,'[)')),(t,v2,orig,2000,tstzrange('2020-01-01',NULL,'[)')),
 (t,v1,disc,900,tstzrange('2020-01-01',NULL,'[)')),(t,v2,disc,1800,tstzrange('2020-01-01','2020-02-01','[)')),
 (t,v1,coll,850,tstzrange('2020-01-01',NULL,'[)'));
 PERFORM catalog.decide_customer_price(c,'colleague',true,NULL,'Initial');
 PERFORM catalog.decide_customer_price(c,'colleague',true,clock_timestamp()+interval '0.5 seconds','Expiring');
 PERFORM pg_sleep(0.6);
 IF (SELECT amount FROM catalog.quote_price(v1,c,1,'web')) IS DISTINCT FROM 900::numeric
 OR (SELECT amount FROM catalog.quote_price(v2,c,1,'app')) IS DISTINCT FROM 2000::numeric THEN RAISE EXCEPTION 'FAIL expiry fallback'; END IF;
 BEGIN UPDATE catalog.price_entries SET valid_during=tstzrange('2020-01-01',clock_timestamp(),'[)') WHERE variant_id=v1 AND price_list_id=orig;
 RAISE EXCEPTION 'FAIL original shortening leaves discount'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM inventory.adjust_stock(w,v1,10,'price-hard-a','Synthetic'); PERFORM inventory.adjust_stock(w,v2,10,'price-hard-b','Synthetic');
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v1,'quantity',1,'expected_unit_price',900),jsonb_build_object('variant_id',v2,'quantity',1,'expected_unit_price',2000));
 BEGIN PERFORM sales.create_checkout('offline-spoof',c,w,orig,'in_person',dl,ln); RAISE EXCEPTION 'FAIL online role impersonates offline'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 oid:=sales.create_checkout('web-mixed',c,w,orig,'web',dl,ln);
 oid2:=sales.create_checkout('app-mixed',c,w,orig,'app',dl,ln);
 IF (SELECT count(*) FROM sales.order_items WHERE order_id IN (oid,oid2) AND price_kind_snapshot='discounted' AND unit_price=900)<>2
 OR (SELECT count(*) FROM sales.order_items WHERE order_id IN (oid,oid2) AND price_kind_snapshot='original' AND unit_price=2000)<>2
 OR (SELECT sum(total) FROM sales.order_totals WHERE order_id IN (oid,oid2)) IS DISTINCT FROM 5800::numeric THEN RAISE EXCEPTION 'FAIL mixed cart'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','app.analytics',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.quote_price('b7000000-0000-0000-0000-000000000001',NULL,1,'app')) THEN RAISE EXCEPTION 'FAIL revoked app quote'; END IF;
 BEGIN PERFORM sales.create_checkout('revoked-app','b5000000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000001',
 (SELECT price_list_id FROM catalog.price_lists WHERE list_key='original'),'app',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id','b7000000-0000-0000-0000-000000000001','quantity',1,'expected_unit_price',900)));
 RAISE EXCEPTION 'FAIL revoked app checkout'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS pricing hardening: bootstrap currency, expiry, trusted channel, mixed cart web/app, price dependency and revoked app

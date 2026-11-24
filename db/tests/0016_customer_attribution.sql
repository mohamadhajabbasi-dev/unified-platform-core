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

GRANT upc_attribution_verifier TO upc_bill_a,upc_bill_b;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='billing-reader' AND (p.permission_key LIKE 'crm.attribution.%' OR p.permission_key IN ('crm.consent.read','crm.consent.write','sales.read'));
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','crm',true,NULL,'Synthetic CRM');
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000002','crm',true,NULL,'Synthetic CRM');
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','sales',true,NULL,'Synthetic sales');
RESET SESSION AUTHORIZATION;
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('b0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','Synthetic A'),
 ('b0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000003','Synthetic A2'),
 ('b0000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO crm.customer_identifiers(tenant_id,customer_id,kind,issuer,normalized_value,verified_at) VALUES
 ('b0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','channel','synthetic','customer-a',clock_timestamp()),
 ('b0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000003','channel','synthetic','customer-a2',clock_timestamp());
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ DECLARE c uuid:='f0000000-0000-0000-0000-000000000001'; s uuid:='f1000000-0000-0000-0000-000000000001'; s2 uuid:='f1000000-0000-0000-0000-000000000002'; a uuid; BEGIN
 PERFORM web.start_session(s,true,false,'v1','organic','search',NULL,'first','home');
 BEGIN PERFORM crm.record_acquisition(c,'web',s,decode(repeat('a1',32),'hex')); RAISE EXCEPTION 'FAIL no consent'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 INSERT INTO crm.customer_consent_events(tenant_id,customer_id,purpose,granted,origin_channel,evidence_digest)
 VALUES(iam.current_tenant_id(),c,'analytics',true,'web',decode(repeat('c1',32),'hex')),
 (iam.current_tenant_id(),'f0000000-0000-0000-0000-000000000003','analytics',true,'web',decode(repeat('c3',32),'hex'));
 a:=crm.record_acquisition(c,'web',s,decode(repeat('a1',32),'hex'));
 IF crm.record_acquisition(c,'web',s,decode(repeat('a1',32),'hex'))<>a THEN RAISE EXCEPTION 'FAIL retry'; END IF;
 BEGIN PERFORM crm.record_acquisition('f0000000-0000-0000-0000-000000000003','web',s,decode(repeat('a3',32),'hex')); RAISE EXCEPTION 'FAIL session reassignment'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM crm.record_acquisition('f0000000-0000-0000-0000-000000000002','web',s,decode(repeat('a4',32),'hex')); RAISE EXCEPTION 'FAIL foreign customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 PERFORM web.start_session(s2,true,false,'v1','paid','ads',NULL,'last','home');
 PERFORM crm.record_acquisition(c,'web',s2,decode(repeat('a2',32),'hex'));
 PERFORM crm.record_acquisition(c,'in_person',NULL,decode(repeat('a5',32),'hex'));
 IF (SELECT count(*) FROM crm.acquisition_sources)<>3 OR NOT EXISTS(SELECT 1 FROM crm.first_retained_acquisition WHERE campaign_code='first') THEN RAISE EXCEPTION 'FAIL first retained touch'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
-- Synthetic canonical order header fixture; checkout lifecycle is covered in 0006.
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES('b0000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','synthetic','Synthetic');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,name,currency) VALUES('b0000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','synthetic','Synthetic','IRR');
INSERT INTO sales.orders(tenant_id,order_id,customer_id,warehouse_id,price_list_id,checkout_key,channel,currency,created_at,reservation_deadline,created_by)
 VALUES('b0000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','synthetic-order','web','IRR',clock_timestamp(),clock_timestamp()+interval '1 hour','b1000000-0000-0000-0000-000000000003');
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ DECLARE oid uuid:='f4000000-0000-0000-0000-000000000001'; aid uuid; BEGIN
 aid:=sales.attribute_order(oid);
 IF aid IS NULL OR sales.attribute_order(oid)<>aid OR NOT EXISTS(SELECT 1 FROM crm.acquisition_sources WHERE acquisition_id=aid AND campaign_code='last') THEN RAISE EXCEPTION 'FAIL deterministic last touch'; END IF;
 PERFORM web.withdraw_session('f1000000-0000-0000-0000-000000000002');
 IF EXISTS(SELECT 1 FROM sales.order_attribution) OR (SELECT count(*) FROM crm.acquisition_sources)<>2 THEN RAISE EXCEPTION 'FAIL session privacy erase'; END IF;
 INSERT INTO crm.customer_consent_events(tenant_id,customer_id,purpose,granted,origin_channel,evidence_digest)
 VALUES(iam.current_tenant_id(),'f0000000-0000-0000-0000-000000000001','analytics',false,'web',decode(repeat('c2',32),'hex'));
 IF EXISTS(SELECT 1 FROM crm.acquisition_sources) THEN RAISE EXCEPTION 'FAIL consent erasure'; END IF;
 BEGIN PERFORM crm.record_acquisition('f0000000-0000-0000-0000-000000000001','web','f1000000-0000-0000-0000-000000000001',decode(repeat('a6',32),'hex')); RAISE EXCEPTION 'FAIL revoked consent'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_acquisition_events) OR EXISTS(SELECT 1 FROM sales.order_attribution) THEN RAISE EXCEPTION 'FAIL leakage'; END IF;
 BEGIN PERFORM crm.record_acquisition('f0000000-0000-0000-0000-000000000002','app',gen_random_uuid(),decode(repeat('a7',32),'hex')); RAISE EXCEPTION 'FAIL unpurchased app'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customers)<>3 OR (SELECT count(*) FROM sales.orders)<>1 OR EXISTS(SELECT 1 FROM crm.customer_acquisition_events) OR EXISTS(SELECT 1 FROM sales.order_attribution) THEN RAISE EXCEPTION 'FAIL privacy preserved masters'; END IF;
END $$;
ROLLBACK;
\echo PASS attribution: verified customer and consent, source links, first retained and last order touch, tenant gates and privacy erasure

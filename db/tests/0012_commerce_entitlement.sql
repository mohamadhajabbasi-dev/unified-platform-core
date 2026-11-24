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
SET SESSION AUTHORIZATION upc_bill_admin;
DO $$
DECLARE ta uuid:='b0000000-0000-0000-0000-000000000001'; tb uuid:='b0000000-0000-0000-0000-000000000002';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; sa uuid; sb uuid; ia uuid; ib uuid; mid uuid;
BEGIN
 sa:=platform.create_subscription(ta,'commerce-term',d,d+30,'Synthetic Commerce',1000,'IRR');
 sb:=platform.create_subscription(tb,'general-term',d,d+30,'Synthetic general',1000,'IRR');
 mid:=platform.specify_purchased_module(ta,sa,'commerce');
 IF platform.specify_purchased_module(ta,sa,'commerce')<>mid THEN RAISE EXCEPTION 'FAIL module retry'; END IF;
 BEGIN
  PERFORM platform.specify_purchased_module(tb,sa,'commerce');
  RAISE EXCEPTION 'FAIL cross tenant term';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 ia:=platform.issue_subscription_invoice(ta,sa,d+7);
 ib:=platform.issue_subscription_invoice(tb,sb,d+7);
 PERFORM platform.record_billing_payment(tb,ib,'synthetic','platform','general-paid',1000,'IRR',clock_timestamp());
 BEGIN
  PERFORM platform.specify_purchased_module(tb,sb,'commerce'); RAISE EXCEPTION 'FAIL post invoice scope expansion';
 EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM platform.record_module_decision(ta,'commerce',true,NULL,'Synthetic approval');
 PERFORM platform.record_module_decision(tb,'commerce',true,NULL,'Synthetic approval');
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF platform.commerce_eligible() OR platform.has_paid_entitlement('commerce') THEN RAISE EXCEPTION 'FAIL unpaid approved term'; END IF;
 BEGIN
  PERFORM platform.specify_purchased_module(iam.current_tenant_id(),gen_random_uuid(),'commerce'); RAISE EXCEPTION 'FAIL tenant scope mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF platform.commerce_eligible() OR platform.has_paid_entitlement('commerce') OR EXISTS(SELECT 1 FROM platform.subscription_modules)
 THEN RAISE EXCEPTION 'FAIL generic paid term or cross tenant leakage'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SELECT invoice_id AS aid FROM platform.subscription_invoices WHERE tenant_id='b0000000-0000-0000-0000-000000000001' \gset
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_billing_payment('b0000000-0000-0000-0000-000000000001',:'aid','synthetic','platform','commerce-paid',1000,'IRR',clock_timestamp());
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','commerce',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF NOT platform.has_paid_entitlement('commerce') OR platform.commerce_eligible() THEN RAISE EXCEPTION 'FAIL paid without approval'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','commerce',true,NULL,'Synthetic approval');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF NOT platform.commerce_eligible() THEN RAISE EXCEPTION 'FAIL paid and approved'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
-- Simulate an expired term using bootstrap-only synthetic fixture adjustment.
UPDATE platform.subscriptions SET service_dates=daterange(current_date-31,current_date-1,'[)')
 WHERE tenant_id='b0000000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN IF platform.commerce_eligible() THEN RAISE EXCEPTION 'FAIL expired subscription'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS Commerce entitlement: explicit purchased scope, paid term, independent approval, expiry and isolation

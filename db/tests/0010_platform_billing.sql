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
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; sa uuid; sb uuid; ia uuid; ib uuid; pid uuid; at_time timestamptz;
BEGIN
 sa:=platform.create_subscription(ta,'term1',d,d+30,'Synthetic term',1000,'IRR');
 IF platform.create_subscription(ta,'term1',d,d+30,'Synthetic term',1000,'IRR')<>sa THEN RAISE EXCEPTION 'FAIL subscription retry'; END IF;
 BEGIN
  PERFORM platform.create_subscription(ta,'overlap',d+1,d+31,'Overlap',1000,'IRR'); RAISE EXCEPTION 'FAIL overlap';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 sb:=platform.create_subscription(tb,'term1',d,d+30,'Synthetic term',1000,'IRR');
 ia:=platform.issue_subscription_invoice(ta,sa,d+7);
 IF platform.issue_subscription_invoice(ta,sa,d+7)<>ia THEN RAISE EXCEPTION 'FAIL invoice retry'; END IF;
 ib:=platform.issue_subscription_invoice(tb,sb,d+7);
 BEGIN
  PERFORM platform.issue_subscription_invoice(tb,sa,d+7); RAISE EXCEPTION 'FAIL foreign subscription FK';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 at_time:=clock_timestamp();
 BEGIN
  PERFORM platform.record_billing_payment(ta,ia,'synthetic','platform','ref1',999,'IRR',at_time); RAISE EXCEPTION 'FAIL amount mismatch';
 EXCEPTION WHEN check_violation THEN NULL; END;
 pid:=platform.record_billing_payment(ta,ia,'synthetic','platform','ref1',1000,'IRR',at_time);
 IF platform.record_billing_payment(ta,ia,'synthetic','platform','ref1',1000,'IRR',at_time)<>pid THEN RAISE EXCEPTION 'FAIL receipt retry'; END IF;
 BEGIN
  PERFORM platform.record_billing_payment(tb,ib,'synthetic','platform','ref1',1000,'IRR',at_time); RAISE EXCEPTION 'FAIL cross tenant receipt reuse';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM platform.record_billing_payment(ta,ia,'synthetic','platform','ref2',1000,'IRR',at_time); RAISE EXCEPTION 'FAIL second receipt';
 EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF (SELECT count(*) FROM platform.billing_invoice_status)<>1 OR NOT EXISTS(SELECT 1 FROM platform.billing_invoice_status WHERE status='paid')
 OR (SELECT count(*) FROM platform.billing_payments)<>1 THEN RAISE EXCEPTION 'FAIL tenant A invoice view'; END IF;
 IF platform.module_enabled('catalog') THEN RAISE EXCEPTION 'FAIL payment grants module'; END IF;
 BEGIN
  PERFORM platform.create_subscription(iam.current_tenant_id(),'forbidden',current_date,current_date+1,'Forbidden',1,'IRR');
  RAISE EXCEPTION 'FAIL tenant billing mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE platform.subscriptions SET fee=1; RAISE EXCEPTION 'FAIL direct billing mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM platform.billing_invoice_status)<>1 OR NOT EXISTS(SELECT 1 FROM platform.billing_invoice_status WHERE status='unpaid')
 OR EXISTS(SELECT 1 FROM platform.billing_payments) THEN RAISE EXCEPTION 'FAIL tenant B isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_staff;
DO $$ BEGIN
 BEGIN
  PERFORM platform.issue_subscription_invoice('b0000000-0000-0000-0000-000000000001',gen_random_uuid(),current_date);
  RAISE EXCEPTION 'FAIL staff issue';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
UPDATE iam.platform_staff_assignments SET revoked_at=clock_timestamp() WHERE login_role='upc_bill_admin';
SET SESSION AUTHORIZATION upc_bill_admin;
DO $$ BEGIN
 BEGIN
  PERFORM platform.create_subscription('b0000000-0000-0000-0000-000000000001','revoked',current_date,current_date+1,'Denied',1,'IRR');
  RAISE EXCEPTION 'FAIL revoked admin';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.journal_entries) OR EXISTS(SELECT 1 FROM sales.payments)
 OR EXISTS(SELECT 1 FROM platform.tenant_module_grants WHERE tenant_id IN ('b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000002'))
 THEN RAISE EXCEPTION 'FAIL billing polluted tenant sales, finance or module grants'; END IF;
END $$;
ROLLBACK;
\echo PASS platform billing: term non-overlap, invoice and receipt idempotency, cross-tenant isolation, admin revocation and no tenant finance or entitlement effects

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_hr_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_hr_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_hr_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_hr_admin;
GRANT upc_runtime TO upc_hr_a,upc_hr_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('f0000000-0000-0000-0000-000000000001','hr-test-a','Synthetic organization A'),
 ('f0000000-0000-0000-0000-000000000002','hr-test-b','Synthetic organization B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('f1000000-0000-0000-0000-000000000001','test','hr-admin'),
 ('f1000000-0000-0000-0000-000000000002','test','hr-a'),
 ('f1000000-0000-0000-0000-000000000003','test','hr-b');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_hr_admin','f1000000-0000-0000-0000-000000000001',true);
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002'),
 ('f0000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_hr_a','f0000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002'),
 ('upc_hr_b','f0000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('f0000000-0000-0000-0000-000000000001','hr-writer'),
 ('f0000000-0000-0000-0000-000000000002','hr-writer');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key
 FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.role_key='hr-writer'
 AND p.permission_key IN ('hr.read','hr.write','hr.payroll.read','hr.payroll.write');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id
 FROM iam.memberships m JOIN iam.roles r USING(tenant_id) WHERE r.role_key='hr-writer';
-- Synthetic canonical order used only to verify commission FK.
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('f0000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000001','Synthetic buyer');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name)
 VALUES('f0000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001','hr-warehouse','Synthetic');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name)
 VALUES('f0000000-0000-0000-0000-000000000001','f4000000-0000-0000-0000-000000000001','hrtest','IRR','Synthetic');
INSERT INTO sales.orders(tenant_id,order_id,customer_id,warehouse_id,price_list_id,checkout_key,channel,currency,created_at,reservation_deadline,created_by)
 VALUES('f0000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000001',
 'f2000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000001',
 'f4000000-0000-0000-0000-000000000001','synthetic-hr-order','manual','IRR',clock_timestamp(),clock_timestamp()+interval '1 day',
 'f1000000-0000-0000-0000-000000000002');
SET SESSION AUTHORIZATION upc_hr_admin;
SELECT platform.record_module_decision('f0000000-0000-0000-0000-000000000001','hr',true,NULL,'Synthetic HR approval');
SELECT platform.record_module_decision('f0000000-0000-0000-0000-000000000002','hr',true,NULL,'Synthetic HR approval');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hr_a;
INSERT INTO hr.employees(tenant_id,employee_id,user_id,personnel_code,display_name,hired_on)
 VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001',iam.current_user_id(),
 'EMP-001','Synthetic employee',current_date-50);
INSERT INTO hr.employment_contracts(tenant_id,employee_id,effective_dates,role_title,monthly_base_pay,currency)
 VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001',
 daterange(current_date-30,NULL,'[)'),'Synthetic role',500,'IRR');
INSERT INTO hr.payroll_periods(tenant_id,period_id,covered_dates)
 VALUES(iam.current_tenant_id(),'f7000000-0000-0000-0000-000000000001',
 daterange(current_date,current_date+30,'[)'));
INSERT INTO hr.payroll_entries(tenant_id,period_id,employee_id,item_key,component,amount,currency)
 VALUES(iam.current_tenant_id(),'f7000000-0000-0000-0000-000000000001',
 'f6000000-0000-0000-0000-000000000001','salary','base',500,'IRR');
INSERT INTO hr.employee_obligations(tenant_id,employee_id,kind,principal,currency,issued_on)
 VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001','advance',50,'IRR',current_date);
INSERT INTO hr.commission_plans(tenant_id,commission_plan_id,plan_key,effective_dates,percentage)
 VALUES(iam.current_tenant_id(),'f8000000-0000-0000-0000-000000000001','sales',
 daterange(current_date-10,NULL,'[)'),5);
INSERT INTO hr.commission_entries(tenant_id,employee_id,commission_plan_id,order_id,source_event_key,amount,currency)
 VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001',
 'f8000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000001',
 'synthetic-commission-001',25,'IRR');
DO $$
BEGIN
 IF (SELECT count(*) FROM hr.employees)<>1 OR (SELECT count(*) FROM hr.payroll_entries)<>1
 OR (SELECT count(*) FROM hr.employee_obligations)<>1 OR (SELECT count(*) FROM hr.commission_entries)<>1
 THEN RAISE EXCEPTION 'FAIL basic HR events'; END IF;
 BEGIN
  INSERT INTO hr.employment_contracts(tenant_id,employee_id,effective_dates,role_title,monthly_base_pay,currency)
  VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001',
  daterange(current_date,current_date+20,'[)'),'duplicate',200,'IRR');
  RAISE EXCEPTION 'FAIL overlapping employment contract';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 BEGIN
  INSERT INTO hr.commission_entries(tenant_id,employee_id,commission_plan_id,order_id,source_event_key,amount,currency)
  VALUES(iam.current_tenant_id(),'f6000000-0000-0000-0000-000000000001',
  'f8000000-0000-0000-0000-000000000001','f5000000-0000-0000-0000-000000000001',
  'synthetic-commission-001',25,'IRR');
  RAISE EXCEPTION 'FAIL commission idempotency';
 EXCEPTION WHEN unique_violation THEN NULL; END;
END $$;
UPDATE hr.payroll_periods SET status='closed' WHERE period_id='f7000000-0000-0000-0000-000000000001';
DO $$
BEGIN
 BEGIN
 INSERT INTO hr.payroll_entries(tenant_id,period_id,employee_id,item_key,component,amount,currency)
 VALUES(iam.current_tenant_id(),'f7000000-0000-0000-0000-000000000001',
 'f6000000-0000-0000-0000-000000000001','late','bonus',10,'IRR');
 RAISE EXCEPTION 'FAIL closed payroll period gate';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
 UPDATE hr.payroll_entries SET amount=100;
 RAISE EXCEPTION 'FAIL immutable payroll write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hr_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hr.employees) OR EXISTS(SELECT 1 FROM hr.payroll_entries)
 OR EXISTS(SELECT 1 FROM hr.commission_entries)
 THEN RAISE EXCEPTION 'FAIL cross tenant employee/payroll leak'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hr_admin;
SELECT platform.record_module_decision('f0000000-0000-0000-0000-000000000001','hr',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_hr_a;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hr.employees) THEN RAISE EXCEPTION 'FAIL HR module revocation'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS HR/contracts/payroll/advances/commissions: tenant RLS and source integrity

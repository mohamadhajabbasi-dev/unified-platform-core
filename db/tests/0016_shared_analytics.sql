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
SET SESSION AUTHORIZATION upc_bill_a;
DO $$
DECLARE a uuid:='d0000000-0000-0000-0000-000000000001'; r1 uuid:='d1000000-0000-0000-0000-000000000001'; r2 uuid:='d1000000-0000-0000-0000-000000000002';
 i uuid:='d2000000-0000-0000-0000-000000000001'; s uuid:='d3000000-0000-0000-0000-000000000001'; s2 uuid:='d3000000-0000-0000-0000-000000000002'; e uuid:='d4000000-0000-0000-0000-000000000001';
BEGIN
 INSERT INTO platform.applications(tenant_id,application_id,app_platform,package_key,display_name) VALUES(iam.current_tenant_id(),a,'android','synthetic.test','Synthetic');
 INSERT INTO platform.app_releases(tenant_id,application_id,release_id,version_label,build_key,release_channel) VALUES
 (iam.current_tenant_id(),a,r1,'1.0','1','stable'),(iam.current_tenant_id(),a,r2,'2.0','2','stable');
 BEGIN PERFORM analytics.first_open(a,r1,i,false,'v1'); RAISE EXCEPTION 'FAIL no consent'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF analytics.first_open(a,r1,i,true,'v1')<>i OR analytics.first_open(a,r1,i,true,'v1')<>i THEN RAISE EXCEPTION 'FAIL install retry'; END IF;
 PERFORM analytics.start_app_session(a,r1,i,s,true,'v1','paid','synthetic',NULL,'campaign','home');
 PERFORM analytics.start_app_session(a,r2,i,s2,true,'v1','direct',NULL,NULL,NULL,'home');
 PERFORM analytics.record_app_event(e,s,'screen_view','home');
 PERFORM analytics.record_app_event(e,s,'screen_view','home');
 BEGIN PERFORM web.record_event(gen_random_uuid(),s,'page_view','home'); RAISE EXCEPTION 'FAIL cross channel write'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 PERFORM web.start_session(gen_random_uuid(),true,false,'v1','direct',NULL,NULL,NULL,'home');
 IF (SELECT count(*) FROM analytics.sessions)<>3 OR (SELECT count(*) FROM analytics.events)<>1
 OR (SELECT sum(first_opens) FROM analytics.daily_first_opens)<>1
 OR NOT EXISTS(SELECT 1 FROM analytics.daily_activity WHERE channel='app' AND sessions=2 AND active_installations=1)
 OR (SELECT sum(sessions) FROM web.daily_sources)<>1 THEN RAISE EXCEPTION 'FAIL distinct metrics'; END IF;
 PERFORM web.withdraw_session(s);
 IF NOT EXISTS(SELECT 1 FROM analytics.events WHERE event_id=e) THEN RAISE EXCEPTION 'FAIL web privacy touched app'; END IF;
 UPDATE platform.app_releases SET is_active=false WHERE release_id=r2;
 BEGIN PERFORM analytics.record_app_event(gen_random_uuid(),s2,'screen_view','home'); RAISE EXCEPTION 'FAIL disabled release'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF NOT platform.commerce_eligible() OR platform.app_eligible() OR EXISTS(SELECT 1 FROM analytics.sessions)
 OR EXISTS(SELECT 1 FROM analytics.app_installations) THEN RAISE EXCEPTION 'FAIL scope'; END IF;
 BEGIN PERFORM analytics.first_open(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),true,'v1'); RAISE EXCEPTION 'FAIL commerce-only app'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','app.analytics',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.sessions WHERE channel='app') OR EXISTS(SELECT 1 FROM analytics.app_installations) THEN RAISE EXCEPTION 'FAIL revoked read'; END IF;
 BEGIN PERFORM analytics.record_app_event(gen_random_uuid(),'d3000000-0000-0000-0000-000000000001','screen_view','home'); RAISE EXCEPTION 'FAIL revoked write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM analytics.withdraw_installation('d0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001');
 IF (SELECT count(*) FROM analytics.sessions)<>1 THEN RAISE EXCEPTION 'FAIL web unaffected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.sessions WHERE channel='app') OR EXISTS(SELECT 1 FROM analytics.events)
 OR EXISTS(SELECT 1 FROM crm.customers) OR NOT EXISTS(SELECT 1 FROM analytics.app_installations WHERE withdrawn_at IS NOT NULL)
 OR to_regclass('web.visitor_sessions') IS NOT NULL OR to_regclass('web.visit_events') IS NOT NULL
 THEN RAISE EXCEPTION 'FAIL withdrawal or duplicate master'; END IF;
END $$;
ROLLBACK;
\echo PASS shared analytics: one session/event master, app registry and release, first-open dedupe, distinct web/app gates, activity, withdrawal and isolation

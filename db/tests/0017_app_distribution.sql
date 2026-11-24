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

GRANT upc_distribution_importer TO upc_bill_a,upc_bill_b;
INSERT INTO platform.applications(tenant_id,application_id,app_platform,package_key,display_name) VALUES
 ('b0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','android','synthetic.a','Synthetic A'),
 ('b0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','android','synthetic.b','Synthetic B');
INSERT INTO platform.app_releases(tenant_id,application_id,release_id,version_label,build_key,release_channel) VALUES
 ('b0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','1.0','1','stable'),
 ('b0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000002','1.0','1','stable');
SET SESSION AUTHORIZATION upc_bill_a;
DO $$
DECLARE a uuid:='e0000000-0000-0000-0000-000000000001'; rel uuid:='e1000000-0000-0000-0000-000000000001';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date-1; digest bytea:=decode(repeat('ab',32),'hex'); rid uuid;
BEGIN
 rid:=analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','downloads','native_downloads',1,100,NULL,digest,'synthetic-batch');
 IF analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','downloads','native_downloads',1,100,NULL,digest,'synthetic-batch')<>rid THEN RAISE EXCEPTION 'FAIL idempotency'; END IF;
 BEGIN PERFORM analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','downloads','native_downloads',1,101,NULL,digest,'synthetic-batch'); RAISE EXCEPTION 'FAIL conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','downloads','native_downloads',2,105,NULL,digest,'synthetic-correction');
 PERFORM analytics.import_distribution_report(a,rel,'cafebazaar',d,'UTC','downloads','native_downloads',1,70,NULL,digest,'synthetic-release');
 PERFORM analytics.import_distribution_report(a,NULL,'myket',d,'UTC','downloads','native_downloads',1,NULL,'not_reported',digest,'synthetic-unknown');
 PERFORM analytics.import_distribution_report(a,NULL,'google_play',d,'UTC','downloads','native_downloads',1,0,NULL,digest,'synthetic-zero');
 PERFORM analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','provider_installs','native_installs',1,80,NULL,digest,'synthetic-install');
 IF (SELECT count(*) FROM analytics.app_distribution_reports)<>6 OR (SELECT count(*) FROM analytics.distribution_latest)<>5
 OR NOT EXISTS(SELECT 1 FROM analytics.distribution_latest WHERE release_id IS NULL AND source='cafebazaar' AND metric='downloads' AND metric_count=105 AND revision=2)
 OR NOT EXISTS(SELECT 1 FROM analytics.distribution_latest WHERE source='myket' AND status='unknown' AND metric_count IS NULL)
 OR NOT EXISTS(SELECT 1 FROM analytics.distribution_latest WHERE source='google_play' AND status='reported' AND metric_count=0)
 OR EXISTS(SELECT 1 FROM analytics.daily_first_opens) THEN RAISE EXCEPTION 'FAIL metric separation or revision'; END IF;
 BEGIN PERFORM analytics.import_distribution_report(a,NULL,'cafebazaar',d,'UTC','downloads','native_downloads',4,106,NULL,digest,'synthetic-gap'); RAISE EXCEPTION 'FAIL gap';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM analytics.import_distribution_report(a,'e1000000-0000-0000-0000-000000000002','cafebazaar',d,'UTC','downloads','native_downloads',1,1,NULL,digest,'foreign'); RAISE EXCEPTION 'FAIL foreign release';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM analytics.import_distribution_report(a,NULL,'app_store',d,'UTC','downloads','native_downloads',1,1,NULL,digest,'bad-source'); RAISE EXCEPTION 'FAIL platform mismatch';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM analytics.import_distribution_report(a,NULL,'website',d,'UTC','downloads','native_downloads',1,-1,NULL,digest,'bad-count'); RAISE EXCEPTION 'FAIL negative count';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN UPDATE analytics.app_distribution_reports SET metric_count=999; RAISE EXCEPTION 'FAIL mutable report';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.distribution_latest) THEN RAISE EXCEPTION 'FAIL leakage'; END IF;
 BEGIN PERFORM analytics.import_distribution_report('e0000000-0000-0000-0000-000000000002',NULL,'myket',current_date-1,'UTC','downloads','native_downloads',1,1,NULL,decode(repeat('ab',32),'hex'),'denied'); RAISE EXCEPTION 'FAIL commerce-only import';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
REVOKE upc_distribution_importer FROM upc_bill_a;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 BEGIN PERFORM analytics.import_distribution_report('e0000000-0000-0000-0000-000000000001',NULL,'myket',current_date-1,'UTC','downloads','native_downloads',1,1,NULL,decode(repeat('ab',32),'hex'),'denied'); RAISE EXCEPTION 'FAIL ordinary runtime import';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT upc_distribution_importer TO upc_bill_a;
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','app.analytics',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.distribution_latest) THEN RAISE EXCEPTION 'FAIL revoked read'; END IF;
 BEGIN PERFORM analytics.import_distribution_report('e0000000-0000-0000-0000-000000000001',NULL,'myket',current_date-1,'UTC','downloads','native_downloads',1,1,NULL,decode(repeat('ab',32),'hex'),'denied'); RAISE EXCEPTION 'FAIL revoked import';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS distribution: verified-import boundary, revision idempotency, unknown versus zero, scope, distinct metrics and entitlement

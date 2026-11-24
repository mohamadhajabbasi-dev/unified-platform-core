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
SET SESSION AUTHORIZATION upc_bill_admin;
DO $$
DECLARE ta uuid:='b0000000-0000-0000-0000-000000000001'; tb uuid:='b0000000-0000-0000-0000-000000000002';
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; sa uuid; sb uuid; ia uuid;
BEGIN
 sa:=platform.create_subscription(ta,'commerce-term',d,d+30,'Synthetic Commerce',1000,'IRR');
 PERFORM platform.specify_purchased_module(ta,sa,'commerce');
 ia:=platform.issue_subscription_invoice(ta,sa,d+7);
 PERFORM platform.record_billing_payment(ta,ia,'synthetic','platform','commerce-paid',1000,'IRR',clock_timestamp());
 sb:=platform.create_subscription(tb,'unpaid-term',d,d+30,'Synthetic unpaid',1000,'IRR');
 PERFORM platform.specify_purchased_module(tb,sb,'commerce');
 PERFORM platform.issue_subscription_invoice(tb,sb,d+7);
 PERFORM platform.record_module_decision(ta,'commerce',true,NULL,'Synthetic approval');
 PERFORM platform.record_module_decision(tb,'commerce',true,NULL,'Synthetic approval');
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$
DECLARE s uuid:='c0000000-0000-0000-0000-000000000001'; e uuid:='c1000000-0000-0000-0000-000000000001';
BEGIN
 BEGIN
 PERFORM web.start_session(s,false,false,'v1','organic','search','organic','synthetic','home'); RAISE EXCEPTION 'FAIL no consent';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
 PERFORM web.start_session(s,true,true,'v1','organic','search','organic','synthetic','home'); RAISE EXCEPTION 'FAIL bot';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF web.start_session(s,true,false,'v1','organic','search','organic','synthetic','home')<>s THEN RAISE EXCEPTION 'FAIL session creation'; END IF;
 IF web.start_session(s,true,false,'v1','organic','search','organic','synthetic','home')<>s THEN RAISE EXCEPTION 'FAIL session retry'; END IF;
 BEGIN
 PERFORM web.start_session(s,true,false,'v1','paid','search','organic','synthetic','home'); RAISE EXCEPTION 'FAIL source rewrite';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 PERFORM web.record_event(e,s,'page_view','home');
 PERFORM web.record_event(e,s,'page_view','home');
 BEGIN
 PERFORM web.record_event(e,s,'page_view','catalog'); RAISE EXCEPTION 'FAIL event payload conflict';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT count(*) FROM analytics.sessions)<>1 OR (SELECT count(*) FROM analytics.events)<>1
 OR NOT EXISTS(SELECT 1 FROM web.daily_sources WHERE sessions=1 AND events=1 AND source_type='organic')
 THEN RAISE EXCEPTION 'FAIL visit counts'; END IF;
 BEGIN
 DELETE FROM analytics.events; RAISE EXCEPTION 'FAIL direct event mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.sessions) OR EXISTS(SELECT 1 FROM analytics.events) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF;
 BEGIN
 PERFORM web.start_session(gen_random_uuid(),true,false,'v1','direct',NULL,NULL,NULL,'home'); RAISE EXCEPTION 'FAIL unpaid collection';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL anonymous visit created customer'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_bill_a;
SELECT web.withdraw_session('c0000000-0000-0000-0000-000000000001');
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM analytics.sessions) OR EXISTS(SELECT 1 FROM analytics.events) THEN RAISE EXCEPTION 'FAIL withdrawal visibility'; END IF;
 BEGIN
 PERFORM web.start_session('c0000000-0000-0000-0000-000000000001',true,false,'v1','organic','search','organic','synthetic','home');
 RAISE EXCEPTION 'FAIL withdrawn retry';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Bootstrap-only synthetic expiry simulation.
UPDATE analytics.sessions SET started_at=clock_timestamp()-interval '32 days',
 collection_until=clock_timestamp()-interval '31 days',retain_until=clock_timestamp()-interval '2 days'
 WHERE session_id='c0000000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION upc_bill_admin;
SELECT platform.record_module_decision('b0000000-0000-0000-0000-000000000001','commerce',false,NULL,'Synthetic revoke');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN
 BEGIN
 PERFORM web.start_session(gen_random_uuid(),true,false,'v1','direct',NULL,NULL,NULL,'home'); RAISE EXCEPTION 'FAIL revoked collection';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF web.purge_expired(100)<>1 THEN RAISE EXCEPTION 'FAIL retention purge after revocation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM analytics.sessions) OR EXISTS(SELECT 1 FROM analytics.events)
 THEN RAISE EXCEPTION 'FAIL physical purge'; END IF; END $$;
ROLLBACK;
\echo PASS web analytics: paid approval gate, consent, bot rejection, session and event idempotency, isolation, withdrawal and retention

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
-- Same account in two tenants: settings must remain independent.
INSERT INTO iam.memberships(tenant_id,user_id) VALUES('b0000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000003');
CREATE ROLE upc_dossier_ab LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_dossier_ab;
INSERT INTO iam.db_principals VALUES('upc_dossier_ab','b0000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000003');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE tenant_id='b0000000-0000-0000-0000-000000000001' AND role_key='billing-reader'
 AND (p.permission_key LIKE 'tenant.%' OR p.permission_key='ops.audit.read');
SET SESSION AUTHORIZATION upc_bill_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); u uuid:=iam.current_user_id();
BEGIN
 INSERT INTO core.tenant_profiles VALUES(t,'registered_entity','Synthetic Organization','IR','Synthetic jurisdiction','vault:test-registration',NULL,'vault:test-tax','unverified','Retail');
 INSERT INTO core.tenant_stakeholders(tenant_id,party_ref,party_type,party_name,user_id,roles,ownership_pct,valid_during)
 VALUES(t,'synthetic-person','individual','Synthetic person',u,ARRAY['partner','signatory'],60,daterange('2026-01-01',NULL,'[)')),
 (t,'synthetic-company','organization','Synthetic company',NULL,ARRAY['shareholder'],40,daterange('2026-01-01',NULL,'[)'));
 BEGIN
  INSERT INTO core.tenant_stakeholders(tenant_id,party_ref,party_type,party_name,user_id,roles,valid_during)
  VALUES(t,'foreign','individual','Foreign member','b1000000-0000-0000-0000-000000000004',ARRAY['manager'],daterange('2026-01-01',NULL,'[)'));
  RAISE EXCEPTION 'FAIL foreign member';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  INSERT INTO core.tenant_stakeholders(tenant_id,party_ref,party_type,party_name,roles,valid_during)
  VALUES(t,'synthetic-person','individual','Duplicate',ARRAY['partner'],daterange('2026-02-01',NULL,'[)'));
  RAISE EXCEPTION 'FAIL duplicate stakeholder period';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 INSERT INTO core.tenant_addresses(tenant_id,address_kind,country_code,address_text) VALUES(t,'registered','IR','Synthetic address');
 INSERT INTO core.tenant_settings(tenant_id,locale,timezone) VALUES(t,'fa-IR','Asia/Tehran');
 BEGIN
  UPDATE core.tenant_settings SET timezone='Invalid/Zone'; RAISE EXCEPTION 'FAIL timezone validation';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO iam.membership_settings(tenant_id,user_id,job_title) VALUES(t,u,'Synthetic manager');
 PERFORM iam.set_my_preferences('fa-IR','Asia/Tehran',false);
 IF (SELECT job_title FROM iam.membership_settings WHERE user_id=u)<>'Synthetic manager'
 OR (SELECT count(*) FROM ops.audit_events)<>7 THEN RAISE EXCEPTION 'FAIL preferences or audit'; END IF;
 BEGIN
  INSERT INTO core.tenant_profiles(tenant_id,entity_type,registered_name,country_code,jurisdiction,legal_status)
  VALUES('b0000000-0000-0000-0000-000000000002','individual','Forbidden','IR','Synthetic','unverified');
  RAISE EXCEPTION 'FAIL foreign dossier write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  DELETE FROM ops.audit_events; RAISE EXCEPTION 'FAIL audit deletion';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_dossier_ab;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.tenant_profiles) OR EXISTS(SELECT 1 FROM core.tenant_stakeholders) OR EXISTS(SELECT 1 FROM ops.audit_events)
 THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF;
 PERFORM iam.set_my_preferences('en-US','UTC',true);
 IF NOT EXISTS(SELECT 1 FROM iam.membership_settings WHERE locale='en-US' AND job_title IS NULL) THEN RAISE EXCEPTION 'FAIL separate preferences'; END IF;
 UPDATE iam.membership_settings SET job_title='Unauthorized';
 IF FOUND THEN RAISE EXCEPTION 'FAIL self promotion'; END IF;
 BEGIN
  INSERT INTO core.tenant_settings(tenant_id,locale,timezone) VALUES(iam.current_tenant_id(),'en-US','UTC');
  RAISE EXCEPTION 'FAIL unauthorized org settings';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bill_a;
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM iam.membership_settings WHERE locale='fa-IR' AND NOT notifications_enabled)
 THEN RAISE EXCEPTION 'FAIL cross tenant preferences overwritten'; END IF; END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.memberships WHERE tenant_id='b0000000-0000-0000-0000-000000000002' AND user_id='b1000000-0000-0000-0000-000000000003';
SET SESSION AUTHORIZATION upc_dossier_ab;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM iam.membership_settings) THEN RAISE EXCEPTION 'FAIL revoked membership read'; END IF;
 BEGIN
  PERFORM iam.set_my_preferences('en-US','UTC',true); RAISE EXCEPTION 'FAIL revoked preference write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS dossier: legal scope, stakeholder relationships, typed settings, self preferences, tenant separation, audit metadata and revocation

\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_crm_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_crm_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_crm_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime,upc_identity_writer TO upc_crm_a,upc_crm_b,upc_crm_reader;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('60000000-0000-0000-0000-000000000001','crm-a','Synthetic A'),
 ('60000000-0000-0000-0000-000000000002','crm-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('61000000-0000-0000-0000-000000000001','test','crm-a'),
 ('61000000-0000-0000-0000-000000000002','test','crm-b'),
 ('61000000-0000-0000-0000-000000000003','test','crm-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('60000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001'),
 ('60000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000002'),
 ('60000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_crm_a','60000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000001'),
 ('upc_crm_b','60000000-0000-0000-0000-000000000002','61000000-0000-0000-0000-000000000002'),
 ('upc_crm_reader','60000000-0000-0000-0000-000000000001','61000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('60000000-0000-0000-0000-000000000001','writer'),
 ('60000000-0000-0000-0000-000000000002','writer'),
 ('60000000-0000-0000-0000-000000000001','reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key
 FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.role_key='writer' AND p.permission_key IN ('crm.read','crm.write');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'crm.read' FROM iam.roles WHERE role_key='reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id
 FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='61000000-0000-0000-0000-000000000003' AND r.role_key='reader')
 OR (m.user_id<>'61000000-0000-0000-0000-000000000003' AND r.role_key='writer');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('60000000-0000-0000-0000-000000000002','62000000-0000-0000-0000-000000000002','Synthetic foreign customer');
SET SESSION AUTHORIZATION upc_crm_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL disabled module read'; END IF;
 BEGIN
  PERFORM crm.resolve_verified_customer('channel','test','disabled','Forbidden');
  RAISE EXCEPTION 'FAIL disabled module write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '60000000-0000-0000-0000-000000000001',module_id,true,'61000000-0000-0000-0000-000000000001','Synthetic enable' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_crm_a;
DO $$
DECLARE a uuid; b uuid;
BEGIN
 a:=crm.resolve_verified_customer('channel','test','identity-a','A');
 IF crm.link_verified_identity(a,'email','','synthetic-a@example.invalid')<>a OR
 crm.resolve_verified_customer('email','','synthetic-a@example.invalid','A')<>a
 THEN RAISE EXCEPTION 'FAIL linked identity reuse'; END IF;
 b:=crm.resolve_verified_customer('channel','test','identity-b','B');
 BEGIN
  PERFORM crm.link_verified_identity(b,'email','','synthetic-a@example.invalid');
  RAISE EXCEPTION 'FAIL conflicting identity merged';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM crm.link_verified_identity('62000000-0000-0000-0000-000000000002','channel','test','foreign');
  RAISE EXCEPTION 'FAIL cross-tenant link';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 IF (SELECT count(*) FROM crm.customers)<>2 OR (SELECT count(*) FROM crm.customer_identifiers)<>3
 THEN RAISE EXCEPTION 'FAIL identity count'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_crm_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customers)<>2 THEN RAISE EXCEPTION 'FAIL permitted read'; END IF;
 BEGIN
  PERFORM crm.resolve_verified_customer('channel','test','forbidden','Forbidden');
  RAISE EXCEPTION 'FAIL missing write permission';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants WHERE permission_key='crm.read' AND tenant_id='60000000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION upc_crm_reader;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL permission revocation'; END IF; END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '60000000-0000-0000-0000-000000000001',module_id,false,'61000000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_crm_a;
DO $$ BEGIN
 BEGIN
  PERFORM crm.resolve_verified_customer('channel','test','identity-a','A');
  RAISE EXCEPTION 'FAIL module revocation';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL revoked module read'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS CRM authorization: permission and module gates, verified identity link, conflict rejection, cross-tenant rejection and revocation

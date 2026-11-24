\set ON_ERROR_STOP on
BEGIN;
-- All fixtures are synthetic; transaction rolls them back.
CREATE ROLE upc_test_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_test_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_test_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_test_readonly LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime,upc_identity_writer TO upc_test_a,upc_test_b,upc_test_unmapped;
GRANT upc_runtime TO upc_test_readonly;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('00000000-0000-0000-0000-000000000001','tenant-a','Synthetic A'),
 ('00000000-0000-0000-0000-000000000002','tenant-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('10000000-0000-0000-0000-000000000001','test','synthetic-actor-a'),
 ('10000000-0000-0000-0000-000000000002','test','synthetic-actor-b');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_test_a','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001'),
 ('upc_test_b','00000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002'),
 ('upc_test_readonly','00000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001');
SET SESSION AUTHORIZATION upc_test_a;
DO $$
DECLARE first_id uuid; second_id uuid;
BEGIN
  first_id := crm.resolve_verified_customer('phone','','+15550000001','Synthetic customer A');
  second_id := crm.resolve_verified_customer('phone','','+15550000001','Same identity from another channel');
  IF first_id IS DISTINCT FROM second_id OR (SELECT count(*) FROM crm.customers) <> 1 THEN
    RAISE EXCEPTION 'FAIL same verified identity';
  END IF;
  PERFORM set_config('app.tenant_id','00000000-0000-0000-0000-000000000002',true);
  IF iam.current_tenant_id() IS DISTINCT FROM '00000000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL forged GUC';
  END IF;
  BEGIN
    INSERT INTO crm.customers(tenant_id,display_name) VALUES
      ('00000000-0000-0000-0000-000000000002','Forbidden');
    RAISE EXCEPTION 'FAIL direct customer insert';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM crm.resolve_verified_customer('phone','','invalid','Invalid');
    RAISE EXCEPTION 'FAIL invalid phone accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT count(*) FROM crm.customers) <> 1 THEN RAISE EXCEPTION 'FAIL atomic rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_test_b;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL tenant B initially sees A'; END IF;
  PERFORM crm.resolve_verified_customer('phone','','+15550000001','Synthetic customer B');
  IF (SELECT count(*) FROM crm.customers) <> 1
    OR EXISTS (SELECT 1 FROM crm.customers WHERE tenant_id <> iam.current_tenant_id())
    THEN RAISE EXCEPTION 'FAIL tenant B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
DECLARE a_id uuid; b_id uuid;
BEGIN
  SELECT customer_id INTO STRICT a_id FROM crm.customers WHERE tenant_id='00000000-0000-0000-0000-000000000001';
  SELECT customer_id INTO STRICT b_id FROM crm.customers WHERE tenant_id='00000000-0000-0000-0000-000000000002';
  IF a_id = b_id THEN RAISE EXCEPTION 'FAIL independent profiles'; END IF;
  BEGIN
    INSERT INTO crm.customer_addresses(tenant_id,customer_id,address_text)
      VALUES ('00000000-0000-0000-0000-000000000002',a_id,'Invalid cross-tenant address');
    RAISE EXCEPTION 'FAIL cross-tenant FK';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO crm.customer_identifiers(tenant_id,customer_id,kind,issuer,normalized_value,verified_at)
      VALUES ('00000000-0000-0000-0000-000000000001',a_id,'phone','','+15550000001',now());
    RAISE EXCEPTION 'FAIL duplicate verified identifier';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
SET SESSION AUTHORIZATION upc_test_readonly;
DO $$
BEGIN
  IF (SELECT count(*) FROM crm.customers) <> 1 THEN RAISE EXCEPTION 'FAIL A reads own only'; END IF;
  BEGIN
    PERFORM crm.resolve_verified_customer('phone','','+15550000002','Forbidden');
    RAISE EXCEPTION 'FAIL readonly verification permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM 1 FROM iam.db_principals;
    RAISE EXCEPTION 'FAIL private directory visible';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_test_unmapped;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM crm.customers) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF;
  BEGIN
    PERFORM crm.resolve_verified_customer('phone','','+15550000002','Forbidden');
    RAISE EXCEPTION 'FAIL unmapped writer';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.memberships WHERE tenant_id='00000000-0000-0000-0000-000000000001';
SET SESSION AUTHORIZATION upc_test_a;
DO $$ BEGIN
  IF iam.current_tenant_id() IS NOT NULL OR EXISTS (SELECT 1 FROM crm.customers)
  THEN RAISE EXCEPTION 'FAIL revoked membership'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS foundation: identity reuse, cross-tenant isolation, verified uniqueness, FK, privilege, spoofing, fail-closed and revocation

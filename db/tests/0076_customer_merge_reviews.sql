\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_merge_review_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_merge_review_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_merge_review_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_merge_review_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_merge_review_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_merge_review_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_merge_review_a,upc_merge_review_b,upc_merge_review_reader,upc_merge_review_nocrm,upc_merge_review_unmapped,upc_merge_review_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0760000-0000-0000-0000-000000000001','merge-review-a','Synthetic A'),('a0760000-0000-0000-0000-000000000002','merge-review-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0760000-0000-0000-0000-00000000000'||i)::uuid,'test','merge-review-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0760000-0000-0000-0000-000000000002'::uuid ELSE 'a0760000-0000-0000-0000-000000000001'::uuid END,
 ('b0760000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_merge_review_a','upc_merge_review_b','upc_merge_review_reader','upc_merge_review_nocrm','upc_merge_review_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0760000-0000-0000-0000-000000000002'::uuid ELSE 'a0760000-0000-0000-0000-000000000001'::uuid END,
 ('b0760000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0760000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'merge-review-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0760000-0000-0000-0000-000000000001','a0760000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='merge-review-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0760000-0000-0000-0000-000000000001','a0760000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0760000-0000-0000-0000-000000000001','a0760000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('merge-review-1','merge-review-2') AND p.permission_key IN ('crm.read','crm.merge_reviews.read','crm.merge_reviews.write','ops.audit.read'))
 OR (r.role_key='merge-review-3' AND p.permission_key IN ('crm.read','crm.merge_reviews.read'))
 OR (r.role_key='merge-review-4' AND p.permission_key IN ('crm.merge_reviews.read','crm.merge_reviews.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0760000-0000-0000-0000-000000000002','d0760000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0760000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('merge-review-a','merge-review-b') AND m.module_key IN ('crm');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES ('a0760000-0000-0000-0000-000000000002','d0760000-0000-0000-0000-000000000004','Synthetic B2'),('a0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000005','Synthetic A3');
SET SESSION AUTHORIZATION upc_merge_review_b;
SELECT crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000002','d0760000-0000-0000-0000-000000000004');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_a;
DO $$
DECLARE rid uuid; previous jsonb; customers_before jsonb; cmd text;
BEGIN
 SELECT jsonb_agg(to_jsonb(c) ORDER BY customer_id) INTO customers_before FROM crm.customers c;
 rid:=crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000003','d0760000-0000-0000-0000-000000000001');
 SELECT to_jsonb(v) INTO previous FROM crm.customer_merge_reviews v WHERE review_id=rid;
 IF rid IS NULL OR previous IS NULL OR crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003') IS DISTINCT FROM rid
 OR (SELECT to_jsonb(v) FROM crm.customer_merge_reviews v WHERE review_id=rid) IS DISTINCT FROM previous
 OR (SELECT count(*) FROM crm.customer_merge_reviews)<>1
 OR NOT EXISTS(SELECT 1 FROM crm.customer_merge_reviews WHERE customer_low_id='d0760000-0000-0000-0000-000000000001' AND customer_high_id='d0760000-0000-0000-0000-000000000003' AND requested_by=iam.current_user_id())
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.customer_merge_reviews' AND entity_id=rid AND actor_user_id=iam.current_user_id() AND event_type='insert')<>1
 THEN RAISE EXCEPTION 'FAIL unordered pair replay or audit'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000002'); RAISE EXCEPTION 'FAIL foreign customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000002','d0760000-0000-0000-0000-000000000004'); RAISE EXCEPTION 'FAIL foreign pair'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL self pair'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null pair'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO crm.customer_merge_reviews(tenant_id,customer_low_id,customer_high_id,requested_by) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid(),iam.current_user_id())','UPDATE crm.customer_merge_reviews SET requested_at=clock_timestamp()','DELETE FROM crm.customer_merge_reviews','TRUNCATE crm.customer_merge_reviews','SET ROLE upc_merge_review_executor','DELETE FROM ops.audit_events'] LOOP
 BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000005'); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM crm.customer_merge_reviews)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.customer_merge_reviews')<>1
 OR (SELECT jsonb_agg(to_jsonb(c) ORDER BY customer_id) FROM crm.customers c) IS DISTINCT FROM customers_before THEN RAISE EXCEPTION 'FAIL rollback or customer mutation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customer_merge_reviews)<>1 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL reader retry'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_merge_reviews) THEN RAISE EXCEPTION 'FAIL missing CRM base'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL missing CRM base write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_merge_reviews) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL unmapped request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_merge_reviews) THEN RAISE EXCEPTION 'FAIL no permissions read'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL no permissions write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason) SELECT 'a0760000-0000-0000-0000-000000000001',module_id,false,'b0760000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='crm';
SET SESSION AUTHORIZATION upc_merge_review_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM crm.customer_merge_reviews) THEN RAISE EXCEPTION 'FAIL disabled CRM read'; END IF;
 BEGIN PERFORM crm.request_customer_merge_review('d0760000-0000-0000-0000-000000000001','d0760000-0000-0000-0000-000000000003'); RAISE EXCEPTION 'FAIL disabled CRM request'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_merge_review_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customer_merge_reviews)<>1 OR NOT EXISTS(SELECT 1 FROM crm.customer_merge_reviews WHERE customer_low_id='d0760000-0000-0000-0000-000000000002' AND customer_high_id='d0760000-0000-0000-0000-000000000004') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM crm.customer_merge_reviews)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='crm.customer_merge_reviews')<>2
 OR (SELECT count(*) FROM crm.customers WHERE tenant_id IN('a0760000-0000-0000-0000-000000000001','a0760000-0000-0000-0000-000000000002'))<>5
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='crm.customer_merge_reviews'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','crm.customer_merge_reviews','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_merge_review_executor','MEMBER')
 OR has_any_column_privilege('upc_merge_review_executor','crm.customers','INSERT,UPDATE,REFERENCES')
 OR has_column_privilege('upc_merge_review_executor','crm.customers','display_name','SELECT')
 OR has_table_privilege('upc_merge_review_executor','crm.customer_identifiers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_merge_review_executor','crm.customer_addresses','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_merge_review_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_merge_review_executor','ops.audit_events','SELECT,INSERT,UPDATE,DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='crm.request_customer_merge_review(uuid,uuid)'::regprocedure AND r.rolname='upc_merge_review_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS customer merge reviews: unordered pair idempotency, tenant and permission gates, no identity changes, audit and rollback

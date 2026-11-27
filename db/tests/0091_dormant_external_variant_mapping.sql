\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_map_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_map_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_map_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_map_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_map_a,upc_map_b,upc_map_unmapped;
GRANT upc_platform_approver TO upc_map_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0910000-0000-0000-0000-000000000001','mapping-a','Synthetic A'),
 ('a0910000-0000-0000-0000-000000000002','mapping-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0910000-0000-0000-0000-000000000001','test','mapping-a'),
 ('b0910000-0000-0000-0000-000000000002','test','mapping-b'),
 ('b0910000-0000-0000-0000-000000000003','test','mapping-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0910000-0000-0000-0000-000000000001','b0910000-0000-0000-0000-000000000001'),
 ('a0910000-0000-0000-0000-000000000002','b0910000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_map_a','a0910000-0000-0000-0000-000000000001','b0910000-0000-0000-0000-000000000001'),
 ('upc_map_b','a0910000-0000-0000-0000-000000000002','b0910000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_map_platform','b0910000-0000-0000-0000-000000000003',true);
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0910000-0000-0000-0000-000000000001','d0910000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0910000-0000-0000-0000-000000000002','d0910000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0910000-0000-0000-0000-000000000001','e0910000-0000-0000-0000-000000000001','d0910000-0000-0000-0000-000000000001','mapping-1','Synthetic'),
 ('a0910000-0000-0000-0000-000000000001','e0910000-0000-0000-0000-000000000002','d0910000-0000-0000-0000-000000000001','mapping-2','Synthetic'),
 ('a0910000-0000-0000-0000-000000000002','e0910000-0000-0000-0000-000000000003','d0910000-0000-0000-0000-000000000002','mapping-1','Synthetic');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a0910000-0000-0000-0000-000000000001','c0910000-0000-0000-0000-000000000001','external-a','synthetic-adapter'),
 ('a0910000-0000-0000-0000-000000000001','c0910000-0000-0000-0000-000000000002','external-b','synthetic-adapter'),
 ('a0910000-0000-0000-0000-000000000002','c0910000-0000-0000-0000-000000000003','external-a','synthetic-adapter');
DO $$
DECLARE a uuid:='a0910000-0000-0000-0000-000000000001'; b uuid:='a0910000-0000-0000-0000-000000000002';
 ca uuid:='c0910000-0000-0000-0000-000000000001'; ca2 uuid:='c0910000-0000-0000-0000-000000000002'; cb uuid:='c0910000-0000-0000-0000-000000000003';
 va uuid:='e0910000-0000-0000-0000-000000000001'; va2 uuid:='e0910000-0000-0000-0000-000000000002'; vb uuid:='e0910000-0000-0000-0000-000000000003';
 eid uuid:='f0910000-0000-0000-0000-000000000001'; eid2 uuid:='f0910000-0000-0000-0000-000000000002';
 rel regclass:='ops.external_variant_mappings'::regclass; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events AS e WHERE tenant_id IN(a,b);
 INSERT INTO ops.external_variant_mappings(tenant_id,connection_id,external_variant_id,variant_id) VALUES(a,ca,eid,va),(a,ca2,eid,va),(b,cb,eid,vb),(a,ca,eid2,va);
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,ca,eid,va);
  RAISE EXCEPTION 'FAIL duplicate mapping'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,ca,eid,va2);
  RAISE EXCEPTION 'FAIL conflicting target'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,cb,gen_random_uuid(),va);
  RAISE EXCEPTION 'FAIL cross-tenant connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,ca,gen_random_uuid(),vb);
  RAISE EXCEPTION 'FAIL cross-tenant variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,ca,gen_random_uuid(),gen_random_uuid());
  RAISE EXCEPTION 'FAIL nonexistent variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(a,ca,gen_random_uuid(),va2);
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM ops.external_variant_mappings WHERE tenant_id IN(a,b))<>4
 OR (SELECT count(*) FROM catalog.variants WHERE tenant_id IN(a,b))<>3
 OR (SELECT count(*) FROM catalog.products WHERE tenant_id IN(a,b))<>2
 OR (SELECT count(*) FROM ops.external_variant_mappings WHERE tenant_id=a AND variant_id=va)<>3
 OR EXISTS(SELECT 1 FROM catalog.price_entries WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id IN(a,b))
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) FROM ops.outbox_events AS e WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or automatic catalog/event effect'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) r(role_name)
 WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_map_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0910000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM ops.external_variant_mappings; RAISE EXCEPTION 'FAIL direct mapping read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA ops TO upc_map_a,upc_map_b,upc_map_unmapped,upc_map_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.external_variant_mappings TO upc_map_a,upc_map_b,upc_map_unmapped,upc_map_platform;
SET SESSION AUTHORIZATION upc_map_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.external_variant_mappings) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.external_variant_mappings VALUES(iam.current_tenant_id(),'c0910000-0000-0000-0000-000000000001',gen_random_uuid(),'e0910000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.external_variant_mappings SET recorded_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.external_variant_mappings; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_map_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.external_variant_mappings) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_map_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.external_variant_mappings) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_map_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM ops.external_variant_mappings) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant external variant mapping: canonical references, scoped uniqueness, conflict and tenant FK denial, rollback, deny-all RLS and no automatic catalog effect

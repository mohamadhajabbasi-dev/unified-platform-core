\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0980000-0000-0000-0000-000000000001','map-test-a','Synthetic A'),
 ('a0980000-0000-0000-0000-000000000002','map-test-b','Synthetic B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0980000-0000-0000-0000-000000000001','d0980000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0980000-0000-0000-0000-000000000002','d0980000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0980000-0000-0000-0000-000000000001','e0980000-0000-0000-0000-000000000001','d0980000-0000-0000-0000-000000000001','map-1','Synthetic'),
 ('a0980000-0000-0000-0000-000000000001','e0980000-0000-0000-0000-000000000002','d0980000-0000-0000-0000-000000000001','map-2','Synthetic'),
 ('a0980000-0000-0000-0000-000000000002','e0980000-0000-0000-0000-000000000003','d0980000-0000-0000-0000-000000000002','map-1','Synthetic');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a0980000-0000-0000-0000-000000000001','c0980000-0000-0000-0000-000000000001','one','synthetic'),
 ('a0980000-0000-0000-0000-000000000001','c0980000-0000-0000-0000-000000000002','two','synthetic'),
 ('a0980000-0000-0000-0000-000000000002','c0980000-0000-0000-0000-000000000003','one','synthetic');

DO $$
DECLARE a uuid:='a0980000-0000-0000-0000-000000000001'; b uuid:='a0980000-0000-0000-0000-000000000002';
 c1 uuid:='c0980000-0000-0000-0000-000000000001'; c2 uuid:='c0980000-0000-0000-0000-000000000002'; cb uuid:='c0980000-0000-0000-0000-000000000003';
 v1 uuid:='e0980000-0000-0000-0000-000000000001'; v2 uuid:='e0980000-0000-0000-0000-000000000002'; vb uuid:='e0980000-0000-0000-0000-000000000003';
 e1 uuid:='f0980000-0000-0000-0000-000000000001'; e2 uuid:='f0980000-0000-0000-0000-000000000002'; stamp timestamptz; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events e WHERE tenant_id IN(a,b);
 IF ops.record_synthetic_external_variant_mapping(a,c1,e1,v1) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL first insert'; END IF;
 SELECT recorded_at INTO STRICT stamp FROM ops.external_variant_mappings WHERE tenant_id=a AND connection_id=c1 AND external_variant_id=e1;
 IF ops.record_synthetic_external_variant_mapping(a,c1,e1,v1) IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL replay'; END IF;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,e1,v2); RAISE EXCEPTION 'FAIL conflicting target'; EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT recorded_at FROM ops.external_variant_mappings WHERE tenant_id=a AND connection_id=c1 AND external_variant_id=e1) IS DISTINCT FROM stamp
 OR (SELECT variant_id FROM ops.external_variant_mappings WHERE tenant_id=a AND connection_id=c1 AND external_variant_id=e1) IS DISTINCT FROM v1 THEN RAISE EXCEPTION 'FAIL mapping changed'; END IF;
 IF ops.record_synthetic_external_variant_mapping(a,c2,e1,v2) IS DISTINCT FROM true OR ops.record_synthetic_external_variant_mapping(b,cb,e1,vb) IS DISTINCT FROM true
 OR ops.record_synthetic_external_variant_mapping(a,c1,e2,v1) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL scoped independence or allowed many-to-one'; END IF;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,gen_random_uuid(),v2); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,cb,gen_random_uuid(),v1); RAISE EXCEPTION 'FAIL foreign connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,gen_random_uuid(),vb); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'FAIL missing variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,gen_random_uuid(),gen_random_uuid(),v1); RAISE EXCEPTION 'FAIL missing connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(NULL,c1,e1,v1); RAISE EXCEPTION 'FAIL null tenant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,NULL,e1,v1); RAISE EXCEPTION 'FAIL null connection'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,NULL,v1); RAISE EXCEPTION 'FAIL null external identity'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(a,c1,e1,NULL); RAISE EXCEPTION 'FAIL null variant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF (SELECT count(*) FROM ops.external_variant_mappings WHERE tenant_id IN(a,b))<>4
 OR (SELECT count(*) FROM catalog.products WHERE tenant_id IN(a,b))<>2
 OR (SELECT count(*) FROM catalog.variants WHERE tenant_id IN(a,b))<>3
 OR EXISTS(SELECT 1 FROM catalog.price_entries WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id IN(a,b))
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) FROM ops.outbox_events e WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_outbox_capture']) AS roles(r) WHERE has_function_privilege(r,'ops.record_synthetic_external_variant_mapping(uuid,uuid,uuid,uuid)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.record_synthetic_external_variant_mapping(uuid,uuid,uuid,uuid)'::regprocedure AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL catalog effect, mapping count or ACL'; END IF;
END $$;
CREATE ROLE upc_mapping_probe_098 LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA ops TO upc_mapping_probe_098;
SET SESSION AUTHORIZATION upc_mapping_probe_098;
DO $$ BEGIN
 BEGIN PERFORM ops.record_synthetic_external_variant_mapping(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid());
 RAISE EXCEPTION 'FAIL public execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS synthetic external variant mapping: exact replay, conflict rejection, stable timestamp, scoped FK, rollback, no catalog mutation or runtime grant

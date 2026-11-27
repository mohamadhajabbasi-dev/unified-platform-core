\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0970000-0000-0000-0000-000000000001','inbound-test-a','Synthetic A'),
 ('a0970000-0000-0000-0000-000000000002','inbound-test-b','Synthetic B');
INSERT INTO ops.integration_connections(tenant_id,connection_id,connection_key,adapter_key) VALUES
 ('a0970000-0000-0000-0000-000000000001','c0970000-0000-0000-0000-000000000001','one','synthetic'),
 ('a0970000-0000-0000-0000-000000000001','c0970000-0000-0000-0000-000000000002','two','synthetic'),
 ('a0970000-0000-0000-0000-000000000002','c0970000-0000-0000-0000-000000000003','one','synthetic');
DO $$
DECLARE a uuid:='a0970000-0000-0000-0000-000000000001'; b uuid:='a0970000-0000-0000-0000-000000000002';
 c1 uuid:='c0970000-0000-0000-0000-000000000001'; c2 uuid:='c0970000-0000-0000-0000-000000000002'; cb uuid:='c0970000-0000-0000-0000-000000000003';
 e1 uuid:='d0970000-0000-0000-0000-000000000001'; e2 uuid:='d0970000-0000-0000-0000-000000000002'; stamp timestamptz; before_connections jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(c) ORDER BY c.tenant_id,c.connection_id) INTO before_connections FROM ops.integration_connections c;
 IF ops.record_synthetic_inbound_identity(a,c1,e1) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL initial insert'; END IF;
 SELECT recorded_at INTO STRICT stamp FROM ops.inbound_inbox WHERE tenant_id=a AND connection_id=c1 AND source_event_id=e1;
 IF ops.record_synthetic_inbound_identity(a,c1,e1) IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL exact replay'; END IF;
 IF (SELECT recorded_at FROM ops.inbound_inbox WHERE tenant_id=a AND connection_id=c1 AND source_event_id=e1) IS DISTINCT FROM stamp
 THEN RAISE EXCEPTION 'FAIL stable timestamp'; END IF;
 IF ops.record_synthetic_inbound_identity(a,c2,e1) IS DISTINCT FROM true OR ops.record_synthetic_inbound_identity(b,cb,e1) IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'FAIL independent scope'; END IF;
 BEGIN
  IF ops.record_synthetic_inbound_identity(a,c1,e2) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL distinct event'; END IF;
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF EXISTS(SELECT 1 FROM ops.inbound_inbox WHERE tenant_id=a AND connection_id=c1 AND source_event_id=e2) THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
 BEGIN PERFORM ops.record_synthetic_inbound_identity(a,cb,e1); RAISE EXCEPTION 'FAIL foreign connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_inbound_identity(a,gen_random_uuid(),e1); RAISE EXCEPTION 'FAIL unknown connection'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_inbound_identity(NULL,c1,e1); RAISE EXCEPTION 'FAIL null tenant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_inbound_identity(a,NULL,e1); RAISE EXCEPTION 'FAIL null connection'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_inbound_identity(a,c1,NULL); RAISE EXCEPTION 'FAIL null event'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF (SELECT count(*) FROM ops.inbound_inbox WHERE tenant_id IN(a,b))<>3
 OR before_connections IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.tenant_id,c.connection_id) FROM ops.integration_connections c)
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM catalog.products WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_outbox_capture']) AS roles(r) WHERE has_function_privilege(r,'ops.record_synthetic_inbound_identity(uuid,uuid,uuid)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.record_synthetic_inbound_identity(uuid,uuid,uuid)'::regprocedure AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL domain effect, inbox count or ACL'; END IF;
END $$;
CREATE ROLE upc_inbound_probe_097 LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA ops TO upc_inbound_probe_097;
SET SESSION AUTHORIZATION upc_inbound_probe_097;
DO $$ BEGIN
 BEGIN PERFORM ops.record_synthetic_inbound_identity('a0970000-0000-0000-0000-000000000001','c0970000-0000-0000-0000-000000000001',gen_random_uuid());
 RAISE EXCEPTION 'FAIL public execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS synthetic inbound identity: scoped replay, unchanged timestamp, independent tenants and connections, rollback, composite FK and no domain effect or runtime grant

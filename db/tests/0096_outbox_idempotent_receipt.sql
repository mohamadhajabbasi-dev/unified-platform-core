\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0960000-0000-0000-0000-000000000001','receipt-test-a','Synthetic A'),
 ('a0960000-0000-0000-0000-000000000002','receipt-test-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a0960000-0000-0000-0000-000000000001','d0960000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0960000-0000-0000-0000-000000000002','d0960000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a0960000-0000-0000-0000-000000000001','c0960000-0000-0000-0000-000000000001','one'),
 ('a0960000-0000-0000-0000-000000000001','c0960000-0000-0000-0000-000000000002','two'),
 ('a0960000-0000-0000-0000-000000000002','c0960000-0000-0000-0000-000000000003','one');
DO $$
DECLARE a uuid:='a0960000-0000-0000-0000-000000000001'; b uuid:='a0960000-0000-0000-0000-000000000002';
 c1 uuid:='c0960000-0000-0000-0000-000000000001'; c2 uuid:='c0960000-0000-0000-0000-000000000002'; cb uuid:='c0960000-0000-0000-0000-000000000003';
 e1 uuid; eb uuid; stamp timestamptz; before_events jsonb;
BEGIN
 SELECT event_id INTO STRICT e1 FROM ops.outbox_events WHERE tenant_id=a;
 SELECT event_id INTO STRICT eb FROM ops.outbox_events WHERE tenant_id=b;
 SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) INTO before_events FROM ops.outbox_events e;
 IF ops.record_synthetic_outbox_receipt(a,c1,e1) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL initial insert'; END IF;
 SELECT recorded_at INTO STRICT stamp FROM ops.outbox_consumer_receipts WHERE tenant_id=a AND consumer_id=c1 AND event_id=e1;
 IF ops.record_synthetic_outbox_receipt(a,c1,e1) IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL exact replay'; END IF;
 IF (SELECT recorded_at FROM ops.outbox_consumer_receipts WHERE tenant_id=a AND consumer_id=c1 AND event_id=e1) IS DISTINCT FROM stamp
 OR EXISTS(SELECT 1 FROM ops.pending_outbox_events(a,c1,1))
 OR (SELECT event_id FROM ops.pending_outbox_events(a,c2,1)) IS DISTINCT FROM e1
 OR (SELECT event_id FROM ops.pending_outbox_events(b,cb,1)) IS DISTINCT FROM eb
 THEN RAISE EXCEPTION 'FAIL stable receipt or independent scope'; END IF;
 BEGIN
  IF ops.record_synthetic_outbox_receipt(a,c2,e1) IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL second consumer'; END IF;
  IF EXISTS(SELECT 1 FROM ops.pending_outbox_events(a,c2,1)) THEN RAISE EXCEPTION 'FAIL in transaction receipt'; END IF;
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT event_id FROM ops.pending_outbox_events(a,c2,1)) IS DISTINCT FROM e1 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,cb,e1); RAISE EXCEPTION 'FAIL foreign consumer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,c1,eb); RAISE EXCEPTION 'FAIL foreign event'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,gen_random_uuid(),e1); RAISE EXCEPTION 'FAIL unknown consumer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,c1,gen_random_uuid()); RAISE EXCEPTION 'FAIL unknown event'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(NULL,c1,e1); RAISE EXCEPTION 'FAIL null tenant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,NULL,e1); RAISE EXCEPTION 'FAIL null consumer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.record_synthetic_outbox_receipt(a,c1,NULL); RAISE EXCEPTION 'FAIL null event'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF (SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))<>1
 OR before_events IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) FROM ops.outbox_events e)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_outbox_capture']) AS roles(r) WHERE has_function_privilege(r,'ops.record_synthetic_outbox_receipt(uuid,uuid,uuid)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.record_synthetic_outbox_receipt(uuid,uuid,uuid)'::regprocedure AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL event mutation, receipt count or ACL'; END IF;
END $$;
CREATE ROLE upc_receipt_probe_096 LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA ops TO upc_receipt_probe_096;
SET SESSION AUTHORIZATION upc_receipt_probe_096;
DO $$ BEGIN
 BEGIN PERFORM ops.record_synthetic_outbox_receipt('a0960000-0000-0000-0000-000000000001','c0960000-0000-0000-0000-000000000001',gen_random_uuid());
 RAISE EXCEPTION 'FAIL public execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS synthetic receipt registration: exact replay, unchanged timestamp, independent consumers, rollback, composite FK rejection and no runtime grant

\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0950000-0000-0000-0000-000000000001','pending-a','Synthetic A'),
 ('a0950000-0000-0000-0000-000000000002','pending-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a0950000-0000-0000-0000-000000000001','d0950000-0000-0000-0000-000000000001','Synthetic A1'),
 ('a0950000-0000-0000-0000-000000000001','d0950000-0000-0000-0000-000000000002','Synthetic A2'),
 ('a0950000-0000-0000-0000-000000000002','d0950000-0000-0000-0000-000000000003','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a0950000-0000-0000-0000-000000000001','c0950000-0000-0000-0000-000000000001','one'),
 ('a0950000-0000-0000-0000-000000000001','c0950000-0000-0000-0000-000000000002','two'),
 ('a0950000-0000-0000-0000-000000000002','c0950000-0000-0000-0000-000000000003','one');
DO $$
DECLARE a uuid:='a0950000-0000-0000-0000-000000000001'; b uuid:='a0950000-0000-0000-0000-000000000002';
 c1 uuid:='c0950000-0000-0000-0000-000000000001'; c2 uuid:='c0950000-0000-0000-0000-000000000002'; cb uuid:='c0950000-0000-0000-0000-000000000003';
 e1 uuid; e2 uuid; before_events jsonb; after_events jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) INTO before_events FROM ops.outbox_events e;
 SELECT p.event_id INTO STRICT e1 FROM ops.pending_outbox_events(a,c1,1) p;
 IF e1 IS DISTINCT FROM (SELECT e.event_id FROM ops.outbox_events e WHERE e.tenant_id=a ORDER BY e.recorded_at,e.event_id LIMIT 1)
 OR (SELECT count(*) FROM ops.pending_outbox_events(a,c1,500))<>2
 OR (SELECT count(*) FROM ops.pending_outbox_events(b,cb,500))<>1
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL bounded, ordered or read-only enumeration'; END IF;
 INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,c1,e1);
 SELECT p.event_id INTO STRICT e2 FROM ops.pending_outbox_events(a,c1,500) p;
 IF e1=e2 OR (SELECT count(*) FROM ops.pending_outbox_events(a,c2,500))<>2
 OR (SELECT event_id FROM ops.pending_outbox_events(a,c1,1)) IS DISTINCT FROM e2
 THEN RAISE EXCEPTION 'FAIL independent consumer or repeat enumeration'; END IF;
 BEGIN INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(a,c1,e2);
  IF EXISTS(SELECT 1 FROM ops.pending_outbox_events(a,c1,500)) THEN RAISE EXCEPTION 'FAIL in-transaction receipt visibility'; END IF;
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT event_id FROM ops.pending_outbox_events(a,c1,1)) IS DISTINCT FROM e2 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(a,cb,1); RAISE EXCEPTION 'FAIL foreign consumer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(a,gen_random_uuid(),1); RAISE EXCEPTION 'FAIL unknown consumer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(a,c1,0); RAISE EXCEPTION 'FAIL zero limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(a,c1,501); RAISE EXCEPTION 'FAIL excessive limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(a,c1,NULL); RAISE EXCEPTION 'FAIL null limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.pending_outbox_events(NULL,c1,1); RAISE EXCEPTION 'FAIL null scope'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) INTO after_events FROM ops.outbox_events e;
 IF before_events IS DISTINCT FROM after_events OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_outbox_capture']) AS roles(r)
 WHERE has_function_privilege(r,'ops.pending_outbox_events(uuid,uuid,integer)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.pending_outbox_events(uuid,uuid,integer)'::regprocedure AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL event mutation or function ACL'; END IF;
END $$;
CREATE ROLE upc_pending_probe LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA ops TO upc_pending_probe;
SET SESSION AUTHORIZATION upc_pending_probe;
DO $$ BEGIN
 BEGIN PERFORM 1 FROM ops.pending_outbox_events('a0950000-0000-0000-0000-000000000001','c0950000-0000-0000-0000-000000000001',1);
  RAISE EXCEPTION 'FAIL public execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS pending outbox enumeration: bounded batches, deterministic sort, independent consumers, rollback, scope and no runtime grant

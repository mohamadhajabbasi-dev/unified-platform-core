\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1060000-0000-0000-0000-000000000001','ready-a','Synthetic A'),
 ('a1060000-0000-0000-0000-000000000002','ready-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1060000-0000-0000-0000-000000000001','d1060000-0000-0000-0000-000000000001','Synthetic A1'),
 ('a1060000-0000-0000-0000-000000000001','d1060000-0000-0000-0000-000000000002','Synthetic A2'),
 ('a1060000-0000-0000-0000-000000000001','d1060000-0000-0000-0000-000000000003','Synthetic A3'),
 ('a1060000-0000-0000-0000-000000000002','d1060000-0000-0000-0000-000000000004','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1060000-0000-0000-0000-000000000001','c1060000-0000-0000-0000-000000000001','one'),
 ('a1060000-0000-0000-0000-000000000001','c1060000-0000-0000-0000-000000000002','two'),
 ('a1060000-0000-0000-0000-000000000002','c1060000-0000-0000-0000-000000000001','one');
DO $$
DECLARE a uuid:='a1060000-0000-0000-0000-000000000001'; b uuid:='a1060000-0000-0000-0000-000000000002';
 c uuid:='c1060000-0000-0000-0000-000000000001'; c2 uuid:='c1060000-0000-0000-0000-000000000002';
 ids uuid[]; t uuid; before_events jsonb; before_claims jsonb; before_receipts jsonb;
BEGIN
 SELECT array_agg(e.event_id ORDER BY e.recorded_at,e.event_id) INTO ids FROM ops.outbox_events e WHERE e.tenant_id=a;
 IF cardinality(ids)<>3 THEN RAISE EXCEPTION 'FAIL fixtures'; END IF;
 IF (SELECT event_id FROM ops.ready_synthetic_outbox_events(a,c,1)) IS DISTINCT FROM ids[1] THEN RAISE EXCEPTION 'FAIL first event'; END IF;
 t:=ops.claim_synthetic_outbox_event(a,c,ids[1],120);
 IF t IS NULL THEN RAISE EXCEPTION 'FAIL active fixture'; END IF;
 IF (SELECT event_id FROM ops.ready_synthetic_outbox_events(a,c,1)) IS DISTINCT FROM ids[2] THEN RAISE EXCEPTION 'FAIL active head starvation'; END IF;
 t:=ops.claim_synthetic_outbox_event(a,c,ids[2],120);
 IF t IS NULL OR NOT ops.fail_synthetic_outbox_claim(a,c,ids[2],t,120) THEN RAISE EXCEPTION 'FAIL cooldown fixture'; END IF;
 IF (SELECT event_id FROM ops.ready_synthetic_outbox_events(a,c,1)) IS DISTINCT FROM ids[3]
 OR (SELECT event_id FROM ops.pending_outbox_events(a,c,1)) IS DISTINCT FROM ids[1]
 OR (SELECT count(*) FROM ops.ready_synthetic_outbox_events(a,c2,500))<>3
 OR (SELECT count(*) FROM ops.ready_synthetic_outbox_events(b,c,500))<>1
 THEN RAISE EXCEPTION 'FAIL cooldown head starvation, old enumeration or scope'; END IF;
 IF NOT ops.record_synthetic_outbox_receipt(a,c,ids[3]) THEN RAISE EXCEPTION 'FAIL receipt fixture'; END IF;
 IF EXISTS(SELECT 1 FROM ops.ready_synthetic_outbox_events(a,c,500)) THEN RAISE EXCEPTION 'FAIL receipt exclusion'; END IF;
 -- Only fixture owner simulates past expiry; actual clock recovery is tested in the worker job.
 UPDATE ops.outbox_claims SET expires_at=statement_timestamp()-interval '2 seconds'
 WHERE tenant_id=a AND consumer_id=c AND event_id=ids[1];
 UPDATE ops.outbox_claims SET expires_at=statement_timestamp()-interval '2 seconds',retry_not_before=statement_timestamp()-interval '1 second'
 WHERE tenant_id=a AND consumer_id=c AND event_id=ids[2];
 SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) INTO before_events FROM ops.outbox_events e;
 SELECT jsonb_agg(to_jsonb(l) ORDER BY l.tenant_id,l.consumer_id,l.event_id) INTO before_claims FROM ops.outbox_claims l;
 SELECT jsonb_agg(to_jsonb(q) ORDER BY q.tenant_id,q.consumer_id,q.event_id) INTO before_receipts FROM ops.outbox_consumer_receipts q;
 IF (SELECT array_agg(event_id ORDER BY recorded_at,event_id) FROM ops.ready_synthetic_outbox_events(a,c,500)) IS DISTINCT FROM ids[1:2] THEN RAISE EXCEPTION 'FAIL expired readiness'; END IF;
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events(b,c2,1); RAISE EXCEPTION 'FAIL foreign consumer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events(a,c,0); RAISE EXCEPTION 'FAIL zero limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events(a,c,501); RAISE EXCEPTION 'FAIL excessive limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events(a,c,NULL); RAISE EXCEPTION 'FAIL null limit'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events(NULL,c,1); RAISE EXCEPTION 'FAIL null scope'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF before_events IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY e.tenant_id,e.event_id) FROM ops.outbox_events e)
 OR before_claims IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(l) ORDER BY l.tenant_id,l.consumer_id,l.event_id) FROM ops.outbox_claims l)
 OR before_receipts IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(q) ORDER BY q.tenant_id,q.consumer_id,q.event_id) FROM ops.outbox_consumer_receipts q)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_outbox_capture']) AS roles(r)
 WHERE has_function_privilege(r,'ops.ready_synthetic_outbox_events(uuid,uuid,integer)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.ready_synthetic_outbox_events(uuid,uuid,integer)'::regprocedure AND (prosecdef OR provolatile<>'s'))
 THEN RAISE EXCEPTION 'FAIL mutation or ACL'; END IF;
END $$;
CREATE ROLE upc_ready_probe LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA ops TO upc_ready_probe;
SET SESSION AUTHORIZATION upc_ready_probe;
DO $$ BEGIN
 BEGIN PERFORM 1 FROM ops.ready_synthetic_outbox_events('a1060000-0000-0000-0000-000000000001','c1060000-0000-0000-0000-000000000001',1);
 RAISE EXCEPTION 'FAIL public execute'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS ready synthetic outbox selection: active/cooling exclusion before LIMIT, expired eligibility, scoped receipt, no mutation or grant

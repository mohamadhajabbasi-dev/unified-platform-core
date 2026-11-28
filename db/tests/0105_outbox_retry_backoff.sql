\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1050000-0000-0000-0000-000000000001','retry-a','Synthetic A'),
 ('a1050000-0000-0000-0000-000000000002','retry-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1050000-0000-0000-0000-000000000001','d1050000-0000-0000-0000-000000000001','Synthetic A'),
 ('a1050000-0000-0000-0000-000000000002','d1050000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1050000-0000-0000-0000-000000000001','c1050000-0000-0000-0000-000000000001','one'),
 ('a1050000-0000-0000-0000-000000000001','c1050000-0000-0000-0000-000000000002','two'),
 ('a1050000-0000-0000-0000-000000000002','c1050000-0000-0000-0000-000000000001','one');
DO $$
DECLARE a uuid:='a1050000-0000-0000-0000-000000000001'; b uuid:='a1050000-0000-0000-0000-000000000002';
 c uuid:='c1050000-0000-0000-0000-000000000001'; c2 uuid:='c1050000-0000-0000-0000-000000000002';
 e uuid; eb uuid; t uuid; t2 uuid; t3 uuid; tb uuid; before_row jsonb; failed_row jsonb; prior jsonb;
BEGIN
 SELECT event_id INTO STRICT e FROM ops.outbox_events WHERE tenant_id=a;
 SELECT event_id INTO STRICT eb FROM ops.outbox_events WHERE tenant_id=b;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events x;
 t:=ops.claim_synthetic_outbox_event(a,c,e,120);
 IF t IS NULL OR (SELECT attempt_count FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c AND event_id=e)<>1 THEN RAISE EXCEPTION 'FAIL initial claim'; END IF;
 SELECT to_jsonb(l) INTO before_row FROM ops.outbox_claims l WHERE tenant_id=a AND consumer_id=c AND event_id=e;
 BEGIN PERFORM ops.fail_synthetic_outbox_claim(a,c,e,t,0); RAISE EXCEPTION 'FAIL zero delay'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.fail_synthetic_outbox_claim(a,c,e,t,301); RAISE EXCEPTION 'FAIL excessive delay'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.fail_synthetic_outbox_claim(a,c,e,t,NULL); RAISE EXCEPTION 'FAIL null delay'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.fail_synthetic_outbox_claim(a,c,e,NULL,1); RAISE EXCEPTION 'FAIL null token'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 IF ops.fail_synthetic_outbox_claim(b,c,eb,t,1) OR ops.fail_synthetic_outbox_claim(a,c,e,gen_random_uuid(),1) THEN RAISE EXCEPTION 'FAIL cross scope or wrong token'; END IF;
 BEGIN
  IF NOT ops.fail_synthetic_outbox_claim(a,c,e,t,60) THEN RAISE EXCEPTION 'FAIL failure rollback fixture'; END IF;
  RAISE EXCEPTION 'fixture rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF before_row IS DISTINCT FROM (SELECT to_jsonb(l) FROM ops.outbox_claims l WHERE tenant_id=a AND consumer_id=c AND event_id=e) THEN RAISE EXCEPTION 'FAIL failure rollback'; END IF;
 IF NOT ops.fail_synthetic_outbox_claim(a,c,e,t,1) THEN RAISE EXCEPTION 'FAIL explicit failure'; END IF;
 SELECT to_jsonb(l) INTO failed_row FROM ops.outbox_claims l WHERE tenant_id=a AND consumer_id=c AND event_id=e;
 IF ops.fail_synthetic_outbox_claim(a,c,e,t,120) OR ops.complete_synthetic_outbox_claim(a,c,e,t)
 OR ops.claim_synthetic_outbox_event(a,c,e,120) IS NOT NULL
 OR failed_row IS DISTINCT FROM (SELECT to_jsonb(l) FROM ops.outbox_claims l WHERE tenant_id=a AND consumer_id=c AND event_id=e)
 OR NOT EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c AND event_id=e AND attempt_count=1 AND lease_token<>t AND retry_not_before>expires_at)
 OR EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id=a AND consumer_id=c AND event_id=e)
 THEN RAISE EXCEPTION 'FAIL cooldown, replay, stale token or receipt'; END IF;
 tb:=ops.claim_synthetic_outbox_event(b,c,eb,120);
 t2:=ops.claim_synthetic_outbox_event(a,c2,e,1);
 IF tb IS NULL OR t2 IS NULL THEN RAISE EXCEPTION 'FAIL independent scopes'; END IF;
 PERFORM pg_sleep(1.2);
 IF ops.fail_synthetic_outbox_claim(a,c2,e,t2,1) THEN RAISE EXCEPTION 'FAIL expired failure'; END IF;
 t3:=ops.claim_synthetic_outbox_event(a,c2,e,120);
 IF t3 IS NULL OR t3=t2 OR NOT EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c2 AND event_id=e AND attempt_count=2 AND retry_not_before IS NULL) THEN RAISE EXCEPTION 'FAIL expiry reclaim count'; END IF;
 BEGIN
  IF ops.claim_synthetic_outbox_event(a,c,e,120) IS NULL THEN RAISE EXCEPTION 'FAIL reclaim rollback fixture'; END IF;
  RAISE EXCEPTION 'fixture rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF failed_row IS DISTINCT FROM (SELECT to_jsonb(l) FROM ops.outbox_claims l WHERE tenant_id=a AND consumer_id=c AND event_id=e) THEN RAISE EXCEPTION 'FAIL reclaim rollback'; END IF;
 t2:=ops.claim_synthetic_outbox_event(a,c,e,120);
 IF t2 IS NULL OR t2=t OR ops.claim_synthetic_outbox_event(a,c,e,120) IS NOT NULL OR ops.fail_synthetic_outbox_claim(a,c,e,t,1)
 OR NOT EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c AND event_id=e AND attempt_count=2 AND retry_not_before IS NULL)
 THEN RAISE EXCEPTION 'FAIL reclaim count or old token'; END IF;
 IF NOT ops.complete_synthetic_outbox_claim(a,c,e,t2) THEN RAISE EXCEPTION 'FAIL completion after retry'; END IF;
 IF ops.complete_synthetic_outbox_claim(a,c,e,t2) OR ops.fail_synthetic_outbox_claim(a,c,e,t2,1) OR ops.claim_synthetic_outbox_event(a,c,e,120) IS NOT NULL THEN RAISE EXCEPTION 'FAIL completed replay'; END IF;
 IF NOT ops.record_synthetic_outbox_receipt(a,c2,e) THEN RAISE EXCEPTION 'FAIL historical receipt fixture'; END IF;
 IF ops.fail_synthetic_outbox_claim(a,c2,e,t3,1) THEN RAISE EXCEPTION 'FAIL existing receipt failure'; END IF;
 IF (SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id=a)<>2
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY tenant_id,event_id) FROM ops.outbox_events x)
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.outbox_claims'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='ops.outbox_claims'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r)
 WHERE has_table_privilege(r,'ops.outbox_claims','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 OR has_function_privilege(r,'ops.fail_synthetic_outbox_claim(uuid,uuid,uuid,uuid,integer)','EXECUTE')
 OR has_function_privilege(r,'ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer)','EXECUTE')
 OR has_function_privilege(r,'ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('ops.fail_synthetic_outbox_claim(uuid,uuid,uuid,uuid,integer)'::regprocedure,'ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer)'::regprocedure,'ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid)'::regprocedure) AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL facts or ACL/RLS'; END IF;
END $$;
CREATE ROLE upc_retry_probe LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_retry_probe;
GRANT USAGE ON SCHEMA ops TO upc_retry_probe;
SET SESSION AUTHORIZATION upc_retry_probe;
DO $$ BEGIN
 BEGIN PERFORM ops.fail_synthetic_outbox_claim(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),1); RAISE EXCEPTION 'FAIL public failure'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.outbox_claims TO upc_retry_probe;
SET SESSION AUTHORIZATION upc_retry_probe;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.outbox_claims) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 UPDATE ops.outbox_claims SET retry_not_before=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.outbox_claims; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS synthetic outbox retry: bounded cooldown, failure fence, acquisition count, rollback, receipt exclusion, independent scopes and default deny

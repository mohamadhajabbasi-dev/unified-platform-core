\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a1040000-0000-0000-0000-000000000001','claim-a','Synthetic A'),
 ('a1040000-0000-0000-0000-000000000002','claim-b','Synthetic B');
INSERT INTO catalog.brands(tenant_id,brand_id,name) VALUES
 ('a1040000-0000-0000-0000-000000000001','d1040000-0000-0000-0000-000000000001','Synthetic A'),
 ('a1040000-0000-0000-0000-000000000002','d1040000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO ops.outbox_consumers(tenant_id,consumer_id,consumer_key) VALUES
 ('a1040000-0000-0000-0000-000000000001','c1040000-0000-0000-0000-000000000001','one'),
 ('a1040000-0000-0000-0000-000000000001','c1040000-0000-0000-0000-000000000002','two'),
 ('a1040000-0000-0000-0000-000000000002','c1040000-0000-0000-0000-000000000001','one');
DO $$
DECLARE a uuid:='a1040000-0000-0000-0000-000000000001'; b uuid:='a1040000-0000-0000-0000-000000000002';
 c uuid:='c1040000-0000-0000-0000-000000000001'; c2 uuid:='c1040000-0000-0000-0000-000000000002';
 e uuid; eb uuid; t uuid; t2 uuid; tb uuid; old uuid; prior jsonb;
BEGIN
 SELECT event_id INTO STRICT e FROM ops.outbox_events WHERE tenant_id=a;
 SELECT event_id INTO STRICT eb FROM ops.outbox_events WHERE tenant_id=b;
 SELECT jsonb_agg(to_jsonb(x) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events x;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(a,c,eb,30); RAISE EXCEPTION 'FAIL cross-tenant event'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(b,c2,eb,30); RAISE EXCEPTION 'FAIL cross-tenant consumer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(a,c,e,0); RAISE EXCEPTION 'FAIL zero duration'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(a,c,e,301); RAISE EXCEPTION 'FAIL long duration'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(a,c,e,NULL); RAISE EXCEPTION 'FAIL null duration'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(NULL,c,e,1); RAISE EXCEPTION 'FAIL null scope'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM ops.complete_synthetic_outbox_claim(a,c,e,NULL); RAISE EXCEPTION 'FAIL null token'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN
  IF ops.claim_synthetic_outbox_event(a,c,e,30) IS NULL THEN RAISE EXCEPTION 'FAIL first rollback claim'; END IF;
  RAISE EXCEPTION 'fixture rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a) THEN RAISE EXCEPTION 'FAIL rollback claim'; END IF;
 old:=ops.claim_synthetic_outbox_event(a,c,e,1);
 IF old IS NULL THEN RAISE EXCEPTION 'FAIL first lease'; END IF;
 PERFORM pg_sleep(1.2);
 IF ops.complete_synthetic_outbox_claim(a,c,e,old) THEN RAISE EXCEPTION 'FAIL expired completion'; END IF;
 t:=ops.claim_synthetic_outbox_event(a,c,e,60);
 IF t IS NULL OR t=old OR ops.claim_synthetic_outbox_event(a,c,e,60) IS NOT NULL
 OR ops.complete_synthetic_outbox_claim(a,c,e,old) OR ops.complete_synthetic_outbox_claim(b,c,eb,t)
 THEN RAISE EXCEPTION 'FAIL reclaim, active or stale scope'; END IF;
 t2:=ops.claim_synthetic_outbox_event(a,c2,e,60);
 tb:=ops.claim_synthetic_outbox_event(b,c,eb,60);
 IF t2 IS NULL OR tb IS NULL OR t=t2 OR t=tb THEN RAISE EXCEPTION 'FAIL independent scope'; END IF;
 BEGIN
  IF NOT ops.complete_synthetic_outbox_claim(a,c,e,t) THEN RAISE EXCEPTION 'FAIL completion'; END IF;
  RAISE EXCEPTION 'fixture rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts WHERE tenant_id=a AND consumer_id=c AND event_id=e)
 OR NOT EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c AND event_id=e AND lease_token=t)
 THEN RAISE EXCEPTION 'FAIL completion rollback'; END IF;
 IF NOT ops.complete_synthetic_outbox_claim(a,c,e,t) THEN RAISE EXCEPTION 'FAIL completion after rollback'; END IF;
 IF ops.complete_synthetic_outbox_claim(a,c,e,t) OR ops.claim_synthetic_outbox_event(a,c,e,60) IS NOT NULL
 OR EXISTS(SELECT 1 FROM ops.outbox_claims WHERE tenant_id=a AND consumer_id=c AND event_id=e)
 THEN RAISE EXCEPTION 'FAIL replay or receipt exclusion'; END IF;
 -- Historical isolated receipt API remains intact, but is not a fenced worker API.
 IF NOT ops.record_synthetic_outbox_receipt(a,c2,e) THEN RAISE EXCEPTION 'FAIL historical receipt'; END IF;
 IF ops.complete_synthetic_outbox_claim(a,c2,e,t2) THEN RAISE EXCEPTION 'FAIL duplicate receipt conflict'; END IF;
 IF (SELECT count(*) FROM ops.outbox_consumer_receipts WHERE tenant_id=a)<>2
 OR (SELECT count(*) FROM ops.outbox_claims WHERE tenant_id IN(a,b))<>1
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY tenant_id,event_id) FROM ops.outbox_events x)
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.outbox_claims'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='ops.outbox_claims'::regclass)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_outbox_capture']) AS roles(r)
 WHERE has_table_privilege(r,'ops.outbox_claims','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 OR has_function_privilege(r,'ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer)','EXECUTE')
 OR has_function_privilege(r,'ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid)','EXECUTE'))
 OR EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer)'::regprocedure,'ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid)'::regprocedure) AND prosecdef)
 THEN RAISE EXCEPTION 'FAIL receipt count, source mutation or ACL/RLS'; END IF;
END $$;
CREATE ROLE upc_claim_probe LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_claim_probe;
GRANT USAGE ON SCHEMA ops TO upc_claim_probe;
SET SESSION AUTHORIZATION upc_claim_probe;
DO $$ BEGIN
 BEGIN PERFORM 1 FROM ops.outbox_claims; RAISE EXCEPTION 'FAIL public table read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.claim_synthetic_outbox_event(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),30); RAISE EXCEPTION 'FAIL public claim'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM ops.complete_synthetic_outbox_claim(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()); RAISE EXCEPTION 'FAIL public completion'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT SELECT,INSERT,UPDATE,DELETE ON ops.outbox_claims TO upc_claim_probe;
SET SESSION AUTHORIZATION upc_claim_probe;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM ops.outbox_claims) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO ops.outbox_claims VALUES(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),clock_timestamp()); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE ops.outbox_claims SET expires_at=clock_timestamp(); IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM ops.outbox_claims; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS synthetic outbox claims: expiry/reclaim, stale fence, rollback, independent scope, receipt replay and deny-all RLS

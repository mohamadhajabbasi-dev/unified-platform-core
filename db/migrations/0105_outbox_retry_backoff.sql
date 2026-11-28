-- 0105: isolated explicit failure and bounded retry; same canonical claim row.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
ALTER TABLE ops.outbox_claims
 ADD COLUMN attempt_count bigint NOT NULL DEFAULT 1 CHECK(attempt_count>0),
 ADD COLUMN retry_not_before timestamptz CHECK(retry_not_before IS NULL OR isfinite(retry_not_before)),
 ADD CONSTRAINT outbox_claims_retry_after_expiry CHECK(retry_not_before IS NULL OR retry_not_before>=expires_at);
CREATE OR REPLACE FUNCTION ops.claim_synthetic_outbox_event(p_tenant uuid,p_consumer uuid,p_event uuid,p_seconds integer)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE created boolean; expiry timestamptz; retry_at timestamptz; token uuid;
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_event IS NULL OR p_seconds IS NULL OR p_seconds NOT BETWEEN 1 AND 300 THEN
  RAISE EXCEPTION 'Invalid claim arguments' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ops.outbox_consumers c WHERE c.tenant_id=p_tenant AND c.consumer_id=p_consumer)
 OR NOT EXISTS(SELECT 1 FROM ops.outbox_events e WHERE e.tenant_id=p_tenant AND e.event_id=p_event) THEN
  RAISE EXCEPTION 'Unknown consumer or event in scope' USING ERRCODE='22023';
 END IF;
 IF EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a WHERE a.tenant_id=p_tenant AND a.consumer_id=p_consumer AND a.event_id=p_event) THEN RETURN NULL; END IF;
 -- The unique tuple serializes conflicting inserts; expiration is evaluated only after row lock.
 INSERT INTO ops.outbox_claims(tenant_id,consumer_id,event_id,lease_token,expires_at)
 VALUES(p_tenant,p_consumer,p_event,gen_random_uuid(),clock_timestamp())
 ON CONFLICT(tenant_id,consumer_id,event_id) DO NOTHING;
 created:=FOUND;
 SELECT l.expires_at,l.retry_not_before INTO expiry,retry_at FROM ops.outbox_claims l
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a WHERE a.tenant_id=p_tenant AND a.consumer_id=p_consumer AND a.event_id=p_event) THEN
  IF created THEN DELETE FROM ops.outbox_claims l WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event; END IF;
  RETURN NULL;
 END IF;
 IF NOT created AND (expiry>clock_timestamp() OR retry_at>clock_timestamp()) THEN RETURN NULL; END IF;
 token:=gen_random_uuid();
 UPDATE ops.outbox_claims l SET lease_token=token,expires_at=clock_timestamp()+make_interval(secs=>p_seconds),
 retry_not_before=NULL,attempt_count=l.attempt_count+CASE WHEN created THEN 0 ELSE 1 END
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event;
 RETURN token;
END $$;
CREATE OR REPLACE FUNCTION ops.complete_synthetic_outbox_claim(p_tenant uuid,p_consumer uuid,p_event uuid,p_token uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE current_token uuid; expiry timestamptz; retry_at timestamptz; inserted boolean;
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_event IS NULL OR p_token IS NULL THEN
  RAISE EXCEPTION 'Invalid completion arguments' USING ERRCODE='22023';
 END IF;
 SELECT l.lease_token,l.expires_at,l.retry_not_before INTO current_token,expiry,retry_at FROM ops.outbox_claims l
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event FOR UPDATE;
 IF NOT FOUND OR current_token IS DISTINCT FROM p_token OR expiry<=clock_timestamp() OR retry_at IS NOT NULL THEN RETURN false; END IF;
 INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(p_tenant,p_consumer,p_event)
 ON CONFLICT(tenant_id,consumer_id,event_id) DO NOTHING;
 inserted:=FOUND;
 DELETE FROM ops.outbox_claims l WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event;
 RETURN inserted;
END $$;

CREATE FUNCTION ops.fail_synthetic_outbox_claim(p_tenant uuid,p_consumer uuid,p_event uuid,p_token uuid,p_delay_seconds integer)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE current_token uuid; expiry timestamptz; retry_at timestamptz; failed_at timestamptz;
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_event IS NULL OR p_token IS NULL OR p_delay_seconds IS NULL OR p_delay_seconds NOT BETWEEN 1 AND 300 THEN
  RAISE EXCEPTION 'Invalid failure arguments' USING ERRCODE='22023';
 END IF;
 SELECT l.lease_token,l.expires_at,l.retry_not_before INTO current_token,expiry,retry_at FROM ops.outbox_claims l
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event FOR UPDATE;
 failed_at:=clock_timestamp();
 IF NOT FOUND OR current_token IS DISTINCT FROM p_token OR expiry<=failed_at OR retry_at IS NOT NULL THEN RETURN false; END IF;
 IF EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a WHERE a.tenant_id=p_tenant AND a.consumer_id=p_consumer AND a.event_id=p_event) THEN RETURN false; END IF;
 UPDATE ops.outbox_claims l SET lease_token=gen_random_uuid(),expires_at=failed_at,
 retry_not_before=failed_at+make_interval(secs=>p_delay_seconds)
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION ops.fail_synthetic_outbox_claim(uuid,uuid,uuid,uuid,integer) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON COLUMN ops.outbox_claims.attempt_count IS 'Outstanding acquisitions, not lifetime history. Pre-0105 current claims initialize to known lower bound 1. Removed on synthetic completion.';
COMMENT ON COLUMN ops.outbox_claims.retry_not_before IS 'Explicit synthetic failure cooldown; NULL for normal active or expired lease. Not production retry policy.';
COMMENT ON FUNCTION ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer) IS 'Synthetic privileged claim; NULL if not acquired. Cooldown and lease checked under row lock, count advances only on acquisition/reclaim. Token usable after commit; no commit-time validity guarantee.';
COMMENT ON FUNCTION ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid) IS 'Atomic synthetic receipt and claim removal; false includes failed/stale/expired token, replay or missing claim. No business effect, no commit-time validity guarantee.';
COMMENT ON FUNCTION ops.fail_synthetic_outbox_claim(uuid,uuid,uuid,uuid,integer) IS 'Synthetic explicit failure; true only once per valid current token, rotate fence and expire lease, delay 1–300 seconds; no receipt or external effect. No terminal policy.';
COMMIT;

-- 0104: isolated transactional claim and fenced synthetic completion; no external worker.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE ops.outbox_claims (
 tenant_id uuid NOT NULL,
 consumer_id uuid NOT NULL,
 event_id uuid NOT NULL,
 lease_token uuid NOT NULL,
 expires_at timestamptz NOT NULL,
 PRIMARY KEY(tenant_id,consumer_id,event_id),
 FOREIGN KEY(tenant_id,consumer_id) REFERENCES ops.outbox_consumers(tenant_id,consumer_id),
 FOREIGN KEY(tenant_id,event_id) REFERENCES ops.outbox_events(tenant_id,event_id),
 CHECK(isfinite(expires_at))
);
CREATE INDEX outbox_claims_event_idx ON ops.outbox_claims(tenant_id,event_id);
ALTER TABLE ops.outbox_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_claims FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.outbox_claims FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
CREATE FUNCTION ops.claim_synthetic_outbox_event(p_tenant uuid,p_consumer uuid,p_event uuid,p_seconds integer)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE created boolean; expiry timestamptz; token uuid;
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
 SELECT l.expires_at INTO expiry FROM ops.outbox_claims l
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a WHERE a.tenant_id=p_tenant AND a.consumer_id=p_consumer AND a.event_id=p_event) THEN
  IF created THEN DELETE FROM ops.outbox_claims l WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event; END IF;
  RETURN NULL;
 END IF;
 IF NOT created AND expiry>clock_timestamp() THEN RETURN NULL; END IF;
 token:=gen_random_uuid();
 UPDATE ops.outbox_claims l SET lease_token=token,expires_at=clock_timestamp()+make_interval(secs=>p_seconds)
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event;
 RETURN token;
END $$;
CREATE FUNCTION ops.complete_synthetic_outbox_claim(p_tenant uuid,p_consumer uuid,p_event uuid,p_token uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE current_token uuid; expiry timestamptz; inserted boolean;
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_event IS NULL OR p_token IS NULL THEN
  RAISE EXCEPTION 'Invalid completion arguments' USING ERRCODE='22023';
 END IF;
 SELECT l.lease_token,l.expires_at INTO current_token,expiry FROM ops.outbox_claims l
 WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event FOR UPDATE;
 IF NOT FOUND OR current_token IS DISTINCT FROM p_token OR expiry<=clock_timestamp() THEN RETURN false; END IF;
 INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id) VALUES(p_tenant,p_consumer,p_event)
 ON CONFLICT(tenant_id,consumer_id,event_id) DO NOTHING;
 inserted:=FOUND;
 DELETE FROM ops.outbox_claims l WHERE l.tenant_id=p_tenant AND l.consumer_id=p_consumer AND l.event_id=p_event;
 RETURN inserted;
END $$;
REVOKE ALL ON FUNCTION ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer),ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE ops.outbox_claims IS 'Current transient claim only, not a second event or receipt. Default-deny synthetic prototype; no retention or operational worker policy.';
COMMENT ON FUNCTION ops.claim_synthetic_outbox_event(uuid,uuid,uuid,integer) IS 'Synthetic privileged claim; NULL means not acquired. Lease duration 1–300 seconds, checked after lock; token only usable after commit, expiration can occur before commit. No delivery or exactly-once guarantee.';
COMMENT ON FUNCTION ops.complete_synthetic_outbox_claim(uuid,uuid,uuid,uuid) IS 'Synthetic receipt insertion and claim removal are atomic. False includes replay, stale/expired token, missing claim or already existing receipt; no business effect. Expiration is validated at locked check, not at COMMIT.';
COMMIT;

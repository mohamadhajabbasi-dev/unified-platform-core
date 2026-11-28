-- 0106: advisory eligibility for an isolated synthetic worker, no new queue or table.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE FUNCTION ops.ready_synthetic_outbox_events(p_tenant uuid,p_consumer uuid,p_limit integer)
RETURNS TABLE(event_id uuid,event_kind text,recorded_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
  RAISE EXCEPTION 'Invalid ready enumeration arguments' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ops.outbox_consumers c WHERE c.tenant_id=p_tenant AND c.consumer_id=p_consumer) THEN
  RAISE EXCEPTION 'Unknown consumer in scope' USING ERRCODE='22023';
 END IF;
 RETURN QUERY SELECT e.event_id,e.event_kind,e.recorded_at
 FROM ops.outbox_events e WHERE e.tenant_id=p_tenant
 AND NOT EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a
 WHERE a.tenant_id=e.tenant_id AND a.consumer_id=p_consumer AND a.event_id=e.event_id)
 AND NOT EXISTS(SELECT 1 FROM ops.outbox_claims l
 WHERE l.tenant_id=e.tenant_id AND l.consumer_id=p_consumer AND l.event_id=e.event_id
 AND (l.expires_at>statement_timestamp() OR l.retry_not_before>statement_timestamp()))
 ORDER BY e.recorded_at,e.event_id LIMIT p_limit;
END $$;
REVOKE ALL ON FUNCTION ops.ready_synthetic_outbox_events(uuid,uuid,integer) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON FUNCTION ops.ready_synthetic_outbox_events(uuid,uuid,integer) IS 'Read-only advisory statement-time snapshot; excludes active leases and cooldowns before LIMIT. Claim must revalidate under lock; not commit order, authorization, delivery or a throughput guarantee.';
COMMIT;

-- 0095: isolated read-only pending enumeration; no delivery authority.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE FUNCTION ops.pending_outbox_events(p_tenant uuid,p_consumer uuid,p_limit integer)
RETURNS TABLE(event_id uuid,event_kind text,recorded_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
  RAISE EXCEPTION 'Invalid pending enumeration arguments' USING ERRCODE='22023';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ops.outbox_consumers c WHERE c.tenant_id=p_tenant AND c.consumer_id=p_consumer) THEN
  RAISE EXCEPTION 'Unknown consumer in scope' USING ERRCODE='22023';
 END IF;
 RETURN QUERY SELECT e.event_id,e.event_kind,e.recorded_at
 FROM ops.outbox_events e WHERE e.tenant_id=p_tenant
 AND NOT EXISTS(SELECT 1 FROM ops.outbox_consumer_receipts a
  WHERE a.tenant_id=e.tenant_id AND a.consumer_id=p_consumer AND a.event_id=e.event_id)
 ORDER BY e.recorded_at,e.event_id LIMIT p_limit;
END $$;
REVOKE ALL ON FUNCTION ops.pending_outbox_events(uuid,uuid,integer) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON FUNCTION ops.pending_outbox_events(uuid,uuid,integer) IS 'Isolated privileged read-only prototype. No runtime grants, lease, delivery or ack authority. Sort is not commit order; never use as high-water cursor. Receipt remains synthetic metadata.';
COMMIT;

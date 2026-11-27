-- 0096: isolated synthetic receipt registration; not proof of delivery.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE FUNCTION ops.record_synthetic_outbox_receipt(p_tenant uuid,p_consumer uuid,p_event uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF p_tenant IS NULL OR p_consumer IS NULL OR p_event IS NULL THEN
  RAISE EXCEPTION 'Invalid receipt arguments' USING ERRCODE='22023';
 END IF;
 INSERT INTO ops.outbox_consumer_receipts(tenant_id,consumer_id,event_id)
 VALUES(p_tenant,p_consumer,p_event)
 ON CONFLICT(tenant_id,consumer_id,event_id) DO NOTHING;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION ops.record_synthetic_outbox_receipt(uuid,uuid,uuid) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON FUNCTION ops.record_synthetic_outbox_receipt(uuid,uuid,uuid) IS 'Isolated privileged prototype: true if inserted, false on exact replay. Existing composite FKs, unique key and RLS unchanged. No delivery, lease, worker or operational acknowledgement authority; return is transactional, not proof of COMMIT.';
COMMIT;

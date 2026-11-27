-- 0097: isolated synthetic inbound identity registration; not verified provider receipt.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE FUNCTION ops.record_synthetic_inbound_identity(p_tenant uuid,p_connection uuid,p_source_event uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
BEGIN
 IF p_tenant IS NULL OR p_connection IS NULL OR p_source_event IS NULL THEN
  RAISE EXCEPTION 'Invalid inbound identity arguments' USING ERRCODE='22023';
 END IF;
 INSERT INTO ops.inbound_inbox(tenant_id,connection_id,source_event_id)
 VALUES(p_tenant,p_connection,p_source_event)
 ON CONFLICT(tenant_id,connection_id,source_event_id) DO NOTHING;
 RETURN FOUND;
END $$;
REVOKE ALL ON FUNCTION ops.record_synthetic_inbound_identity(uuid,uuid,uuid) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON FUNCTION ops.record_synthetic_inbound_identity(uuid,uuid,uuid) IS 'Isolated privileged prototype: true if inserted, false on exact replay. Composite connection scope and RLS unchanged. No provider trust, payload, domain processing or operational authority. Transactional result is not proof of COMMIT.';
COMMIT;

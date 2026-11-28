-- 0098: isolated synthetic mapping registration; no remapping or provider authority.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE FUNCTION ops.record_synthetic_external_variant_mapping(p_tenant uuid,p_connection uuid,p_external_variant uuid,p_variant uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE existing_variant uuid;
BEGIN
 IF p_tenant IS NULL OR p_connection IS NULL OR p_external_variant IS NULL OR p_variant IS NULL THEN
  RAISE EXCEPTION 'Invalid mapping arguments' USING ERRCODE='22023';
 END IF;
 INSERT INTO ops.external_variant_mappings(tenant_id,connection_id,external_variant_id,variant_id)
 VALUES(p_tenant,p_connection,p_external_variant,p_variant)
 ON CONFLICT(tenant_id,connection_id,external_variant_id) DO NOTHING;
 IF FOUND THEN RETURN true; END IF;
 -- A fresh statement snapshot under READ COMMITTED observes the committed winner.
 -- At stricter isolation a serialization failure is acceptable; never overwrite.
 SELECT m.variant_id INTO existing_variant FROM ops.external_variant_mappings m
 WHERE m.tenant_id=p_tenant AND m.connection_id=p_connection AND m.external_variant_id=p_external_variant;
 IF NOT FOUND THEN RAISE EXCEPTION 'Mapping unavailable after conflict' USING ERRCODE='40001'; END IF;
 IF existing_variant IS DISTINCT FROM p_variant THEN
  RAISE EXCEPTION 'Conflicting canonical variant' USING ERRCODE='23505';
 END IF;
 RETURN false;
END $$;
REVOKE ALL ON FUNCTION ops.record_synthetic_external_variant_mapping(uuid,uuid,uuid,uuid) FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON FUNCTION ops.record_synthetic_external_variant_mapping(uuid,uuid,uuid,uuid) IS 'Isolated privileged prototype: true if inserted, false on exact replay; conflicting target rejects. Existing composite FKs and deny-all RLS unchanged. No provider trust, remapping, catalog mutation or operational authority. Transaction result is not proof of COMMIT.';
COMMIT;

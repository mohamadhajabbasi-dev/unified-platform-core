-- 0003: enforce existing IAM and module decisions on CRM, no new master tables.
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('crm.read','Read customer records'),('crm.write','Resolve and link verified customer identities');
INSERT INTO platform.modules(module_key,version_label) VALUES ('crm','0.1');
GRANT USAGE ON SCHEMA platform TO upc_crm_executor;
GRANT EXECUTE ON FUNCTION iam.has_permission(text),platform.module_enabled(text) TO upc_crm_executor;

-- Existing tenant_scope remains mandatory. Restrictive policies AND with it.
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['crm.customers'::regclass,'crm.customer_identifiers'::regclass,'crm.customer_addresses'::regclass]
 LOOP
  EXECUTE format('CREATE POLICY crm_read_gate ON %s AS RESTRICTIVE FOR SELECT TO upc_runtime USING (iam.has_permission(''crm.read'') AND platform.module_enabled(''crm''))',rel);
  EXECUTE format('CREATE POLICY crm_executor_gate ON %s AS RESTRICTIVE FOR ALL TO upc_crm_executor USING (iam.has_permission(''crm.write'') AND platform.module_enabled(''crm'')) WITH CHECK (iam.has_permission(''crm.write'') AND platform.module_enabled(''crm''))',rel);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION crm.resolve_verified_customer(
  p_kind text, p_issuer text, p_value text, p_display_name text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_tenant uuid := iam.current_tenant_id();
  v_customer uuid;
BEGIN
  IF v_tenant IS NULL OR NOT iam.has_permission('crm.write') OR NOT platform.module_enabled('crm') THEN
    RAISE EXCEPTION 'CRM write permission and enabled module required' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL OR p_issuer IS NULL OR p_value IS NULL
      OR p_display_name IS NULL OR btrim(p_display_name) = ''
      OR p_value = '' OR btrim(p_value) <> p_value THEN
    RAISE EXCEPTION 'invalid verified identity input' USING ERRCODE = '22023';
  END IF;
  -- Serialize same canonical identity. A hash collision only serializes unrelated work.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    jsonb_build_array(v_tenant,p_kind,p_issuer,p_value)::text,0));
  SELECT customer_id INTO v_customer
    FROM crm.customer_identifiers
    WHERE tenant_id = v_tenant AND kind = p_kind AND issuer = p_issuer
      AND normalized_value = p_value AND verified_at IS NOT NULL AND revoked_at IS NULL;
  IF FOUND THEN RETURN v_customer; END IF;
  INSERT INTO crm.customers(tenant_id,display_name)
    VALUES (v_tenant,p_display_name) RETURNING customer_id INTO v_customer;
  INSERT INTO crm.customer_identifiers(tenant_id,customer_id,kind,issuer,normalized_value,verified_at)
    VALUES (v_tenant,v_customer,p_kind,p_issuer,p_value,now());
  RETURN v_customer;
END $$;

-- The verifier may attach another independently verified identity to an
-- already identified customer. Conflicting ownership is rejected, never merged.
CREATE FUNCTION crm.link_verified_identity(p_customer uuid,p_kind text,p_issuer text,p_value text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE v_tenant uuid := iam.current_tenant_id(); v_existing uuid;
BEGIN
 IF v_tenant IS NULL OR NOT iam.has_permission('crm.write') OR NOT platform.module_enabled('crm') THEN
  RAISE EXCEPTION 'CRM write permission and enabled module required' USING ERRCODE='42501';
 END IF;
 IF p_customer IS NULL OR p_kind IS NULL OR p_issuer IS NULL OR p_value IS NULL OR
    p_value='' OR btrim(p_value)<>p_value THEN
  RAISE EXCEPTION 'Invalid verified identity input' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array(v_tenant,p_kind,p_issuer,p_value)::text,0));
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=v_tenant AND customer_id=p_customer) THEN
  RAISE EXCEPTION 'Customer unavailable in current tenant' USING ERRCODE='23503';
 END IF;
 SELECT customer_id INTO v_existing FROM crm.customer_identifiers
 WHERE tenant_id=v_tenant AND kind=p_kind AND issuer=p_issuer AND normalized_value=p_value
 AND verified_at IS NOT NULL AND revoked_at IS NULL;
 IF FOUND THEN
  IF v_existing<>p_customer THEN RAISE EXCEPTION 'Identity conflict; review required' USING ERRCODE='23505'; END IF;
  RETURN p_customer;
 END IF;
 INSERT INTO crm.customer_identifiers(tenant_id,customer_id,kind,issuer,normalized_value,verified_at)
 VALUES(v_tenant,p_customer,p_kind,p_issuer,p_value,now());
 RETURN p_customer;
END $$;
ALTER FUNCTION crm.link_verified_identity(uuid,text,text,text) OWNER TO upc_crm_executor;
REVOKE ALL ON FUNCTION crm.link_verified_identity(uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.link_verified_identity(uuid,text,text,text) TO upc_identity_writer;
COMMIT;

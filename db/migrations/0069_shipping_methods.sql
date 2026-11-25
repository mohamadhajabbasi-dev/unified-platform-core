-- 0069: dormant tenant shipping method identity; no delivery rates, dispatch or order mutation.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('sales.shipping.write','Register dormant shipping method identity');
CREATE ROLE upc_shipping_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE sales.shipping_methods (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 method_id uuid NOT NULL DEFAULT gen_random_uuid(),
 method_key text NOT NULL CHECK(method_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 200 AND display_name ~ '[^[:space:]]' AND display_name !~ '[[:cntrl:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,method_id),
 UNIQUE(tenant_id,method_key)
);
ALTER TABLE sales.shipping_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.shipping_methods FORCE ROW LEVEL SECURITY;
REVOKE ALL ON sales.shipping_methods FROM PUBLIC;
CREATE POLICY shipping_runtime_read ON sales.shipping_methods FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('sales.read') AND platform.module_enabled('sales'));
CREATE POLICY shipping_executor_read ON sales.shipping_methods FOR SELECT TO upc_shipping_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('sales.read') AND iam.has_permission('sales.shipping.write') AND platform.module_enabled('sales'));
CREATE POLICY shipping_executor_insert ON sales.shipping_methods FOR INSERT TO upc_shipping_executor
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('sales.read') AND iam.has_permission('sales.shipping.write') AND platform.module_enabled('sales'));
GRANT USAGE ON SCHEMA sales,iam,platform TO upc_shipping_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_shipping_executor;
GRANT SELECT ON sales.shipping_methods TO upc_runtime,upc_shipping_executor;
GRANT INSERT(tenant_id,method_key,display_name) ON sales.shipping_methods TO upc_shipping_executor;
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid
 WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='categories' THEN (j->>'category_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_barcodes' THEN (j->>'barcode_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='attribute_definitions' THEN (j->>'attribute_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_attribute_values' THEN (j->>'assignment_id')::uuid
 WHEN TG_TABLE_SCHEMA='inventory' AND TG_TABLE_NAME='reorder_policies' THEN (j->>'policy_id')::uuid
 WHEN TG_TABLE_SCHEMA='sales' AND TG_TABLE_NAME='shipping_methods' THEN (j->>'method_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;

CREATE TRIGGER shipping_method_audit AFTER INSERT ON sales.shipping_methods
 FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION sales.register_shipping_method(p_key text,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior sales.shipping_methods%ROWTYPE; mid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('sales.read') OR NOT iam.has_permission('sales.shipping.write') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Shipping method registration denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed'
 THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 200 OR p_name !~ '[^[:space:]]' OR p_name ~ '[[:cntrl:]]'
 THEN RAISE EXCEPTION 'Invalid shipping method identity' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-shipping-method',t,p_key)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR NOT iam.has_permission('sales.read') OR NOT iam.has_permission('sales.shipping.write') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Shipping method registration denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM sales.shipping_methods WHERE tenant_id=t AND method_key=p_key;
 IF FOUND THEN
  IF prior.display_name IS DISTINCT FROM p_name THEN RAISE EXCEPTION 'Shipping method key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.method_id;
 END IF;
 INSERT INTO sales.shipping_methods(tenant_id,method_key,display_name) VALUES(t,p_key,p_name) RETURNING method_id INTO mid;
 RETURN mid;
END $$;
ALTER FUNCTION sales.register_shipping_method(text,text) OWNER TO upc_shipping_executor;
REVOKE ALL ON FUNCTION sales.register_shipping_method(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION sales.register_shipping_method(text,text) TO upc_runtime;
COMMIT;

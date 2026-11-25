-- 0066: alternate barcode metadata for canonical variants, not a product master.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_barcode_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE catalog.variant_barcodes (
 tenant_id uuid NOT NULL,
 barcode_id uuid NOT NULL DEFAULT gen_random_uuid(),
 variant_id uuid NOT NULL,
 barcode_code text COLLATE "C" NOT NULL CHECK(barcode_code COLLATE "C" ~ '^[!-~]{1,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,barcode_id),
 UNIQUE(tenant_id,barcode_code),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE INDEX variant_barcodes_variant_idx ON catalog.variant_barcodes(tenant_id,variant_id);
ALTER TABLE catalog.variant_barcodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.variant_barcodes FORCE ROW LEVEL SECURITY;
REVOKE ALL ON catalog.variant_barcodes FROM PUBLIC;
CREATE POLICY barcode_read ON catalog.variant_barcodes FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY barcode_executor_read ON catalog.variant_barcodes FOR SELECT TO upc_barcode_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
CREATE POLICY barcode_executor_insert ON catalog.variant_barcodes FOR INSERT TO upc_barcode_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT USAGE ON SCHEMA catalog,iam,platform TO upc_barcode_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_barcode_executor;
GRANT SELECT(tenant_id,variant_id) ON catalog.variants TO upc_barcode_executor;
CREATE POLICY barcode_variant_dependency ON catalog.variants FOR SELECT TO upc_barcode_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT SELECT ON catalog.variant_barcodes TO upc_runtime,upc_barcode_executor;
GRANT INSERT(tenant_id,variant_id,barcode_code) ON catalog.variant_barcodes TO upc_barcode_executor;
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='categories' THEN (j->>'category_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_barcodes' THEN (j->>'barcode_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER variant_barcode_audit AFTER INSERT ON catalog.variant_barcodes FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION catalog.register_variant_barcode(p_variant uuid,p_code text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior catalog.variant_barcodes%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Barcode access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_variant IS NULL OR p_code IS NULL OR p_code COLLATE "C" !~ '^[!-~]{1,128}$' THEN RAISE EXCEPTION 'Invalid barcode metadata' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-variant-barcode',t,p_code)::text,0));
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Barcode access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM catalog.variants WHERE tenant_id=t AND variant_id=p_variant) THEN RAISE EXCEPTION 'Variant unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM catalog.variant_barcodes WHERE tenant_id=t AND barcode_code=p_code COLLATE "C";
 IF FOUND THEN
  IF prior.variant_id IS DISTINCT FROM p_variant THEN RAISE EXCEPTION 'Barcode code conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.barcode_id;
 END IF;
 INSERT INTO catalog.variant_barcodes(tenant_id,variant_id,barcode_code) VALUES(t,p_variant,p_code) RETURNING barcode_id INTO result_id;
 RETURN result_id;
END $$;
ALTER FUNCTION catalog.register_variant_barcode(uuid,text) OWNER TO upc_barcode_executor;
REVOKE ALL ON FUNCTION catalog.register_variant_barcode(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.register_variant_barcode(uuid,text) TO upc_runtime;
COMMIT;

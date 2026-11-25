-- 0067: one tenant definition and one current descriptive value per variant/attribute.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_attribute_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE catalog.attribute_definitions (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 attribute_id uuid NOT NULL DEFAULT gen_random_uuid(),
 attribute_key text COLLATE "C" NOT NULL CHECK(attribute_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 120 AND display_name ~ '[^[:space:]]' AND display_name !~ '[[:cntrl:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,attribute_id),
 UNIQUE(tenant_id,attribute_key)
);
CREATE TABLE catalog.variant_attribute_values (
 tenant_id uuid NOT NULL,
 assignment_id uuid NOT NULL DEFAULT gen_random_uuid(),
 variant_id uuid NOT NULL,
 attribute_id uuid NOT NULL,
 value_text text NOT NULL CHECK(length(value_text) BETWEEN 1 AND 512 AND value_text ~ '[^[:space:]]' AND value_text !~ '[[:cntrl:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,assignment_id),
 UNIQUE(tenant_id,variant_id,attribute_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,attribute_id) REFERENCES catalog.attribute_definitions(tenant_id,attribute_id)
);
CREATE INDEX variant_attribute_values_attribute_idx ON catalog.variant_attribute_values(tenant_id,attribute_id,variant_id);
ALTER TABLE catalog.attribute_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.attribute_definitions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON catalog.attribute_definitions FROM PUBLIC;
CREATE POLICY attribute_read ON catalog.attribute_definitions FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY attribute_executor_read ON catalog.attribute_definitions FOR SELECT TO upc_attribute_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
CREATE POLICY attribute_executor_insert ON catalog.attribute_definitions FOR INSERT TO upc_attribute_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT SELECT ON catalog.attribute_definitions TO upc_runtime,upc_attribute_executor;
ALTER TABLE catalog.variant_attribute_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.variant_attribute_values FORCE ROW LEVEL SECURITY;
REVOKE ALL ON catalog.variant_attribute_values FROM PUBLIC;
CREATE POLICY attribute_read ON catalog.variant_attribute_values FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY attribute_executor_read ON catalog.variant_attribute_values FOR SELECT TO upc_attribute_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
CREATE POLICY attribute_executor_insert ON catalog.variant_attribute_values FOR INSERT TO upc_attribute_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT SELECT ON catalog.variant_attribute_values TO upc_runtime,upc_attribute_executor;
CREATE POLICY attribute_executor_update ON catalog.variant_attribute_values FOR UPDATE TO upc_attribute_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write')) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT USAGE ON SCHEMA catalog,iam,platform TO upc_attribute_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_attribute_executor;
GRANT SELECT(tenant_id,variant_id) ON catalog.variants TO upc_attribute_executor;
CREATE POLICY attribute_variant_dependency ON catalog.variants FOR SELECT TO upc_attribute_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.write'));
GRANT INSERT(tenant_id,attribute_key,display_name) ON catalog.attribute_definitions TO upc_attribute_executor;
GRANT INSERT(tenant_id,variant_id,attribute_id,value_text) ON catalog.variant_attribute_values TO upc_attribute_executor;
GRANT UPDATE(value_text,changed_at) ON catalog.variant_attribute_values TO upc_attribute_executor;
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='categories' THEN (j->>'category_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_barcodes' THEN (j->>'barcode_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='attribute_definitions' THEN (j->>'attribute_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_attribute_values' THEN (j->>'assignment_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER attribute_definition_audit AFTER INSERT ON catalog.attribute_definitions FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE TRIGGER variant_attribute_value_insert_audit AFTER INSERT ON catalog.variant_attribute_values FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE TRIGGER variant_attribute_value_update_audit AFTER UPDATE OF value_text ON catalog.variant_attribute_values FOR EACH ROW WHEN (OLD.value_text COLLATE "C" IS DISTINCT FROM NEW.value_text COLLATE "C") EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION catalog.register_attribute_definition(p_key text,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior catalog.attribute_definitions%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Attribute access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key COLLATE "C" !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 120 OR p_name !~ '[^[:space:]]' OR p_name ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'Invalid attribute definition' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-attribute-definition',t,p_key)::text,0));
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Attribute access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM catalog.attribute_definitions WHERE tenant_id=t AND attribute_key=p_key COLLATE "C";
 IF FOUND THEN
  IF prior.display_name COLLATE "C" IS DISTINCT FROM p_name COLLATE "C" THEN RAISE EXCEPTION 'Attribute key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.attribute_id;
 END IF;
 INSERT INTO catalog.attribute_definitions(tenant_id,attribute_key,display_name) VALUES(t,p_key,p_name) RETURNING attribute_id INTO result_id;
 RETURN result_id;
END $$;
CREATE FUNCTION catalog.set_variant_attribute_value(p_variant uuid,p_attribute uuid,p_value text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior catalog.variant_attribute_values%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Attribute access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_variant IS NULL OR p_attribute IS NULL OR p_value IS NULL OR length(p_value) NOT BETWEEN 1 AND 512 OR p_value !~ '[^[:space:]]' OR p_value ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'Invalid attribute assignment' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-variant-attribute',t,p_variant,p_attribute)::text,0));
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Attribute access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM catalog.variants WHERE tenant_id=t AND variant_id=p_variant) OR NOT EXISTS(SELECT 1 FROM catalog.attribute_definitions WHERE tenant_id=t AND attribute_id=p_attribute) THEN RAISE EXCEPTION 'Variant or attribute unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM catalog.variant_attribute_values WHERE tenant_id=t AND variant_id=p_variant AND attribute_id=p_attribute;
 IF FOUND THEN
  IF prior.value_text COLLATE "C" IS DISTINCT FROM p_value COLLATE "C" THEN
   UPDATE catalog.variant_attribute_values SET value_text=p_value,changed_at=clock_timestamp() WHERE tenant_id=t AND assignment_id=prior.assignment_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Attribute update denied' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN prior.assignment_id;
 END IF;
 INSERT INTO catalog.variant_attribute_values(tenant_id,variant_id,attribute_id,value_text) VALUES(t,p_variant,p_attribute,p_value) RETURNING assignment_id INTO result_id;
 RETURN result_id;
END $$;
ALTER FUNCTION catalog.register_attribute_definition(text,text) OWNER TO upc_attribute_executor;
ALTER FUNCTION catalog.set_variant_attribute_value(uuid,uuid,text) OWNER TO upc_attribute_executor;
REVOKE ALL ON FUNCTION catalog.register_attribute_definition(text,text),catalog.set_variant_attribute_value(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.register_attribute_definition(text,text),catalog.set_variant_attribute_value(uuid,uuid,text) TO upc_runtime;
COMMIT;

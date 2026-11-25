-- 0065: single-parent hierarchy on the existing canonical categories.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
ALTER TABLE catalog.categories ADD COLUMN parent_category_id uuid,
 ADD FOREIGN KEY(tenant_id,parent_category_id) REFERENCES catalog.categories(tenant_id,category_id),
 ADD CHECK(parent_category_id IS DISTINCT FROM category_id);
CREATE INDEX categories_parent_idx ON catalog.categories(tenant_id,parent_category_id) WHERE parent_category_id IS NOT NULL;
REVOKE INSERT ON catalog.categories FROM upc_runtime;
GRANT INSERT(tenant_id,category_id,name,is_active) ON catalog.categories TO upc_runtime;
CREATE ROLE upc_category_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA catalog,iam,platform TO upc_category_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_category_executor;
GRANT SELECT(tenant_id,category_id,parent_category_id),UPDATE(parent_category_id) ON catalog.categories TO upc_category_executor;
CREATE POLICY category_tree_read ON catalog.categories FOR SELECT TO upc_category_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND iam.has_permission('catalog.write') AND platform.module_enabled('catalog'));
CREATE POLICY category_tree_update ON catalog.categories FOR UPDATE TO upc_category_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND iam.has_permission('catalog.write') AND platform.module_enabled('catalog')) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read') AND iam.has_permission('catalog.write') AND platform.module_enabled('catalog'));
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='categories' THEN (j->>'category_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER category_parent_audit AFTER UPDATE OF parent_category_id ON catalog.categories FOR EACH ROW
 WHEN (OLD.parent_category_id IS DISTINCT FROM NEW.parent_category_id) EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION catalog.set_category_parent(p_child uuid,p_parent uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior uuid; contains_child boolean; reaches_root boolean;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Category access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_child IS NULL THEN RAISE EXCEPTION 'Child required' USING ERRCODE='22023'; END IF;
 -- Every runtime graph mutation serializes on the same tenant key, before reading edges.
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-category-tree',t)::text,0));
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.write') OR NOT platform.module_enabled('catalog') THEN RAISE EXCEPTION 'Category access denied' USING ERRCODE='42501'; END IF;
 SELECT parent_category_id INTO prior FROM catalog.categories WHERE tenant_id=t AND category_id=p_child;
 IF NOT FOUND THEN RAISE EXCEPTION 'Category unavailable' USING ERRCODE='23503'; END IF;
 IF p_parent IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM catalog.categories WHERE tenant_id=t AND category_id=p_parent) THEN RAISE EXCEPTION 'Category unavailable' USING ERRCODE='23503'; END IF;
  WITH RECURSIVE ancestors(category_id,parent_category_id) AS (
   SELECT c.category_id,c.parent_category_id FROM catalog.categories c WHERE c.tenant_id=t AND c.category_id=p_parent
   UNION
   SELECT c.category_id,c.parent_category_id FROM catalog.categories c JOIN ancestors a ON c.category_id=a.parent_category_id WHERE c.tenant_id=t
  )
  SELECT COALESCE(bool_or(category_id=p_child),false),COALESCE(bool_or(parent_category_id IS NULL),false)
  INTO contains_child,reaches_root FROM ancestors;
  IF contains_child OR NOT reaches_root THEN RAISE EXCEPTION 'Category cycle or invalid ancestry' USING ERRCODE='23514'; END IF;
 END IF;
 IF prior IS DISTINCT FROM p_parent THEN
  UPDATE catalog.categories SET parent_category_id=p_parent WHERE tenant_id=t AND category_id=p_child;
  IF NOT FOUND THEN RAISE EXCEPTION 'Category update denied' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN p_child;
END $$;
ALTER FUNCTION catalog.set_category_parent(uuid,uuid) OWNER TO upc_category_executor;
REVOKE ALL ON FUNCTION catalog.set_category_parent(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.set_category_parent(uuid,uuid) TO upc_runtime;
COMMIT;

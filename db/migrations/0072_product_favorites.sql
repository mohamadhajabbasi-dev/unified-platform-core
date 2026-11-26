-- 0072: internal prototype of customer/product favorite relation, not customer authentication.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('catalog.favorites.read','Read tenant product favorite relationships'),('catalog.favorites.write','Set tenant product favorite relationships');
CREATE ROLE upc_favorite_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE catalog.product_favorites (
 tenant_id uuid NOT NULL,
 favorite_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 product_id uuid NOT NULL,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,favorite_id),
 UNIQUE(tenant_id,customer_id,product_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id)
);
CREATE INDEX product_favorites_product_idx ON catalog.product_favorites(tenant_id,product_id,customer_id);
ALTER TABLE catalog.product_favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.product_favorites FORCE ROW LEVEL SECURITY;
REVOKE ALL ON catalog.product_favorites FROM PUBLIC;
CREATE POLICY favorite_read ON catalog.product_favorites FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read'));
CREATE POLICY favorite_executor_read ON catalog.product_favorites FOR SELECT TO upc_favorite_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write'));
CREATE POLICY favorite_executor_insert ON catalog.product_favorites FOR INSERT TO upc_favorite_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write'));
CREATE POLICY favorite_executor_update ON catalog.product_favorites FOR UPDATE TO upc_favorite_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write')) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write'));
GRANT USAGE ON SCHEMA catalog,crm,iam,platform TO upc_favorite_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_favorite_executor;
GRANT SELECT(tenant_id,customer_id) ON crm.customers TO upc_favorite_executor;
CREATE POLICY favorite_customer_dependency ON crm.customers AS RESTRICTIVE FOR SELECT TO upc_favorite_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write'));
GRANT SELECT(tenant_id,product_id) ON catalog.products TO upc_favorite_executor;
CREATE POLICY favorite_product_dependency ON catalog.products FOR SELECT TO upc_favorite_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('catalog.favorites.read') AND iam.has_permission('catalog.favorites.write'));
GRANT SELECT ON catalog.product_favorites TO upc_runtime,upc_favorite_executor;
GRANT INSERT(tenant_id,customer_id,product_id) ON catalog.product_favorites TO upc_favorite_executor;
GRANT UPDATE(is_active,changed_at) ON catalog.product_favorites TO upc_favorite_executor;
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
 WHEN TG_TABLE_SCHEMA='ops' AND TG_TABLE_NAME='incidents' THEN (j->>'incident_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='product_favorites' THEN (j->>'favorite_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;



CREATE TRIGGER favorite_audit AFTER INSERT OR UPDATE ON catalog.product_favorites FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION catalog.set_product_favorite(p_customer uuid,p_product uuid,p_active boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior catalog.product_favorites%ROWTYPE; fid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR NOT iam.has_permission('catalog.favorites.read') OR NOT iam.has_permission('catalog.favorites.write') THEN RAISE EXCEPTION 'Favorite access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_customer IS NULL OR p_product IS NULL OR p_active IS NULL THEN RAISE EXCEPTION 'Customer, product and state required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-product-favorite',t,p_customer,p_product)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR t IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR NOT iam.has_permission('catalog.favorites.read') OR NOT iam.has_permission('catalog.favorites.write') THEN RAISE EXCEPTION 'Favorite access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=t AND customer_id=p_customer)
 OR NOT EXISTS(SELECT 1 FROM catalog.products WHERE tenant_id=t AND product_id=p_product)
 THEN RAISE EXCEPTION 'Customer or product unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM catalog.product_favorites WHERE tenant_id=t AND customer_id=p_customer AND product_id=p_product;
 IF FOUND THEN
  IF prior.is_active IS DISTINCT FROM p_active THEN
   UPDATE catalog.product_favorites SET is_active=p_active,changed_at=clock_timestamp() WHERE tenant_id=t AND favorite_id=prior.favorite_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Favorite update denied' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN prior.favorite_id;
 END IF;
 IF NOT p_active THEN RETURN NULL; END IF;
 INSERT INTO catalog.product_favorites(tenant_id,customer_id,product_id) VALUES(t,p_customer,p_product) RETURNING favorite_id INTO fid;
 RETURN fid;
END $$;
ALTER FUNCTION catalog.set_product_favorite(uuid,uuid,boolean) OWNER TO upc_favorite_executor;
REVOKE ALL ON FUNCTION catalog.set_product_favorite(uuid,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.set_product_favorite(uuid,uuid,boolean) TO upc_runtime;
COMMIT;

-- 0073: internal dormant restock alert request metadata; no consent or notification authorization.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('catalog.stock_alerts.read','Read tenant stock alert request relationships'),('catalog.stock_alerts.write','Set tenant stock alert request relationships');
CREATE ROLE upc_stock_alert_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE catalog.stock_alert_subscriptions (
 tenant_id uuid NOT NULL,
 subscription_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 is_requested boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,subscription_id),
 UNIQUE(tenant_id,customer_id,variant_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE INDEX stock_alert_subscriptions_variant_idx ON catalog.stock_alert_subscriptions(tenant_id,variant_id,customer_id);
ALTER TABLE catalog.stock_alert_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.stock_alert_subscriptions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON catalog.stock_alert_subscriptions FROM PUBLIC;
CREATE POLICY stock_alert_read ON catalog.stock_alert_subscriptions FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read'));
CREATE POLICY stock_alert_executor_read ON catalog.stock_alert_subscriptions FOR SELECT TO upc_stock_alert_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write'));
CREATE POLICY stock_alert_executor_insert ON catalog.stock_alert_subscriptions FOR INSERT TO upc_stock_alert_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write'));
CREATE POLICY stock_alert_executor_update ON catalog.stock_alert_subscriptions FOR UPDATE TO upc_stock_alert_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write')) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write'));
GRANT USAGE ON SCHEMA catalog,crm,iam,platform TO upc_stock_alert_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_stock_alert_executor;
GRANT SELECT(tenant_id,customer_id) ON crm.customers TO upc_stock_alert_executor;
CREATE POLICY stock_alert_customer_dependency ON crm.customers AS RESTRICTIVE FOR SELECT TO upc_stock_alert_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write'));
GRANT SELECT(tenant_id,variant_id) ON catalog.variants TO upc_stock_alert_executor;
CREATE POLICY stock_alert_variant_dependency ON catalog.variants FOR SELECT TO upc_stock_alert_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog') AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory') AND iam.has_permission('catalog.stock_alerts.read') AND iam.has_permission('catalog.stock_alerts.write'));
GRANT SELECT ON catalog.stock_alert_subscriptions TO upc_runtime,upc_stock_alert_executor;
GRANT INSERT(tenant_id,customer_id,variant_id) ON catalog.stock_alert_subscriptions TO upc_stock_alert_executor;
GRANT UPDATE(is_requested,changed_at) ON catalog.stock_alert_subscriptions TO upc_stock_alert_executor;
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
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='stock_alert_subscriptions' THEN (j->>'subscription_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;



CREATE TRIGGER stock_alert_audit AFTER INSERT OR UPDATE ON catalog.stock_alert_subscriptions FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION catalog.set_stock_alert_request(p_customer uuid,p_variant uuid,p_active boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior catalog.stock_alert_subscriptions%ROWTYPE; fid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory') OR NOT iam.has_permission('catalog.stock_alerts.read') OR NOT iam.has_permission('catalog.stock_alerts.write') THEN RAISE EXCEPTION 'Stock alert request access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_customer IS NULL OR p_variant IS NULL OR p_active IS NULL THEN RAISE EXCEPTION 'Customer, variant and state required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-stock-alert-request',t,p_customer,p_variant)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR t IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory') OR NOT iam.has_permission('catalog.stock_alerts.read') OR NOT iam.has_permission('catalog.stock_alerts.write') THEN RAISE EXCEPTION 'Stock alert request access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=t AND customer_id=p_customer)
 OR NOT EXISTS(SELECT 1 FROM catalog.variants WHERE tenant_id=t AND variant_id=p_variant)
 THEN RAISE EXCEPTION 'Customer or variant unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM catalog.stock_alert_subscriptions WHERE tenant_id=t AND customer_id=p_customer AND variant_id=p_variant;
 IF FOUND THEN
  IF prior.is_requested IS DISTINCT FROM p_active THEN
   UPDATE catalog.stock_alert_subscriptions SET is_requested=p_active,changed_at=clock_timestamp() WHERE tenant_id=t AND subscription_id=prior.subscription_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Stock alert request update denied' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN prior.subscription_id;
 END IF;
 IF NOT p_active THEN RETURN NULL; END IF;
 INSERT INTO catalog.stock_alert_subscriptions(tenant_id,customer_id,variant_id) VALUES(t,p_customer,p_variant) RETURNING subscription_id INTO fid;
 RETURN fid;
END $$;
ALTER FUNCTION catalog.set_stock_alert_request(uuid,uuid,boolean) OWNER TO upc_stock_alert_executor;
REVOKE ALL ON FUNCTION catalog.set_stock_alert_request(uuid,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.set_stock_alert_request(uuid,uuid,boolean) TO upc_runtime;
COMMIT;

-- 0068: dormant reorder configuration only; never post stock or purchase suggestions.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('inventory.reorder.write','Maintain dormant inventory reorder configuration');
CREATE ROLE upc_reorder_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE inventory.reorder_policies (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 policy_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 reorder_point bigint NOT NULL CHECK(reorder_point>=0),
 suggested_units bigint NOT NULL CHECK(suggested_units>0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,policy_id),
 UNIQUE(tenant_id,warehouse_id,variant_id),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE INDEX reorder_policies_variant_idx ON inventory.reorder_policies(tenant_id,variant_id,warehouse_id);
ALTER TABLE inventory.reorder_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.reorder_policies FORCE ROW LEVEL SECURITY;
REVOKE ALL ON inventory.reorder_policies FROM PUBLIC;
CREATE POLICY reorder_runtime_read ON inventory.reorder_policies FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory'));
CREATE POLICY reorder_executor_read ON inventory.reorder_policies FOR SELECT TO upc_reorder_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
CREATE POLICY reorder_executor_insert ON inventory.reorder_policies FOR INSERT TO upc_reorder_executor
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
CREATE POLICY reorder_executor_update ON inventory.reorder_policies FOR UPDATE TO upc_reorder_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
GRANT SELECT ON inventory.reorder_policies TO upc_runtime,upc_reorder_executor;
GRANT INSERT(tenant_id,warehouse_id,variant_id,reorder_point,suggested_units) ON inventory.reorder_policies TO upc_reorder_executor;
GRANT UPDATE(reorder_point,suggested_units,changed_at) ON inventory.reorder_policies TO upc_reorder_executor;
-- The private executor may verify only same-tenant physical variant identity,
-- never read ledger/balances/procurement or access operational write functions.
GRANT USAGE ON SCHEMA inventory,catalog,iam,platform TO upc_reorder_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_reorder_executor;
GRANT SELECT(tenant_id,warehouse_id) ON inventory.warehouses TO upc_reorder_executor;
GRANT SELECT(tenant_id,variant_id,product_id) ON catalog.variants TO upc_reorder_executor;
GRANT SELECT(tenant_id,product_id,kind) ON catalog.products TO upc_reorder_executor;
CREATE POLICY reorder_warehouse_dependency ON inventory.warehouses FOR SELECT TO upc_reorder_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
CREATE POLICY reorder_variant_dependency ON catalog.variants FOR SELECT TO upc_reorder_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
CREATE POLICY reorder_product_dependency ON catalog.products FOR SELECT TO upc_reorder_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.reorder.write') AND platform.module_enabled('inventory'));
-- Extend the existing audit writer, never add a parallel audit table.
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
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER reorder_policy_insert_audit AFTER INSERT ON inventory.reorder_policies
 FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE TRIGGER reorder_policy_update_audit AFTER UPDATE OF reorder_point,suggested_units ON inventory.reorder_policies
 FOR EACH ROW WHEN (OLD.reorder_point IS DISTINCT FROM NEW.reorder_point OR OLD.suggested_units IS DISTINCT FROM NEW.suggested_units)
 EXECUTE FUNCTION ops.record_dossier_change();
-- Technical metadata contract, not an authorization for replenishment.
CREATE FUNCTION inventory.set_reorder_policy(p_warehouse uuid,p_variant uuid,p_point bigint,p_units bigint) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior inventory.reorder_policies%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('inventory.read') OR NOT iam.has_permission('inventory.reorder.write') OR NOT platform.module_enabled('inventory')
 THEN RAISE EXCEPTION 'Reorder configuration denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL OR p_point IS NULL OR p_point<0 OR p_units IS NULL OR p_units<=0
 THEN RAISE EXCEPTION 'Invalid reorder configuration' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-reorder-policy',t,p_warehouse,p_variant)::text,0));
 IF t IS NULL OR NOT iam.has_permission('inventory.read') OR NOT iam.has_permission('inventory.reorder.write') OR NOT platform.module_enabled('inventory')
 THEN RAISE EXCEPTION 'Reorder configuration denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.warehouses WHERE tenant_id=t AND warehouse_id=p_warehouse)
 OR NOT EXISTS(SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
               WHERE v.tenant_id=t AND v.variant_id=p_variant AND p.kind='physical')
 THEN RAISE EXCEPTION 'Warehouse or physical variant unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM inventory.reorder_policies
  WHERE tenant_id=t AND warehouse_id=p_warehouse AND variant_id=p_variant;
 IF FOUND THEN
  IF prior.reorder_point IS DISTINCT FROM p_point OR prior.suggested_units IS DISTINCT FROM p_units THEN
   UPDATE inventory.reorder_policies SET reorder_point=p_point,suggested_units=p_units,changed_at=clock_timestamp()
    WHERE tenant_id=t AND policy_id=prior.policy_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Reorder configuration update denied' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN prior.policy_id;
 END IF;
 INSERT INTO inventory.reorder_policies(tenant_id,warehouse_id,variant_id,reorder_point,suggested_units)
 VALUES(t,p_warehouse,p_variant,p_point,p_units) RETURNING policy_id INTO result_id;
 RETURN result_id;
END $$;
ALTER FUNCTION inventory.set_reorder_policy(uuid,uuid,bigint,bigint) OWNER TO upc_reorder_executor;
REVOKE ALL ON FUNCTION inventory.set_reorder_policy(uuid,uuid,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.set_reorder_policy(uuid,uuid,bigint,bigint) TO upc_runtime;
COMMIT;

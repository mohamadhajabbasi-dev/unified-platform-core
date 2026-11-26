-- 0077: dormant immutable proposed SLA target definitions; no ticket assignment, clock or enforcement.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('crm.sla.read','Read proposed SLA target definitions'),('crm.sla.write','Register proposed SLA target definitions');
CREATE ROLE upc_sla_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE crm.sla_policies (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 policy_id uuid NOT NULL DEFAULT gen_random_uuid(),
 policy_key text NOT NULL CHECK(policy_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 response_minutes integer NOT NULL CHECK(response_minutes>0),
 resolution_minutes integer NOT NULL CHECK(resolution_minutes>=response_minutes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,policy_id),
 UNIQUE(tenant_id,policy_key)
);
ALTER TABLE crm.sla_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.sla_policies FORCE ROW LEVEL SECURITY;
REVOKE ALL ON crm.sla_policies FROM PUBLIC;
CREATE POLICY sla_read ON crm.sla_policies FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.sla.read'));
CREATE POLICY sla_executor_read ON crm.sla_policies FOR SELECT TO upc_sla_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.sla.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.sla.write'));
CREATE POLICY sla_executor_insert ON crm.sla_policies FOR INSERT TO upc_sla_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.sla.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.sla.write'));
GRANT USAGE ON SCHEMA crm,iam,platform TO upc_sla_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_sla_executor;
GRANT SELECT ON crm.sla_policies TO upc_runtime,upc_sla_executor;
GRANT INSERT(tenant_id,policy_key,response_minutes,resolution_minutes) ON crm.sla_policies TO upc_sla_executor;
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
 WHEN TG_TABLE_SCHEMA='content' AND TG_TABLE_NAME='article_revisions' THEN (j->>'revision_id')::uuid
 WHEN TG_TABLE_SCHEMA='content' AND TG_TABLE_NAME='article_favorites' THEN (j->>'favorite_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_merge_reviews' THEN (j->>'review_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='sla_policies' THEN (j->>'policy_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;






CREATE TRIGGER sla_policy_audit AFTER INSERT ON crm.sla_policies FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION crm.register_sla_policy(p_key text,p_response integer,p_resolution integer) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior crm.sla_policies%ROWTYPE; pid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('crm.sla.read') OR NOT iam.has_permission('crm.sla.write') THEN RAISE EXCEPTION 'SLA registration denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_response IS NULL OR p_resolution IS NULL OR p_response<=0 OR p_resolution<p_response THEN RAISE EXCEPTION 'Invalid proposed SLA targets' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-sla-policy',t,p_key)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('crm.sla.read') OR NOT iam.has_permission('crm.sla.write') THEN RAISE EXCEPTION 'SLA registration denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM crm.sla_policies WHERE tenant_id=t AND policy_key=p_key;
 IF FOUND THEN
  IF prior.response_minutes IS DISTINCT FROM p_response OR prior.resolution_minutes IS DISTINCT FROM p_resolution THEN RAISE EXCEPTION 'SLA policy key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.policy_id;
 END IF;
 INSERT INTO crm.sla_policies(tenant_id,policy_key,response_minutes,resolution_minutes) VALUES(t,p_key,p_response,p_resolution) RETURNING policy_id INTO pid;
 RETURN pid;
END $$;
ALTER FUNCTION crm.register_sla_policy(text,integer,integer) OWNER TO upc_sla_executor;
REVOKE ALL ON FUNCTION crm.register_sla_policy(text,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.register_sla_policy(text,integer,integer) TO upc_runtime;
COMMIT;

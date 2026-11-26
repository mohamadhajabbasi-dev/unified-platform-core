-- 0080: authorized staff-recorded support feedback prototype; not verified customer authorship.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('crm.feedback.read','Read recorded support feedback'),('crm.feedback.write','Record support feedback');
CREATE ROLE upc_feedback_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE crm.support_feedback (
 tenant_id uuid NOT NULL,
 feedback_id uuid NOT NULL DEFAULT gen_random_uuid(),
 ticket_id uuid NOT NULL,
 score integer NOT NULL CHECK(score BETWEEN 1 AND 5),
 recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,feedback_id),
 UNIQUE(tenant_id,ticket_id),
 FOREIGN KEY(tenant_id,ticket_id) REFERENCES crm.support_tickets(tenant_id,ticket_id),
 FOREIGN KEY(tenant_id,recorded_by) REFERENCES iam.memberships(tenant_id,user_id)
);
ALTER TABLE crm.support_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.support_feedback FORCE ROW LEVEL SECURITY;
REVOKE ALL ON crm.support_feedback FROM PUBLIC;
CREATE POLICY feedback_read ON crm.support_feedback FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.feedback.read') AND platform.module_enabled('crm'));
CREATE POLICY feedback_executor_read ON crm.support_feedback FOR SELECT TO upc_feedback_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.feedback.read') AND iam.has_permission('crm.feedback.write') AND platform.module_enabled('crm'));
CREATE POLICY feedback_executor_insert ON crm.support_feedback FOR INSERT TO upc_feedback_executor
 WITH CHECK(tenant_id=iam.current_tenant_id() AND recorded_by=iam.current_user_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.feedback.read') AND iam.has_permission('crm.feedback.write') AND platform.module_enabled('crm'));
GRANT USAGE ON SCHEMA crm,iam,platform TO upc_feedback_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_feedback_executor;
GRANT SELECT ON crm.support_feedback TO upc_runtime,upc_feedback_executor;
GRANT INSERT(tenant_id,ticket_id,score,recorded_by) ON crm.support_feedback TO upc_feedback_executor;
GRANT SELECT(tenant_id,ticket_id) ON crm.support_tickets TO upc_feedback_executor;
CREATE POLICY feedback_ticket_read ON crm.support_tickets FOR SELECT TO upc_feedback_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.feedback.read') AND iam.has_permission('crm.feedback.write') AND platform.module_enabled('crm'));
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
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_feedback' THEN (j->>'feedback_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;






CREATE TRIGGER support_feedback_audit AFTER INSERT ON crm.support_feedback FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION crm.record_support_feedback(p_ticket uuid,p_score integer) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); prior crm.support_feedback%ROWTYPE; fid uuid;
BEGIN
 IF t IS NULL OR actor IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.feedback.read') OR NOT iam.has_permission('crm.feedback.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Feedback access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_ticket IS NULL OR p_score IS NULL OR p_score NOT BETWEEN 1 AND 5 THEN RAISE EXCEPTION 'Invalid feedback' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-support-feedback',t,p_ticket)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR actor IS DISTINCT FROM iam.current_user_id() OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.feedback.read') OR NOT iam.has_permission('crm.feedback.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Feedback access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE tenant_id=t AND ticket_id=p_ticket) THEN RAISE EXCEPTION 'Ticket unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM crm.support_feedback WHERE tenant_id=t AND ticket_id=p_ticket;
 IF FOUND THEN
  IF prior.score IS DISTINCT FROM p_score OR prior.recorded_by IS DISTINCT FROM actor THEN RAISE EXCEPTION 'Feedback conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.feedback_id;
 END IF;
 INSERT INTO crm.support_feedback(tenant_id,ticket_id,score,recorded_by) VALUES(t,p_ticket,p_score,actor) RETURNING feedback_id INTO fid;
 RETURN fid;
END $$;
ALTER FUNCTION crm.record_support_feedback(uuid,integer) OWNER TO upc_feedback_executor;
REVOKE ALL ON FUNCTION crm.record_support_feedback(uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.record_support_feedback(uuid,integer) TO upc_runtime;
COMMIT;

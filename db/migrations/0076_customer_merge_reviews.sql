-- 0076: immutable unordered customer pair review request; never merges identities.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('crm.merge_reviews.read','Read tenant customer pair review requests'),('crm.merge_reviews.write','Request review of a customer pair');
CREATE ROLE upc_merge_review_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE crm.customer_merge_reviews (
 tenant_id uuid NOT NULL,
 review_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_low_id uuid NOT NULL,
 customer_high_id uuid NOT NULL,
 requested_by uuid NOT NULL,
 requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,review_id),
 UNIQUE(tenant_id,customer_low_id,customer_high_id),
 CHECK(customer_low_id<customer_high_id),
 FOREIGN KEY(tenant_id,customer_low_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,customer_high_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,requested_by) REFERENCES iam.memberships(tenant_id,user_id)
);
CREATE INDEX merge_reviews_high_idx ON crm.customer_merge_reviews(tenant_id,customer_high_id);
ALTER TABLE crm.customer_merge_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.customer_merge_reviews FORCE ROW LEVEL SECURITY;
REVOKE ALL ON crm.customer_merge_reviews FROM PUBLIC;
CREATE POLICY merge_review_read ON crm.customer_merge_reviews FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.merge_reviews.read'));
CREATE POLICY merge_review_executor_read ON crm.customer_merge_reviews FOR SELECT TO upc_merge_review_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.merge_reviews.read') AND iam.has_permission('crm.merge_reviews.write'));
CREATE POLICY merge_review_executor_insert ON crm.customer_merge_reviews FOR INSERT TO upc_merge_review_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.merge_reviews.read') AND iam.has_permission('crm.merge_reviews.write') AND requested_by=iam.current_user_id());
GRANT USAGE ON SCHEMA crm,iam,platform TO upc_merge_review_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_merge_review_executor;
GRANT SELECT(tenant_id,customer_id) ON crm.customers TO upc_merge_review_executor;
CREATE POLICY merge_review_customer_dependency ON crm.customers AS RESTRICTIVE FOR SELECT TO upc_merge_review_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND platform.module_enabled('crm') AND iam.has_permission('crm.merge_reviews.read') AND iam.has_permission('crm.merge_reviews.write'));
GRANT SELECT ON crm.customer_merge_reviews TO upc_runtime,upc_merge_review_executor;
GRANT INSERT(tenant_id,customer_low_id,customer_high_id,requested_by) ON crm.customer_merge_reviews TO upc_merge_review_executor;
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
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;





CREATE TRIGGER customer_merge_review_audit AFTER INSERT ON crm.customer_merge_reviews FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION crm.request_customer_merge_review(p_first uuid,p_second uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); lo uuid; hi uuid; rid uuid;
BEGIN
 IF t IS NULL OR actor IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('crm.merge_reviews.read') OR NOT iam.has_permission('crm.merge_reviews.write') THEN RAISE EXCEPTION 'Merge review access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_first IS NULL OR p_second IS NULL OR p_first=p_second THEN RAISE EXCEPTION 'Distinct customer pair required' USING ERRCODE='22023'; END IF;
 lo:=least(p_first,p_second); hi:=greatest(p_first,p_second);
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-merge-review',t,lo,hi)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR actor IS DISTINCT FROM iam.current_user_id() OR t IS NULL OR actor IS NULL OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') OR NOT iam.has_permission('crm.merge_reviews.read') OR NOT iam.has_permission('crm.merge_reviews.write') THEN RAISE EXCEPTION 'Merge review access denied' USING ERRCODE='42501'; END IF;
 IF (SELECT count(*) FROM crm.customers WHERE tenant_id=t AND customer_id IN(lo,hi))<>2 THEN RAISE EXCEPTION 'Customer pair unavailable' USING ERRCODE='23503'; END IF;
 SELECT review_id INTO rid FROM crm.customer_merge_reviews WHERE tenant_id=t AND customer_low_id=lo AND customer_high_id=hi;
 IF FOUND THEN RETURN rid; END IF;
 INSERT INTO crm.customer_merge_reviews(tenant_id,customer_low_id,customer_high_id,requested_by) VALUES(t,lo,hi,actor) RETURNING review_id INTO rid;
 RETURN rid;
END $$;
ALTER FUNCTION crm.request_customer_merge_review(uuid,uuid) OWNER TO upc_merge_review_executor;
REVOKE ALL ON FUNCTION crm.request_customer_merge_review(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.request_customer_merge_review(uuid,uuid) TO upc_runtime;
COMMIT;

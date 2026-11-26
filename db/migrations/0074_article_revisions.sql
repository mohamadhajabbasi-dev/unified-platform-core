-- 0074: explicitly captured immutable distinct editorial text snapshots, not a parallel article master.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('content.revisions.read','Read tenant captured editorial snapshots'),('content.revisions.capture','Capture current editorial text snapshot');
CREATE ROLE upc_revision_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE content.article_revisions (
 tenant_id uuid NOT NULL,
 revision_id uuid NOT NULL DEFAULT gen_random_uuid(),
 article_id uuid NOT NULL,
 captured_by uuid NOT NULL,
 captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 snapshot_digest bytea NOT NULL CHECK(octet_length(snapshot_digest)=32 AND snapshot_digest=sha256(convert_to(snapshot::text,'UTF8'))),
 PRIMARY KEY(tenant_id,revision_id),
 UNIQUE(tenant_id,article_id,snapshot_digest),
 FOREIGN KEY(tenant_id,article_id) REFERENCES content.articles(tenant_id,article_id),
 FOREIGN KEY(tenant_id,captured_by) REFERENCES iam.memberships(tenant_id,user_id)
);
CREATE INDEX article_revisions_capture_idx ON content.article_revisions(tenant_id,article_id,captured_at DESC);
ALTER TABLE content.article_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE content.article_revisions FORCE ROW LEVEL SECURITY;
REVOKE ALL ON content.article_revisions FROM PUBLIC;
CREATE POLICY revision_read ON content.article_revisions FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND platform.module_enabled('content') AND iam.has_permission('content.revisions.read'));
CREATE POLICY revision_executor_read ON content.article_revisions FOR SELECT TO upc_revision_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND platform.module_enabled('content') AND iam.has_permission('content.revisions.read') AND iam.has_permission('content.write') AND iam.has_permission('content.revisions.capture'));
CREATE POLICY revision_executor_insert ON content.article_revisions FOR INSERT TO upc_revision_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND platform.module_enabled('content') AND iam.has_permission('content.revisions.read') AND iam.has_permission('content.write') AND iam.has_permission('content.revisions.capture') AND captured_by=iam.current_user_id());
GRANT USAGE ON SCHEMA content,iam,platform TO upc_revision_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_revision_executor;
GRANT SELECT(tenant_id,article_id,slug,title,excerpt,body,seo_title,seo_description,focus_keyword,cover_asset_ref) ON content.articles TO upc_revision_executor;
CREATE POLICY revision_article_dependency ON content.articles FOR SELECT TO upc_revision_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND platform.module_enabled('content') AND iam.has_permission('content.revisions.read') AND iam.has_permission('content.write') AND iam.has_permission('content.revisions.capture'));
GRANT SELECT ON content.article_revisions TO upc_runtime,upc_revision_executor;
GRANT INSERT(tenant_id,article_id,captured_by,snapshot,snapshot_digest) ON content.article_revisions TO upc_revision_executor;
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
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;




CREATE TRIGGER article_revision_audit AFTER INSERT ON content.article_revisions FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION content.capture_article_revision(p_article uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); payload jsonb; digest_value bytea; previous content.article_revisions%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR actor IS NULL OR NOT iam.has_permission('content.read') OR NOT platform.module_enabled('content') OR NOT iam.has_permission('content.revisions.read') OR NOT iam.has_permission('content.write') OR NOT iam.has_permission('content.revisions.capture') THEN RAISE EXCEPTION 'Revision access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_article IS NULL THEN RAISE EXCEPTION 'Article required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('content-article-revision',t,p_article)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR actor IS DISTINCT FROM iam.current_user_id() OR t IS NULL OR actor IS NULL OR NOT iam.has_permission('content.read') OR NOT platform.module_enabled('content') OR NOT iam.has_permission('content.revisions.read') OR NOT iam.has_permission('content.write') OR NOT iam.has_permission('content.revisions.capture')
 THEN RAISE EXCEPTION 'Revision access denied' USING ERRCODE='42501'; END IF;
 -- Capture a single consistent committed text state (or own transaction state); no auto-versioning of direct edits.
 SELECT jsonb_build_object('slug',slug,'title',title,'excerpt',excerpt,'body',body,'seo_title',seo_title,'seo_description',seo_description,'focus_keyword',focus_keyword,'cover_asset_ref',cover_asset_ref)
 INTO payload FROM content.articles WHERE tenant_id=t AND article_id=p_article;
 IF NOT FOUND THEN RAISE EXCEPTION 'Article unavailable' USING ERRCODE='23503'; END IF;
 digest_value:=sha256(convert_to(payload::text,'UTF8'));
 SELECT * INTO previous FROM content.article_revisions WHERE tenant_id=t AND article_id=p_article AND snapshot_digest=digest_value;
 IF FOUND THEN
  IF previous.snapshot IS DISTINCT FROM payload THEN RAISE EXCEPTION 'Snapshot digest conflict' USING ERRCODE='23505'; END IF;
  RETURN previous.revision_id;
 END IF;
 INSERT INTO content.article_revisions(tenant_id,article_id,captured_by,snapshot,snapshot_digest)
 VALUES(t,p_article,actor,payload,digest_value) RETURNING revision_id INTO result_id;
 RETURN result_id;
END $$;
ALTER FUNCTION content.capture_article_revision(uuid) OWNER TO upc_revision_executor;
REVOKE ALL ON FUNCTION content.capture_article_revision(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION content.capture_article_revision(uuid) TO upc_runtime;
COMMIT;

-- 0063: internal CRM tag metadata and one persistent customer/tag relationship.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES
 ('crm.tags.read','Read tenant customer tag metadata and relationships'),
 ('crm.tags.write','Maintain tenant customer tags and relationships');
CREATE ROLE upc_tag_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE crm.customer_tags (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 tag_id uuid NOT NULL DEFAULT gen_random_uuid(),
 tag_key text NOT NULL CHECK(tag_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 120 AND display_name ~ '[^[:space:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,tag_id),
 UNIQUE(tenant_id,tag_key)
);
CREATE UNIQUE INDEX customer_tags_name_uq ON crm.customer_tags(tenant_id,lower(btrim(display_name)));
CREATE TABLE crm.customer_tag_links (
 tenant_id uuid NOT NULL,
 link_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 tag_id uuid NOT NULL,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,link_id),
 UNIQUE(tenant_id,customer_id,tag_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,tag_id) REFERENCES crm.customer_tags(tenant_id,tag_id)
);
CREATE INDEX customer_tag_links_tag_idx ON crm.customer_tag_links(tenant_id,tag_id,customer_id);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['crm.customer_tags'::regclass,'crm.customer_tag_links'::regclass] LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('REVOKE ALL ON %s FROM PUBLIC',rel);
  EXECUTE format('CREATE POLICY tag_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''crm.read'') AND iam.has_permission(''crm.tags.read'') AND platform.module_enabled(''crm''))',rel);
  EXECUTE format('CREATE POLICY tag_executor_read ON %s FOR SELECT TO upc_tag_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''crm.read'') AND iam.has_permission(''crm.tags.read'') AND iam.has_permission(''crm.tags.write'') AND platform.module_enabled(''crm''))',rel);
  EXECUTE format('CREATE POLICY tag_executor_insert ON %s FOR INSERT TO upc_tag_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(''crm.read'') AND iam.has_permission(''crm.tags.read'') AND iam.has_permission(''crm.tags.write'') AND platform.module_enabled(''crm''))',rel);
 END LOOP;
END $$;
CREATE POLICY link_executor_update ON crm.customer_tag_links FOR UPDATE TO upc_tag_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND iam.has_permission('crm.tags.read') AND iam.has_permission('crm.tags.write') AND platform.module_enabled('crm'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND iam.has_permission('crm.tags.read') AND iam.has_permission('crm.tags.write') AND platform.module_enabled('crm'));
-- Only existence of existing customer, not identity/addresses or profile fields.
GRANT USAGE ON SCHEMA crm,iam,platform TO upc_tag_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_tag_executor;
GRANT SELECT(tenant_id,customer_id) ON crm.customers TO upc_tag_executor;
CREATE POLICY tag_customer_dependency ON crm.customers AS RESTRICTIVE FOR SELECT TO upc_tag_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.read') AND iam.has_permission('crm.tags.read') AND iam.has_permission('crm.tags.write') AND platform.module_enabled('crm'));
GRANT SELECT ON crm.customer_tags,crm.customer_tag_links TO upc_runtime,upc_tag_executor;
GRANT INSERT(tenant_id,tag_key,display_name) ON crm.customer_tags TO upc_tag_executor;
GRANT INSERT(tenant_id,customer_id,tag_id) ON crm.customer_tag_links TO upc_tag_executor;
GRANT UPDATE(is_active,changed_at) ON crm.customer_tag_links TO upc_tag_executor;
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER customer_tag_audit AFTER INSERT ON crm.customer_tags FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE TRIGGER customer_tag_link_audit AFTER INSERT OR UPDATE ON crm.customer_tag_links FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
-- Statement-time module contract preserved; no change to financial period locks.
CREATE FUNCTION crm.register_customer_tag(p_key text,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); old_tag crm.customer_tags%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.read') OR NOT iam.has_permission('crm.tags.read') OR NOT iam.has_permission('crm.tags.write') OR NOT platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'Customer tag access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 120 OR p_name !~ '[^[:space:]]'
 THEN RAISE EXCEPTION 'Invalid tag metadata' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-tag-key',t,p_key)::text,0));
 IF NOT iam.has_permission('crm.read') OR NOT iam.has_permission('crm.tags.read') OR NOT iam.has_permission('crm.tags.write') OR NOT platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'Customer tag access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO old_tag FROM crm.customer_tags WHERE tenant_id=t AND tag_key=p_key;
 IF FOUND THEN
  IF old_tag.display_name IS DISTINCT FROM p_name THEN RAISE EXCEPTION 'Tag key conflict' USING ERRCODE='23505'; END IF;
  RETURN old_tag.tag_id;
 END IF;
 INSERT INTO crm.customer_tags(tenant_id,tag_key,display_name) VALUES(t,p_key,p_name) RETURNING tag_id INTO result_id;
 RETURN result_id;
END $$;
CREATE FUNCTION crm.set_customer_tag(p_customer uuid,p_tag uuid,p_active boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); old_link crm.customer_tag_links%ROWTYPE; result_id uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.read') OR NOT iam.has_permission('crm.tags.read') OR NOT iam.has_permission('crm.tags.write') OR NOT platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'Customer tag access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_customer IS NULL OR p_tag IS NULL OR p_active IS NULL THEN RAISE EXCEPTION 'Customer, tag and state required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-tag-link',t,p_customer,p_tag)::text,0));
 IF NOT iam.has_permission('crm.read') OR NOT iam.has_permission('crm.tags.read') OR NOT iam.has_permission('crm.tags.write') OR NOT platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'Customer tag access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=t AND customer_id=p_customer)
 OR NOT EXISTS(SELECT 1 FROM crm.customer_tags WHERE tenant_id=t AND tag_id=p_tag)
 THEN RAISE EXCEPTION 'Customer or tag unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO old_link FROM crm.customer_tag_links WHERE tenant_id=t AND customer_id=p_customer AND tag_id=p_tag;
 IF FOUND THEN
  IF old_link.is_active IS DISTINCT FROM p_active THEN
   UPDATE crm.customer_tag_links SET is_active=p_active,changed_at=clock_timestamp() WHERE tenant_id=t AND link_id=old_link.link_id;
   IF NOT FOUND THEN RAISE EXCEPTION 'Customer tag update denied' USING ERRCODE='42501'; END IF;
  END IF;
  RETURN old_link.link_id;
 END IF;
 IF NOT p_active THEN RETURN NULL; END IF;
 INSERT INTO crm.customer_tag_links(tenant_id,customer_id,tag_id) VALUES(t,p_customer,p_tag) RETURNING link_id INTO result_id;
 RETURN result_id;
END $$;
ALTER FUNCTION crm.register_customer_tag(text,text) OWNER TO upc_tag_executor;
ALTER FUNCTION crm.set_customer_tag(uuid,uuid,boolean) OWNER TO upc_tag_executor;
REVOKE ALL ON FUNCTION crm.register_customer_tag(text,text),crm.set_customer_tag(uuid,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.register_customer_tag(text,text),crm.set_customer_tag(uuid,uuid,boolean) TO upc_runtime;
COMMIT;

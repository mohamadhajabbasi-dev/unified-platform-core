-- 0062: dormant tenant site identity only; no domain ownership or routing.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES
 ('tenant.sites.read','Read dormant tenant site metadata'),
 ('tenant.sites.write','Register dormant tenant site metadata');
CREATE ROLE upc_site_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE core.sites (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 site_id uuid NOT NULL DEFAULT gen_random_uuid(),
 site_key text NOT NULL CHECK(site_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 200 AND display_name ~ '[^[:space:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,site_id),
 UNIQUE(tenant_id,site_key)
);
ALTER TABLE core.sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.sites FORCE ROW LEVEL SECURITY;
REVOKE ALL ON core.sites FROM PUBLIC;
CREATE POLICY site_read ON core.sites FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.sites.read'));
CREATE POLICY site_executor_read ON core.sites FOR SELECT TO upc_site_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.sites.read') AND iam.has_permission('tenant.sites.write'));
CREATE POLICY site_executor_insert ON core.sites FOR INSERT TO upc_site_executor
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.sites.read') AND iam.has_permission('tenant.sites.write'));
GRANT SELECT ON core.sites TO upc_runtime,upc_site_executor;
GRANT USAGE ON SCHEMA core,iam TO upc_site_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text) TO upc_site_executor;
GRANT INSERT(tenant_id,site_key,display_name) ON core.sites TO upc_site_executor;
-- Shared audit; preserve all previous target branches.
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER site_audit AFTER INSERT ON core.sites FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
-- Stable site_key is the retry key. No caller-supplied tenant/id/time/domain.
-- No update/activation is granted. Exact retries return the original ID,
-- differing payloads fail closed; permission checked before reading history.
CREATE FUNCTION core.register_site(p_key text,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior core.sites%ROWTYPE; sid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('tenant.sites.read') OR NOT iam.has_permission('tenant.sites.write')
 THEN RAISE EXCEPTION 'Site registration denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed'
 THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 200 OR p_name !~ '[^[:space:]]'
 THEN RAISE EXCEPTION 'Invalid site identity' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('core-site-key',t,p_key)::text,0));
 SELECT * INTO prior FROM core.sites WHERE tenant_id=t AND site_key=p_key;
 IF FOUND THEN
  IF prior.display_name IS DISTINCT FROM p_name THEN RAISE EXCEPTION 'Site key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.site_id;
 END IF;
 INSERT INTO core.sites(tenant_id,site_key,display_name) VALUES(t,p_key,p_name) RETURNING site_id INTO sid;
 RETURN sid;
END $$;
ALTER FUNCTION core.register_site(text,text) OWNER TO upc_site_executor;
REVOKE ALL ON FUNCTION core.register_site(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.register_site(text,text) TO upc_runtime;
COMMIT;

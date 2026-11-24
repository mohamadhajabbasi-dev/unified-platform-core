-- 0011: organization dossier and tenant-scoped membership preferences.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO iam.permissions VALUES
 ('tenant.legal.read','Read sensitive organization dossier'),
 ('tenant.legal.write','Maintain organization dossier and stakeholders'),
 ('tenant.settings.read','Read organization preferences'),
 ('tenant.settings.write','Maintain organization preferences'),
 ('tenant.members.read','Read personnel settings'),
 ('tenant.members.write','Maintain personnel settings');
-- The canonical tenant name remains core.tenants.display_name.
CREATE TABLE core.tenant_profiles (
 tenant_id uuid PRIMARY KEY REFERENCES core.tenants(tenant_id),
 entity_type text NOT NULL CHECK(entity_type IN ('individual','registered_entity','other')),
 registered_name text NOT NULL CHECK(length(btrim(registered_name)) BETWEEN 1 AND 300),
 country_code text NOT NULL CHECK(country_code ~ '^[A-Z]{2}$'),
 jurisdiction text NOT NULL CHECK(length(btrim(jurisdiction)) BETWEEN 1 AND 200),
 registration_ref text CHECK(length(btrim(registration_ref)) BETWEEN 1 AND 300),
 registration_date date CHECK(isfinite(registration_date)),
 tax_ref text CHECK(length(btrim(tax_ref)) BETWEEN 1 AND 300),
 legal_status text NOT NULL CHECK(legal_status IN ('unverified','active','inactive','dissolved')),
 industry text CHECK(length(btrim(industry)) BETWEEN 1 AND 200),
 CHECK(entity_type<>'registered_entity' OR registration_ref IS NOT NULL)
);
-- References are opaque identifiers in a future protected identity vault.
-- Never store raw national/tax/registration identifiers in these reference columns.
CREATE TABLE core.tenant_stakeholders (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 stakeholder_id uuid NOT NULL DEFAULT gen_random_uuid(),
 party_ref text NOT NULL CHECK(length(btrim(party_ref)) BETWEEN 1 AND 300),
 party_type text NOT NULL CHECK(party_type IN ('individual','organization')),
 party_name text NOT NULL CHECK(length(btrim(party_name)) BETWEEN 1 AND 300),
 user_id uuid,
 roles text[] NOT NULL CHECK(cardinality(roles) BETWEEN 1 AND 6 AND array_position(roles,NULL) IS NULL
 AND roles <@ ARRAY['partner','shareholder','beneficial_owner','representative','signatory','manager']::text[]),
 ownership_pct numeric(7,4) CHECK(ownership_pct>=0 AND ownership_pct<=100 AND ownership_pct<>'NaN'::numeric),
 authority_description text CHECK(length(btrim(authority_description)) BETWEEN 1 AND 2000),
 valid_during daterange NOT NULL CHECK(NOT isempty(valid_during) AND NOT lower_inf(valid_during)
 AND isfinite(lower(valid_during)) AND (upper_inf(valid_during) OR isfinite(upper(valid_during)))),
 PRIMARY KEY(tenant_id,stakeholder_id),
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id),
 EXCLUDE USING gist(tenant_id WITH =,party_ref WITH =,valid_during WITH &&),
 CHECK(party_type='individual' OR user_id IS NULL),
 CHECK(ownership_pct IS NULL OR roles && ARRAY['partner','shareholder','beneficial_owner']::text[])
);
CREATE TABLE core.tenant_addresses (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 address_id uuid NOT NULL DEFAULT gen_random_uuid(),
 address_kind text NOT NULL CHECK(address_kind IN ('registered','billing','operating')),
 country_code text NOT NULL CHECK(country_code ~ '^[A-Z]{2}$'),
 address_text text NOT NULL CHECK(length(btrim(address_text)) BETWEEN 1 AND 2000),
 postal_code text CHECK(length(btrim(postal_code)) BETWEEN 1 AND 100),
 PRIMARY KEY(tenant_id,address_id)
);
-- Typed settings only. No module enablement, credentials, accounting or price flags.
CREATE TABLE core.tenant_settings (
 tenant_id uuid PRIMARY KEY REFERENCES core.tenants(tenant_id),
 locale text NOT NULL CHECK(locale ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
 timezone text NOT NULL,
 contact_email text CHECK(length(contact_email)<=254 AND contact_email ~ '^[^[:space:]@]+@[^[:space:]@]+$'),
 contact_phone text CHECK(contact_phone ~ '^\+[1-9][0-9]{7,14}$'),
 website_host text CHECK(length(website_host)<=253 AND website_host ~ '^[a-z0-9.-]+$'),
 CHECK(length(timezone) BETWEEN 1 AND 100)
);
CREATE TABLE iam.membership_settings (
 tenant_id uuid NOT NULL,
 user_id uuid NOT NULL,
 locale text CHECK(locale ~ '^[a-z]{2,3}(-[A-Z]{2})?$'),
 timezone text CHECK(length(timezone) BETWEEN 1 AND 100),
 notifications_enabled boolean NOT NULL DEFAULT true,
 job_title text CHECK(length(btrim(job_title)) BETWEEN 1 AND 200),
 department text CHECK(length(btrim(department)) BETWEEN 1 AND 200),
 manager_user_id uuid,
 PRIMARY KEY(tenant_id,user_id),
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(tenant_id,manager_user_id) REFERENCES iam.memberships(tenant_id,user_id) ON DELETE SET NULL(manager_user_id),
 CHECK(manager_user_id IS DISTINCT FROM user_id)
);
-- One shared audit event table, not a second master or copy of sensitive values.
CREATE SCHEMA ops;
REVOKE ALL ON SCHEMA ops FROM PUBLIC;
CREATE ROLE upc_audit_writer NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE ops.audit_events (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 event_id uuid NOT NULL DEFAULT gen_random_uuid(),
 actor_user_id uuid NOT NULL REFERENCES core.users(user_id),
 event_type text NOT NULL,
 entity_type text NOT NULL,
 entity_id uuid NOT NULL,
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,event_id)
);
CREATE INDEX audit_events_tenant_time_idx ON ops.audit_events(tenant_id,occurred_at);
ALTER TABLE ops.audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.audit_events FORCE ROW LEVEL SECURITY;
INSERT INTO iam.permissions VALUES ('ops.audit.read','Read own tenant audit metadata');
CREATE POLICY audit_read ON ops.audit_events FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('ops.audit.read'));
CREATE POLICY audit_write ON ops.audit_events FOR INSERT TO upc_audit_writer WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT USAGE ON SCHEMA ops TO upc_runtime,upc_audit_writer;
GRANT USAGE ON SCHEMA iam TO upc_audit_writer;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id() TO upc_audit_writer;
GRANT INSERT ON ops.audit_events TO upc_audit_writer;
GRANT SELECT ON ops.audit_events TO upc_runtime;
CREATE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t);
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
ALTER FUNCTION ops.record_dossier_change() OWNER TO upc_audit_writer;
REVOKE ALL ON FUNCTION ops.record_dossier_change() FROM PUBLIC;
CREATE FUNCTION core.validate_timezone() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.timezone IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=NEW.timezone)
 THEN RAISE EXCEPTION 'Invalid timezone' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION core.validate_timezone() FROM PUBLIC;
CREATE TRIGGER validate_tenant_timezone BEFORE INSERT OR UPDATE OF timezone ON core.tenant_settings FOR EACH ROW EXECUTE FUNCTION core.validate_timezone();
CREATE TRIGGER validate_member_timezone BEFORE INSERT OR UPDATE OF timezone ON iam.membership_settings FOR EACH ROW EXECUTE FUNCTION core.validate_timezone();
DO $$
DECLARE rel regclass; read_perm text; write_perm text;
BEGIN
 FOREACH rel IN ARRAY ARRAY['core.tenant_profiles'::regclass,'core.tenant_stakeholders'::regclass,'core.tenant_addresses'::regclass,'core.tenant_settings'::regclass] LOOP
  read_perm:=CASE WHEN rel='core.tenant_settings'::regclass THEN 'tenant.settings.read' ELSE 'tenant.legal.read' END;
  write_perm:=CASE WHEN rel='core.tenant_settings'::regclass THEN 'tenant.settings.write' ELSE 'tenant.legal.write' END;
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY dossier_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L))',rel,read_perm);
  EXECUTE format('CREATE POLICY dossier_insert ON %s FOR INSERT TO upc_runtime WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND iam.has_permission(%L))',rel,read_perm,write_perm);
  EXECUTE format('CREATE POLICY dossier_update ON %s FOR UPDATE TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND iam.has_permission(%L)) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND iam.has_permission(%L))',rel,read_perm,write_perm,read_perm,write_perm);
  EXECUTE format('CREATE TRIGGER dossier_audit AFTER INSERT OR UPDATE ON %s FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change()',rel);
 END LOOP;
END $$;
GRANT SELECT,INSERT ON core.tenant_profiles,core.tenant_stakeholders,core.tenant_addresses,core.tenant_settings TO upc_runtime;
GRANT UPDATE(entity_type,registered_name,country_code,jurisdiction,registration_ref,registration_date,tax_ref,legal_status,industry) ON core.tenant_profiles TO upc_runtime;
GRANT UPDATE(roles,ownership_pct,authority_description,valid_during) ON core.tenant_stakeholders TO upc_runtime;
GRANT UPDATE(address_kind,country_code,address_text,postal_code) ON core.tenant_addresses TO upc_runtime;
GRANT UPDATE(locale,timezone,contact_email,contact_phone,website_host) ON core.tenant_settings TO upc_runtime;
ALTER TABLE iam.membership_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.membership_settings FORCE ROW LEVEL SECURITY;
CREATE POLICY member_settings_read ON iam.membership_settings FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND (user_id=iam.current_user_id() OR iam.has_permission('tenant.members.read')));
CREATE POLICY member_settings_insert ON iam.membership_settings FOR INSERT TO upc_runtime
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.members.read') AND iam.has_permission('tenant.members.write'));
CREATE POLICY member_settings_update ON iam.membership_settings FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.members.read') AND iam.has_permission('tenant.members.write'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.members.read') AND iam.has_permission('tenant.members.write'));
GRANT SELECT,INSERT ON iam.membership_settings TO upc_runtime;
GRANT UPDATE(locale,timezone,notifications_enabled,job_title,department,manager_user_id) ON iam.membership_settings TO upc_runtime;
CREATE TRIGGER member_settings_audit AFTER INSERT OR UPDATE ON iam.membership_settings FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
-- Self-service preferences cannot edit job/department/manager or other user's rows.
CREATE ROLE upc_preferences_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA iam TO upc_preferences_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id() TO upc_preferences_executor;
GRANT SELECT ON iam.membership_settings TO upc_preferences_executor;
GRANT INSERT(tenant_id,user_id,locale,timezone,notifications_enabled),UPDATE(locale,timezone,notifications_enabled)
 ON iam.membership_settings TO upc_preferences_executor;
CREATE POLICY self_preferences ON iam.membership_settings FOR ALL TO upc_preferences_executor
 USING(tenant_id=iam.current_tenant_id() AND user_id=iam.current_user_id())
 WITH CHECK(tenant_id=iam.current_tenant_id() AND user_id=iam.current_user_id());
CREATE FUNCTION iam.set_my_preferences(p_locale text,p_timezone text,p_notify boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); u uuid:=iam.current_user_id();
BEGIN
 IF t IS NULL OR u IS NULL THEN RAISE EXCEPTION 'Membership required' USING ERRCODE='42501'; END IF;
 INSERT INTO iam.membership_settings(tenant_id,user_id,locale,timezone,notifications_enabled)
 VALUES(t,u,p_locale,p_timezone,p_notify) ON CONFLICT(tenant_id,user_id) DO UPDATE SET
 locale=EXCLUDED.locale,timezone=EXCLUDED.timezone,notifications_enabled=EXCLUDED.notifications_enabled;
END $$;
ALTER FUNCTION iam.set_my_preferences(text,text,boolean) OWNER TO upc_preferences_executor;
REVOKE ALL ON FUNCTION iam.set_my_preferences(text,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION iam.set_my_preferences(text,text,boolean) TO upc_runtime;
COMMIT;

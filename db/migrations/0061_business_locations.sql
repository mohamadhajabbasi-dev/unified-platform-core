-- 0061: tenant physical branch/store identity, no address or warehouse duplicate.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO iam.permissions VALUES
 ('tenant.locations.read','Read tenant physical business locations'),
 ('tenant.locations.write','Maintain tenant physical business locations');

CREATE TABLE core.business_locations (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 location_id uuid NOT NULL DEFAULT gen_random_uuid(),
 location_key text NOT NULL CHECK(location_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 200 AND display_name ~ '[^[:space:]]'),
 location_kind text NOT NULL CHECK(location_kind IN ('branch','store')),
 address_id uuid,
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,location_id),
 UNIQUE(tenant_id,location_key),
 FOREIGN KEY(tenant_id,address_id) REFERENCES core.tenant_addresses(tenant_id,address_id)
);
CREATE INDEX business_locations_address_idx ON core.business_locations(tenant_id,address_id);
ALTER TABLE core.business_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.business_locations FORCE ROW LEVEL SECURITY;
REVOKE ALL ON core.business_locations FROM PUBLIC;
CREATE POLICY location_read ON core.business_locations FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.locations.read'));
-- Referencing a dossier address requires its existing read permission; prevent
-- an unauthorized writer from using the FK as an address-existence oracle.
CREATE POLICY location_insert ON core.business_locations FOR INSERT TO upc_runtime
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.locations.read')
 AND iam.has_permission('tenant.locations.write')
 AND (address_id IS NULL OR iam.has_permission('tenant.legal.read')));
CREATE POLICY location_update ON core.business_locations FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.locations.read')
 AND iam.has_permission('tenant.locations.write'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('tenant.locations.read')
 AND iam.has_permission('tenant.locations.write')
 AND (address_id IS NULL OR iam.has_permission('tenant.legal.read')));
GRANT SELECT ON core.business_locations TO upc_runtime;
GRANT INSERT(tenant_id,location_key,display_name,location_kind,address_id,is_active)
 ON core.business_locations TO upc_runtime;
GRANT UPDATE(display_name,address_id,is_active) ON core.business_locations TO upc_runtime;

-- Preserve the existing audit writer, owner, scope, ACL and all old targets.
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER business_location_audit AFTER INSERT OR UPDATE ON core.business_locations
 FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
COMMIT;

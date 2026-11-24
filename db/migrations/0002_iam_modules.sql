-- Independent greenfield test database only.
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'upc_greenfield_test' THEN
   RAISE EXCEPTION 'Test database required';
 END IF;
END $$;

-- Separate non-login, non-bypass function owners. No runtime role may inherit them.
CREATE ROLE upc_scope_owner NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_crm_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_policy_reader NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_module_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_platform_approver NOLOGIN NOSUPERUSER NOBYPASSRLS;

GRANT USAGE ON SCHEMA iam TO upc_scope_owner;
GRANT SELECT ON iam.db_principals TO upc_scope_owner;
ALTER FUNCTION iam.current_tenant_id() OWNER TO upc_scope_owner;

CREATE FUNCTION iam.current_user_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog
AS $$
 SELECT p.user_id FROM iam.db_principals p WHERE p.login_role = session_user::name
$$;
ALTER FUNCTION iam.current_user_id() OWNER TO upc_scope_owner;
REVOKE ALL ON FUNCTION iam.current_user_id() FROM PUBLIC;

GRANT USAGE ON SCHEMA iam,crm TO upc_crm_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_crm_executor;
GRANT SELECT, INSERT ON crm.customers,crm.customer_identifiers TO upc_crm_executor;
ALTER FUNCTION crm.resolve_verified_customer(text,text,text,text) OWNER TO upc_crm_executor;

-- Permission registry is global; grants and memberships are tenant-owned.
CREATE TABLE iam.permissions (
 permission_key text PRIMARY KEY CHECK (permission_key ~ '^[a-z][a-z0-9_.-]+$'),
 description text NOT NULL
);
CREATE TABLE iam.roles (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 role_id uuid NOT NULL DEFAULT gen_random_uuid(),
 role_key text NOT NULL CHECK (btrim(role_key) <> ''),
 PRIMARY KEY(tenant_id,role_id),
 UNIQUE(tenant_id,role_key)
);
CREATE TABLE iam.role_grants (
 tenant_id uuid NOT NULL,
 role_id uuid NOT NULL,
 permission_key text NOT NULL REFERENCES iam.permissions(permission_key),
 PRIMARY KEY(tenant_id,role_id,permission_key),
 FOREIGN KEY(tenant_id,role_id) REFERENCES iam.roles(tenant_id,role_id) ON DELETE CASCADE
);
CREATE TABLE iam.membership_roles (
 tenant_id uuid NOT NULL,
 user_id uuid NOT NULL,
 role_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,user_id,role_id),
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id) ON DELETE CASCADE,
 FOREIGN KEY(tenant_id,role_id) REFERENCES iam.roles(tenant_id,role_id) ON DELETE CASCADE
);
CREATE INDEX membership_roles_role_idx ON iam.membership_roles(tenant_id,role_id);

-- Independent privileged platform login assignments, reusing core.users.
-- Only bootstrap administration provisions assignments; no tenant access.
CREATE TABLE iam.platform_staff_assignments (
 login_role name PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES core.users(user_id),
 is_superadmin boolean NOT NULL DEFAULT false,
 revoked_at timestamptz
);

CREATE SCHEMA platform;
REVOKE ALL ON SCHEMA platform FROM PUBLIC;
CREATE TABLE platform.modules (
 module_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 module_key text NOT NULL UNIQUE CHECK (module_key ~ '^[a-z][a-z0-9_.-]+$'),
 version_label text NOT NULL CHECK (btrim(version_label) <> '')
);

-- Append-only decisions are the sole source of module enablement.
-- Latest decision wins, expiry never falls back to an earlier approval.
CREATE TABLE platform.tenant_module_grants (
 decision_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 module_id uuid NOT NULL REFERENCES platform.modules(module_id),
 enabled boolean NOT NULL,
 decided_by uuid NOT NULL REFERENCES core.users(user_id),
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz,
 reason text NOT NULL CHECK (btrim(reason) <> ''),
 CHECK (enabled OR expires_at IS NULL),
 CHECK (expires_at IS NULL OR expires_at > decided_at)
);
CREATE INDEX tenant_module_latest_idx
 ON platform.tenant_module_grants(tenant_id,module_id,decision_id DESC);

DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['iam.roles'::regclass,'iam.role_grants'::regclass,
   'iam.membership_roles'::regclass,'platform.tenant_module_grants'::regclass]
 LOOP
   EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
   EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
   EXECUTE format('CREATE POLICY tenant_scope ON %s USING (tenant_id=iam.current_tenant_id()) WITH CHECK (tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
-- The executor is not a login or member of a runtime role. Only the narrow
-- approval function below may write across tenants after checking authority.
CREATE POLICY module_executor_insert ON platform.tenant_module_grants
 FOR INSERT TO upc_module_executor WITH CHECK (true);
CREATE POLICY module_executor_select ON platform.tenant_module_grants
 FOR SELECT TO upc_module_executor USING (true);

GRANT USAGE ON SCHEMA iam,platform TO upc_policy_reader;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id() TO upc_policy_reader;
GRANT SELECT ON iam.membership_roles,iam.role_grants,platform.tenant_module_grants,platform.modules TO upc_policy_reader;

CREATE FUNCTION iam.has_permission(p_permission text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $$
 SELECT EXISTS (
  SELECT 1 FROM iam.membership_roles mr
  JOIN iam.role_grants rg ON rg.tenant_id=mr.tenant_id AND rg.role_id=mr.role_id
  WHERE mr.tenant_id=iam.current_tenant_id() AND mr.user_id=iam.current_user_id()
    AND rg.permission_key=p_permission
 )
$$;
ALTER FUNCTION iam.has_permission(text) OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION iam.has_permission(text) FROM PUBLIC;

CREATE FUNCTION platform.module_enabled(p_module_key text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog
AS $$
 SELECT COALESCE((
   SELECT g.enabled AND (g.expires_at IS NULL OR g.expires_at > statement_timestamp())
   FROM platform.tenant_module_grants g JOIN platform.modules m USING(module_id)
   WHERE g.tenant_id=iam.current_tenant_id() AND m.module_key=p_module_key
   ORDER BY g.decision_id DESC LIMIT 1
 ),false)
$$;
ALTER FUNCTION platform.module_enabled(text) OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION platform.module_enabled(text) FROM PUBLIC;

GRANT USAGE ON SCHEMA iam,platform TO upc_module_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_module_executor;
GRANT SELECT ON iam.platform_staff_assignments,platform.modules TO upc_module_executor;
GRANT SELECT,INSERT ON platform.tenant_module_grants TO upc_module_executor;
GRANT USAGE ON SEQUENCE platform.tenant_module_grants_decision_id_seq TO upc_module_executor;

CREATE FUNCTION platform.record_module_decision(
 p_tenant uuid,p_module_key text,p_enabled boolean,p_expires_at timestamptz,p_reason text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog
AS $$
DECLARE v_actor uuid; v_module uuid; v_decision bigint;
BEGIN
 SELECT user_id INTO v_actor FROM iam.platform_staff_assignments
 WHERE login_role=session_user::name AND is_superadmin AND revoked_at IS NULL;
 IF v_actor IS NULL OR iam.current_tenant_id() IS NOT NULL THEN
   RAISE EXCEPTION 'platform superadmin required' USING ERRCODE='42501';
 END IF;
 IF p_tenant IS NULL OR p_enabled IS NULL OR p_reason IS NULL OR btrim(p_reason)=''
   OR (NOT p_enabled AND p_expires_at IS NOT NULL)
   OR (p_expires_at IS NOT NULL AND p_expires_at <= clock_timestamp()) THEN
   RAISE EXCEPTION 'invalid approval' USING ERRCODE='22023';
 END IF;
 SELECT module_id INTO STRICT v_module FROM platform.modules WHERE module_key=p_module_key;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('module',p_tenant,v_module)::text,0));
 INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,expires_at,reason)
 VALUES(p_tenant,v_module,p_enabled,v_actor,p_expires_at,p_reason)
 RETURNING decision_id INTO v_decision;
 RETURN v_decision;
END $$;
ALTER FUNCTION platform.record_module_decision(uuid,text,boolean,timestamptz,text) OWNER TO upc_module_executor;
REVOKE ALL ON FUNCTION platform.record_module_decision(uuid,text,boolean,timestamptz,text) FROM PUBLIC;
GRANT USAGE ON SCHEMA platform TO upc_platform_approver,upc_runtime;
GRANT EXECUTE ON FUNCTION platform.record_module_decision(uuid,text,boolean,timestamptz,text) TO upc_platform_approver;
GRANT EXECUTE ON FUNCTION iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_runtime;

COMMIT;

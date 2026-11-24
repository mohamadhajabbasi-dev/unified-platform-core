-- Greenfield prototype only. Never run on an existing operational database.
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'upc_greenfield_test' THEN
    RAISE EXCEPTION 'This prototype is restricted to upc_greenfield_test';
  END IF;
END $$;

CREATE ROLE upc_runtime NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_identity_writer NOLOGIN NOSUPERUSER NOBYPASSRLS;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA core;
CREATE SCHEMA iam;
CREATE SCHEMA crm;
REVOKE ALL ON SCHEMA core, iam, crm FROM PUBLIC;

CREATE TABLE core.tenants (
  tenant_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_key text NOT NULL UNIQUE CHECK (tenant_key ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  display_name text NOT NULL CHECK (btrim(display_name) <> ''),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE core.users (
  user_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  identity_issuer text NOT NULL CHECK (btrim(identity_issuer) <> ''),
  identity_subject text NOT NULL CHECK (btrim(identity_subject) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (identity_issuer, identity_subject)
);
CREATE TABLE iam.memberships (
  tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
  user_id uuid NOT NULL REFERENCES core.users(user_id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, user_id)
);
-- Private authorization directory: a trusted, dedicated database login is
-- bound to exactly one membership. Not a second user or tenant master.
-- Runtime has no direct access. Deleting membership cascades revocation.
CREATE TABLE iam.db_principals (
  login_role name PRIMARY KEY,
  tenant_id uuid NOT NULL,
  user_id uuid NOT NULL,
  FOREIGN KEY (tenant_id, user_id)
    REFERENCES iam.memberships(tenant_id, user_id) ON DELETE CASCADE
);
CREATE FUNCTION iam.current_tenant_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog
AS $$
  SELECT p.tenant_id FROM iam.db_principals AS p
  WHERE p.login_role = session_user::name
$$;
REVOKE ALL ON FUNCTION iam.current_tenant_id() FROM PUBLIC;

CREATE TABLE crm.customers (
  tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
  customer_id uuid NOT NULL DEFAULT gen_random_uuid(),
  display_name text NOT NULL CHECK (btrim(display_name) <> ''),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, customer_id)
);
CREATE TABLE crm.customer_identifiers (
  tenant_id uuid NOT NULL,
  identifier_id uuid NOT NULL DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('phone','email','channel')),
  issuer text NOT NULL DEFAULT '',
  normalized_value text NOT NULL CHECK (btrim(normalized_value) = normalized_value AND normalized_value <> ''),
  verified_at timestamptz,
  revoked_at timestamptz,
  PRIMARY KEY (tenant_id, identifier_id),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES crm.customers(tenant_id, customer_id),
  CHECK ((kind = 'channel' AND btrim(issuer) <> '') OR (kind <> 'channel' AND issuer = '')),
  CHECK (kind <> 'phone' OR normalized_value ~ '^\+[1-9][0-9]{7,14}$'),
  CHECK (revoked_at IS NULL OR (verified_at IS NOT NULL AND revoked_at >= verified_at))
);
CREATE UNIQUE INDEX customer_verified_identity_uq
  ON crm.customer_identifiers (tenant_id, kind, issuer, normalized_value)
  WHERE verified_at IS NOT NULL AND revoked_at IS NULL;
CREATE INDEX customer_identifiers_customer_idx ON crm.customer_identifiers(tenant_id, customer_id);

CREATE TABLE crm.customer_addresses (
  tenant_id uuid NOT NULL,
  address_id uuid NOT NULL DEFAULT gen_random_uuid(),
  customer_id uuid NOT NULL,
  address_text text NOT NULL CHECK (btrim(address_text) <> ''),
  PRIMARY KEY (tenant_id, address_id),
  FOREIGN KEY (tenant_id, customer_id) REFERENCES crm.customers(tenant_id, customer_id)
);
CREATE INDEX customer_addresses_customer_idx ON crm.customer_addresses(tenant_id, customer_id);

-- Fail closed for unmapped session logins. Never trust caller-set tenant GUCs.
ALTER TABLE core.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON core.tenants
  USING (tenant_id = iam.current_tenant_id())
  WITH CHECK (tenant_id = iam.current_tenant_id());
ALTER TABLE iam.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.memberships FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_scope ON iam.memberships
  USING (tenant_id = iam.current_tenant_id())
  WITH CHECK (tenant_id = iam.current_tenant_id());
DO $$
DECLARE rel regclass;
BEGIN
  FOREACH rel IN ARRAY ARRAY['crm.customers'::regclass,
    'crm.customer_identifiers'::regclass,'crm.customer_addresses'::regclass]
  LOOP
    EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', rel);
    EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', rel);
    EXECUTE format('CREATE POLICY tenant_scope ON %s USING (tenant_id = iam.current_tenant_id()) WITH CHECK (tenant_id = iam.current_tenant_id())', rel);
  END LOOP;
END $$;

-- Trusted verifier service only: this function does not itself prove ownership
-- of phone/email/channel. Call ONLY after independently verified identity and
-- ambiguity review. It does not auto-merge profiles with different identifiers.
CREATE FUNCTION crm.resolve_verified_customer(
  p_kind text, p_issuer text, p_value text, p_display_name text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog
AS $$
DECLARE
  v_tenant uuid := iam.current_tenant_id();
  v_customer uuid;
BEGIN
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'unmapped session login' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL OR p_issuer IS NULL OR p_value IS NULL
      OR p_display_name IS NULL OR btrim(p_display_name) = ''
      OR p_value = '' OR btrim(p_value) <> p_value THEN
    RAISE EXCEPTION 'invalid verified identity input' USING ERRCODE = '22023';
  END IF;
  -- Serialize same canonical identity. A hash collision only serializes unrelated work.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    jsonb_build_array(v_tenant,p_kind,p_issuer,p_value)::text,0));
  SELECT customer_id INTO v_customer
    FROM crm.customer_identifiers
    WHERE tenant_id = v_tenant AND kind = p_kind AND issuer = p_issuer
      AND normalized_value = p_value AND verified_at IS NOT NULL AND revoked_at IS NULL;
  IF FOUND THEN RETURN v_customer; END IF;
  INSERT INTO crm.customers(tenant_id,display_name)
    VALUES (v_tenant,p_display_name) RETURNING customer_id INTO v_customer;
  INSERT INTO crm.customer_identifiers(tenant_id,customer_id,kind,issuer,normalized_value,verified_at)
    VALUES (v_tenant,v_customer,p_kind,p_issuer,p_value,now());
  RETURN v_customer;
END $$;
REVOKE ALL ON FUNCTION crm.resolve_verified_customer(text,text,text,text) FROM PUBLIC;

-- These are backend prototype roles, NOT end-user access roles.
GRANT USAGE ON SCHEMA core, iam, crm TO upc_runtime;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_runtime;
GRANT SELECT ON core.tenants, crm.customers, crm.customer_identifiers, crm.customer_addresses TO upc_runtime;
GRANT USAGE ON SCHEMA crm TO upc_identity_writer;
GRANT EXECUTE ON FUNCTION crm.resolve_verified_customer(text,text,text,text) TO upc_identity_writer;

COMMIT;

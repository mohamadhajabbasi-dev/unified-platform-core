-- 0099: dormant tenant security source selectors, not runtime enforcement.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE iam.security_policies (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 policy_id uuid NOT NULL DEFAULT gen_random_uuid(),
 source_network cidr,
 source_country text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,policy_id),
 CHECK ((source_network IS NOT NULL AND source_country IS NULL) OR
        (source_network IS NULL AND source_country IS NOT NULL AND source_country ~ '^[A-Z]{2}$')),
 UNIQUE(tenant_id,source_network),
 UNIQUE(tenant_id,source_country)
);
ALTER TABLE iam.security_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.security_policies FORCE ROW LEVEL SECURITY;
REVOKE ALL ON iam.security_policies FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver,upc_outbox_capture;
COMMENT ON TABLE iam.security_policies IS 'Dormant synthetic tenant source selectors only; CIDR or two-uppercase-letter country syntax, not country validity, geolocation, allow/deny, rule precedence, authentication, credential or enforcement authority. No secrets or runtime grants.';
COMMIT;

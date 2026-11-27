-- 0088: dormant tenant authentication session metadata; NOT an authentication mechanism.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE TABLE iam.user_auth_sessions (
 tenant_id uuid NOT NULL,
 user_id uuid NOT NULL,
 session_id uuid NOT NULL DEFAULT gen_random_uuid(),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,session_id),
 -- A session belongs to an existing membership, not a second identity.
 -- Prototype only: preserve existing membership deletion; no final retention policy.
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id) ON DELETE CASCADE
);
CREATE INDEX user_auth_sessions_membership_idx ON iam.user_auth_sessions(tenant_id,user_id);
ALTER TABLE iam.user_auth_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE iam.user_auth_sessions FORCE ROW LEVEL SECURITY;
-- No policy, application grant, writer, token, issuer, or session validation:
-- even an accidental table grant cannot expose rows under normal RLS.
REVOKE ALL ON iam.user_auth_sessions FROM PUBLIC,upc_runtime,upc_identity_writer,upc_platform_approver;
COMMENT ON TABLE iam.user_auth_sessions IS 'Dormant synthetic tenant membership session metadata; session_id is not a credential. No runtime authentication or authorization.';
COMMIT;

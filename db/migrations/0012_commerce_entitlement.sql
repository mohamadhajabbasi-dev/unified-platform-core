-- 0012: explicit purchased modules, independent from approval decisions.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO platform.modules(module_key,version_label) VALUES('commerce','0.1');
CREATE TABLE platform.subscription_modules (
 tenant_id uuid NOT NULL,
 subscription_id uuid NOT NULL,
 module_id uuid NOT NULL REFERENCES platform.modules(module_id),
 specified_by uuid NOT NULL REFERENCES core.users(user_id),
 specified_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,subscription_id,module_id),
 FOREIGN KEY(tenant_id,subscription_id) REFERENCES platform.subscriptions(tenant_id,subscription_id)
);
ALTER TABLE platform.subscription_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform.subscription_modules FORCE ROW LEVEL SECURITY;
CREATE POLICY subscription_modules_read ON platform.subscription_modules FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('platform.billing.read'));
CREATE POLICY subscription_modules_admin ON platform.subscription_modules FOR ALL TO upc_billing_executor USING(true) WITH CHECK(true);
GRANT SELECT ON platform.subscription_modules TO upc_runtime;
GRANT SELECT,INSERT ON platform.subscription_modules TO upc_billing_executor;
GRANT SELECT ON platform.modules TO upc_billing_executor;
-- Use same transaction lock as invoice issuance. Scope cannot be expanded after invoicing.
CREATE FUNCTION platform.specify_purchased_module(p_tenant uuid,p_subscription uuid,p_module text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid:=platform.require_billing_admin(); mid uuid;
BEGIN
 IF p_tenant IS NULL OR p_subscription IS NULL OR p_module IS NULL THEN
  RAISE EXCEPTION 'Subscription and module required' USING ERRCODE='22023'; END IF;
 SELECT module_id INTO mid FROM platform.modules WHERE module_key=p_module;
 IF NOT FOUND THEN RAISE EXCEPTION 'Module unavailable' USING ERRCODE='23503'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('platform-invoice',p_tenant,p_subscription)::text,0));
 IF EXISTS(SELECT 1 FROM platform.subscription_modules WHERE tenant_id=p_tenant AND subscription_id=p_subscription AND module_id=mid)
 THEN RETURN mid; END IF;
 IF EXISTS(SELECT 1 FROM platform.subscription_invoices WHERE tenant_id=p_tenant AND subscription_id=p_subscription)
 THEN RAISE EXCEPTION 'Invoiced term cannot gain purchased modules' USING ERRCODE='23514'; END IF;
 INSERT INTO platform.subscription_modules(tenant_id,subscription_id,module_id,specified_by)
 VALUES(p_tenant,p_subscription,mid,actor);
 RETURN mid;
END $$;
ALTER FUNCTION platform.specify_purchased_module(uuid,uuid,text) OWNER TO upc_billing_executor;
REVOKE ALL ON FUNCTION platform.specify_purchased_module(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION platform.specify_purchased_module(uuid,uuid,text) TO upc_platform_approver;

-- Private, tenant-scoped reader exposes only a Boolean, not billing records.
GRANT SELECT ON platform.subscription_modules,platform.subscriptions,platform.subscription_invoices,platform.billing_payments TO upc_policy_reader;
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['platform.subscription_modules'::regclass,'platform.subscriptions'::regclass,
 'platform.subscription_invoices'::regclass,'platform.billing_payments'::regclass] LOOP
 EXECUTE format('CREATE POLICY entitlement_scope ON %s FOR SELECT TO upc_policy_reader USING(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
CREATE FUNCTION platform.has_paid_entitlement(p_module text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(
 SELECT 1 FROM platform.subscription_modules sm JOIN platform.modules m USING(module_id)
 JOIN platform.subscriptions s USING(tenant_id,subscription_id)
 JOIN platform.subscription_invoices i USING(tenant_id,subscription_id)
 JOIN platform.billing_payments p USING(tenant_id,invoice_id)
 WHERE sm.tenant_id=iam.current_tenant_id() AND m.module_key=p_module
 AND s.service_dates @> (statement_timestamp() AT TIME ZONE 'UTC')::date
 AND p.amount=s.fee AND p.currency=s.currency AND p.captured_at<=statement_timestamp()
 )
$$;
ALTER FUNCTION platform.has_paid_entitlement(text) OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION platform.has_paid_entitlement(text) FROM PUBLIC;
CREATE FUNCTION platform.commerce_eligible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT platform.has_paid_entitlement('commerce') AND platform.module_enabled('commerce')
$$;
ALTER FUNCTION platform.commerce_eligible() OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION platform.commerce_eligible() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION platform.has_paid_entitlement(text),platform.commerce_eligible() TO upc_runtime;
COMMIT;

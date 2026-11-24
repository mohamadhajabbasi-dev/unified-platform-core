-- 0010: platform subscription billing, separate from tenant sales and journals.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO iam.permissions VALUES ('platform.billing.read','Read own tenant subscription invoices and receipts');
CREATE ROLE upc_billing_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_billing_recorder NOLOGIN NOSUPERUSER NOBYPASSRLS;
-- A subscription is an immutable priced service term; renewals are new terms.
CREATE TABLE platform.subscriptions (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 subscription_id uuid NOT NULL DEFAULT gen_random_uuid(),
 request_key text NOT NULL CHECK(btrim(request_key)=request_key AND length(request_key) BETWEEN 1 AND 200),
 service_dates daterange NOT NULL CHECK(NOT isempty(service_dates) AND NOT lower_inf(service_dates)
 AND NOT upper_inf(service_dates) AND isfinite(lower(service_dates)) AND isfinite(upper(service_dates))),
 description text NOT NULL CHECK(btrim(description)<>''),
 fee numeric(20,4) NOT NULL CHECK(fee>0 AND fee<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 created_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,subscription_id), UNIQUE(tenant_id,request_key),
 EXCLUDE USING gist(tenant_id WITH =,service_dates WITH &&)
);
-- One invoice per immutable term. Its amount is derived from the term.
CREATE TABLE platform.subscription_invoices (
 tenant_id uuid NOT NULL,
 invoice_id uuid NOT NULL DEFAULT gen_random_uuid(),
 subscription_id uuid NOT NULL,
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 issued_by uuid NOT NULL REFERENCES core.users(user_id),
 due_on date NOT NULL CHECK(isfinite(due_on)),
 PRIMARY KEY(tenant_id,invoice_id), UNIQUE(tenant_id,subscription_id),
 FOREIGN KEY(tenant_id,subscription_id) REFERENCES platform.subscriptions(tenant_id,subscription_id)
);
CREATE TABLE platform.billing_payments (
 tenant_id uuid NOT NULL,
 billing_payment_id uuid NOT NULL DEFAULT gen_random_uuid(),
 invoice_id uuid NOT NULL,
 provider text NOT NULL CHECK(btrim(provider)=provider AND length(provider) BETWEEN 1 AND 100),
 provider_account text NOT NULL CHECK(btrim(provider_account)=provider_account AND length(provider_account) BETWEEN 1 AND 200),
 provider_reference text NOT NULL CHECK(btrim(provider_reference)=provider_reference AND length(provider_reference) BETWEEN 1 AND 200),
 amount numeric(20,4) NOT NULL CHECK(amount>0 AND amount<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 captured_at timestamptz NOT NULL CHECK(isfinite(captured_at)),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,billing_payment_id), UNIQUE(tenant_id,invoice_id),
 UNIQUE(provider,provider_account,provider_reference),
 FOREIGN KEY(tenant_id,invoice_id) REFERENCES platform.subscription_invoices(tenant_id,invoice_id)
);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['platform.subscriptions'::regclass,'platform.subscription_invoices'::regclass,'platform.billing_payments'::regclass] LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY tenant_billing_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''platform.billing.read''))',rel);
  EXECUTE format('CREATE POLICY private_billing_executor ON %s FOR ALL TO upc_billing_executor USING(true) WITH CHECK(true)',rel);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA platform,iam TO upc_billing_executor;
GRANT USAGE ON SCHEMA platform TO upc_billing_recorder;
GRANT SELECT ON iam.platform_staff_assignments TO upc_billing_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_billing_executor;
GRANT SELECT,INSERT ON platform.subscriptions,platform.subscription_invoices,platform.billing_payments TO upc_billing_executor;
GRANT SELECT ON platform.subscriptions,platform.subscription_invoices,platform.billing_payments TO upc_runtime;
-- Billing must remain readable to authorized tenant members even when a commercial module expires.
-- Private executor cannot be assumed by runtime. Require independently assigned active platform superadmin.
CREATE FUNCTION platform.require_billing_admin() RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE actor uuid;
BEGIN
 SELECT user_id INTO actor FROM iam.platform_staff_assignments
 WHERE login_role=session_user::name AND is_superadmin AND revoked_at IS NULL;
 IF actor IS NULL OR iam.current_tenant_id() IS NOT NULL THEN
  RAISE EXCEPTION 'Active platform billing administrator required' USING ERRCODE='42501';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Billing writes require READ COMMITTED' USING ERRCODE='25000'; END IF;
 RETURN actor;
END $$;
ALTER FUNCTION platform.require_billing_admin() OWNER TO upc_billing_executor;
REVOKE ALL ON FUNCTION platform.require_billing_admin() FROM PUBLIC;
CREATE FUNCTION platform.create_subscription(p_tenant uuid,p_key text,p_start date,p_end date,p_description text,p_fee numeric,p_currency text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid:=platform.require_billing_admin(); prior platform.subscriptions%ROWTYPE; sid uuid;
BEGIN
 IF p_tenant IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_start IS NULL OR p_end IS NULL OR NOT isfinite(p_start) OR NOT isfinite(p_end) OR p_end<=p_start
 OR p_description IS NULL OR btrim(p_description)='' OR p_fee IS NULL OR p_fee<=0 OR p_fee='NaN'::numeric
 OR p_fee>=1e16::numeric OR p_fee<>round(p_fee,4) OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' THEN
  RAISE EXCEPTION 'Invalid subscription term' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('platform-subscription',p_tenant,p_key)::text,0));
 SELECT * INTO prior FROM platform.subscriptions WHERE tenant_id=p_tenant AND request_key=p_key;
 IF FOUND THEN
  IF prior.service_dates<>daterange(p_start,p_end,'[)') OR prior.description<>p_description OR prior.fee<>p_fee OR prior.currency<>p_currency
  THEN RAISE EXCEPTION 'Subscription idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.subscription_id;
 END IF;
 INSERT INTO platform.subscriptions(tenant_id,request_key,service_dates,description,fee,currency,created_by)
 VALUES(p_tenant,p_key,daterange(p_start,p_end,'[)'),p_description,p_fee,p_currency,actor) RETURNING subscription_id INTO sid;
 RETURN sid;
END $$;
CREATE FUNCTION platform.issue_subscription_invoice(p_tenant uuid,p_subscription uuid,p_due date)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid:=platform.require_billing_admin(); prior platform.subscription_invoices%ROWTYPE; iid uuid;
BEGIN
 IF p_tenant IS NULL OR p_subscription IS NULL OR p_due IS NULL OR NOT isfinite(p_due) THEN RAISE EXCEPTION 'Invalid invoice' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('platform-invoice',p_tenant,p_subscription)::text,0));
 SELECT * INTO prior FROM platform.subscription_invoices WHERE tenant_id=p_tenant AND subscription_id=p_subscription;
 IF FOUND THEN
  IF prior.due_on<>p_due THEN RAISE EXCEPTION 'Invoice idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.invoice_id;
 END IF;
 IF p_due<(clock_timestamp() AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'Due date already elapsed' USING ERRCODE='22023'; END IF;
 INSERT INTO platform.subscription_invoices(tenant_id,subscription_id,issued_by,due_on)
 VALUES(p_tenant,p_subscription,actor,p_due) RETURNING invoice_id INTO iid;
 RETURN iid;
END $$;
-- Only an independently verified full receipt is recorded. No actual charge.
CREATE FUNCTION platform.record_billing_payment(p_tenant uuid,p_invoice uuid,p_provider text,p_account text,p_reference text,
 p_amount numeric,p_currency text,p_captured_at timestamptz) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor uuid:=platform.require_billing_admin(); prior platform.billing_payments%ROWTYPE; fee numeric; cur text; issued timestamptz; pid uuid;
BEGIN
 IF p_tenant IS NULL OR p_invoice IS NULL OR p_provider IS NULL OR btrim(p_provider)<>p_provider OR length(p_provider) NOT BETWEEN 1 AND 100
 OR p_account IS NULL OR btrim(p_account)<>p_account OR length(p_account) NOT BETWEEN 1 AND 200
 OR p_reference IS NULL OR btrim(p_reference)<>p_reference OR length(p_reference) NOT BETWEEN 1 AND 200
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_amount<>round(p_amount,4)
 OR p_currency IS NULL OR p_captured_at IS NULL OR NOT isfinite(p_captured_at) OR p_captured_at>clock_timestamp()
 THEN RAISE EXCEPTION 'Invalid verified billing receipt' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('platform-billing-reference',p_provider,p_account,p_reference)::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('platform-billing-invoice',p_tenant,p_invoice)::text,0));
 SELECT * INTO prior FROM platform.billing_payments WHERE provider=p_provider AND provider_account=p_account AND provider_reference=p_reference;
 IF FOUND THEN
  IF prior.tenant_id<>p_tenant OR prior.invoice_id<>p_invoice OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.captured_at<>p_captured_at
  THEN RAISE EXCEPTION 'Billing receipt idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.billing_payment_id;
 END IF;
 SELECT s.fee,s.currency,i.issued_at INTO fee,cur,issued FROM platform.subscription_invoices i
 JOIN platform.subscriptions s USING(tenant_id,subscription_id) WHERE i.tenant_id=p_tenant AND i.invoice_id=p_invoice;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invoice unavailable' USING ERRCODE='23503'; END IF;
 IF p_amount<>fee OR p_currency<>cur OR p_captured_at<issued THEN RAISE EXCEPTION 'Receipt does not match invoice' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM platform.billing_payments WHERE tenant_id=p_tenant AND invoice_id=p_invoice) THEN
  RAISE EXCEPTION 'Invoice already paid; reconcile extra capture' USING ERRCODE='23505'; END IF;
 INSERT INTO platform.billing_payments(tenant_id,invoice_id,provider,provider_account,provider_reference,amount,currency,captured_at,recorded_by)
 VALUES(p_tenant,p_invoice,p_provider,p_account,p_reference,p_amount,p_currency,p_captured_at,actor) RETURNING billing_payment_id INTO pid;
 RETURN pid;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['platform.create_subscription(uuid,text,date,date,text,numeric,text)'::regprocedure,
 'platform.issue_subscription_invoice(uuid,uuid,date)'::regprocedure,
 'platform.record_billing_payment(uuid,uuid,text,text,text,numeric,text,timestamptz)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_billing_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION platform.create_subscription(uuid,text,date,date,text,numeric,text),
 platform.issue_subscription_invoice(uuid,uuid,date) TO upc_platform_approver;
GRANT EXECUTE ON FUNCTION platform.record_billing_payment(uuid,uuid,text,text,text,numeric,text,timestamptz) TO upc_billing_recorder;
CREATE VIEW platform.billing_invoice_status WITH(security_invoker=true) AS
 SELECT i.tenant_id,i.invoice_id,i.subscription_id,s.service_dates,s.fee,s.currency,i.due_on,
 CASE WHEN p.billing_payment_id IS NOT NULL THEN 'paid' WHEN i.due_on<(statement_timestamp() AT TIME ZONE 'UTC')::date THEN 'overdue' ELSE 'unpaid' END AS status
 FROM platform.subscription_invoices i JOIN platform.subscriptions s USING(tenant_id,subscription_id)
 LEFT JOIN platform.billing_payments p USING(tenant_id,invoice_id);
GRANT SELECT ON platform.billing_invoice_status TO upc_runtime;
-- No grant to tenant finance, no module enablement, no duplicate revenue journal.
COMMIT;

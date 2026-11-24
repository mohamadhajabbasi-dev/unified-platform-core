-- 0008: tenant double-entry accounting foundation. No platform billing.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
CREATE SCHEMA finance;
REVOKE ALL ON SCHEMA finance FROM PUBLIC;
CREATE ROLE upc_finance_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_finance_checker NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('finance.read','Read tenant accounts and posted journal'),
 ('finance.accounts.write','Create tenant chart of accounts'),
 ('finance.post.manual','Post balanced manual journal'),
 ('finance.post.cash','Post verified sales capture and refund');
INSERT INTO platform.modules(module_key,version_label) VALUES ('finance','0.1');

CREATE TABLE finance.accounts (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 account_id uuid NOT NULL DEFAULT gen_random_uuid(),
 account_code text NOT NULL CHECK(btrim(account_code)=account_code AND length(account_code) BETWEEN 1 AND 100),
 name text NOT NULL CHECK(btrim(name)<>''),
 account_type text NOT NULL CHECK(account_type IN ('asset','liability','equity','revenue','expense')),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 PRIMARY KEY(tenant_id,account_id), UNIQUE(tenant_id,account_code), UNIQUE(tenant_id,account_id,currency)
);
CREATE TABLE finance.journal_entries (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 entry_id uuid NOT NULL DEFAULT gen_random_uuid(),
 source_key text NOT NULL CHECK(length(source_key) BETWEEN 1 AND 250),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 memo text NOT NULL CHECK(btrim(memo)<>''),
 payment_id uuid,
 refund_id uuid,
 posted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 posted_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,entry_id), UNIQUE(tenant_id,source_key), UNIQUE(tenant_id,entry_id,currency),
 UNIQUE(tenant_id,payment_id), UNIQUE(tenant_id,refund_id),
 FOREIGN KEY(tenant_id,payment_id) REFERENCES sales.payments(tenant_id,payment_id),
 FOREIGN KEY(tenant_id,refund_id) REFERENCES sales.refunds(tenant_id,refund_id),
 CHECK ((payment_id IS NULL AND refund_id IS NULL AND source_key LIKE 'manual:%') OR
 (payment_id IS NOT NULL AND refund_id IS NULL AND source_key='payment:'||payment_id::text) OR
 (refund_id IS NOT NULL AND payment_id IS NULL AND source_key='refund:'||refund_id::text))
);
CREATE INDEX journal_posted_idx ON finance.journal_entries(tenant_id,posted_at);
-- Positive signed amount is debit, negative is credit. One line per account per entry.
CREATE TABLE finance.journal_lines (
 tenant_id uuid NOT NULL,
 entry_id uuid NOT NULL,
 account_id uuid NOT NULL,
 currency text NOT NULL,
 amount numeric(40,4) NOT NULL CHECK(amount<>0 AND amount<>'NaN'::numeric),
 PRIMARY KEY(tenant_id,entry_id,account_id),
 FOREIGN KEY(tenant_id,entry_id,currency) REFERENCES finance.journal_entries(tenant_id,entry_id,currency),
 FOREIGN KEY(tenant_id,account_id,currency) REFERENCES finance.accounts(tenant_id,account_id,currency)
);
CREATE INDEX journal_lines_account_idx ON finance.journal_lines(tenant_id,account_id);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['finance.accounts'::regclass,'finance.journal_entries'::regclass,'finance.journal_lines'::regclass] LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY finance_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''finance.read'') AND platform.module_enabled(''finance''))',rel);
  EXECUTE format('CREATE POLICY finance_executor_scope ON %s FOR ALL TO upc_finance_executor USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
CREATE POLICY account_insert ON finance.accounts FOR INSERT TO upc_runtime
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('finance.read')
 AND iam.has_permission('finance.accounts.write') AND platform.module_enabled('finance'));
GRANT USAGE ON SCHEMA finance TO upc_runtime,upc_finance_executor,upc_finance_checker;
GRANT SELECT ON finance.accounts,finance.journal_entries,finance.journal_lines TO upc_runtime,upc_finance_executor;
GRANT INSERT ON finance.accounts TO upc_runtime;
GRANT INSERT ON finance.journal_entries,finance.journal_lines TO upc_finance_executor;
GRANT USAGE ON SCHEMA iam,platform,sales TO upc_finance_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_finance_executor;
-- Finance may reconcile verified historical cash events even when sales is disabled;
-- only the private executor can read these source tables, tenant scope still applies.
GRANT SELECT ON sales.payments,sales.refunds TO upc_finance_executor;
CREATE POLICY finance_payment_dependency ON sales.payments FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY finance_refund_dependency ON sales.refunds FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());

-- Independent constraint checker, not a login or runtime role. Only its trigger
-- can read journal rows across tenants to check each newly posted entry.
GRANT SELECT ON finance.journal_entries,finance.journal_lines TO upc_finance_checker;
CREATE POLICY journal_checker ON finance.journal_entries FOR SELECT TO upc_finance_checker USING(true);
CREATE POLICY journal_checker ON finance.journal_lines FOR SELECT TO upc_finance_checker USING(true);
CREATE FUNCTION finance.check_balanced_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE n bigint; balance numeric;
BEGIN
 SELECT count(*),COALESCE(sum(amount),0) INTO n,balance FROM finance.journal_lines
 WHERE tenant_id=NEW.tenant_id AND entry_id=NEW.entry_id;
 IF n<2 OR balance<>0 THEN RAISE EXCEPTION 'Journal entry must have at least two balanced lines' USING ERRCODE='23514'; END IF;
 RETURN NULL;
END $$;
ALTER FUNCTION finance.check_balanced_entry() OWNER TO upc_finance_checker;
REVOKE ALL ON FUNCTION finance.check_balanced_entry() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER journal_header_balanced AFTER INSERT ON finance.journal_entries
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION finance.check_balanced_entry();
CREATE CONSTRAINT TRIGGER journal_lines_balanced AFTER INSERT ON finance.journal_lines
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION finance.check_balanced_entry();
CREATE FUNCTION finance.reject_posted_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'Posted journal immutable; use a correcting entry' USING ERRCODE='55000'; END $$;
REVOKE ALL ON FUNCTION finance.reject_posted_mutation() FROM PUBLIC;
CREATE TRIGGER posted_header_immutable BEFORE UPDATE OR DELETE ON finance.journal_entries
 FOR EACH ROW EXECUTE FUNCTION finance.reject_posted_mutation();
CREATE TRIGGER posted_lines_immutable BEFORE UPDATE OR DELETE ON finance.journal_lines
 FOR EACH ROW EXECUTE FUNCTION finance.reject_posted_mutation();

CREATE FUNCTION finance.require_access(p_permission text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR NOT platform.module_enabled('finance') THEN
  RAISE EXCEPTION 'Finance access denied' USING ERRCODE='42501';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Journal posting requires READ COMMITTED' USING ERRCODE='25000';
 END IF;
 RETURN t;
END $$;
-- Private writer; only explicit manual/cash APIs may call it.
CREATE FUNCTION finance.write_entry(p_tenant uuid,p_key text,p_currency text,p_memo text,p_lines jsonb,p_payment uuid,p_refund uuid)
RETURNS uuid LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE prior finance.journal_entries%ROWTYPE; eid uuid; normalized jsonb; existing jsonb; n integer; balance numeric;
BEGIN
 IF p_tenant IS DISTINCT FROM iam.current_tenant_id() OR p_tenant IS NULL
 OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' OR p_memo IS NULL OR btrim(p_memo)=''
 OR p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION 'Invalid journal' USING ERRCODE='22023'; END IF;
 n:=jsonb_array_length(p_lines);
 IF n NOT BETWEEN 2 AND 100 THEN RAISE EXCEPTION 'Invalid line count' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) AS x(account_id uuid,amount numeric)
  WHERE x.account_id IS NULL OR x.amount IS NULL OR x.amount=0 OR x.amount='NaN'::numeric
  OR abs(x.amount)>=1e36::numeric OR x.amount<>round(x.amount,4))
 OR (SELECT count(DISTINCT x.account_id) FROM jsonb_to_recordset(p_lines) AS x(account_id uuid))<>n THEN
  RAISE EXCEPTION 'Invalid or duplicate journal line' USING ERRCODE='22023';
 END IF;
 SELECT sum(x.amount),jsonb_agg(jsonb_build_array(x.account_id,x.amount) ORDER BY x.account_id)
 INTO balance,normalized FROM jsonb_to_recordset(p_lines) AS x(account_id uuid,amount numeric);
 IF balance<>0 THEN RAISE EXCEPTION 'Unbalanced journal' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('finance-journal',p_tenant,p_key)::text,0));
 SELECT * INTO prior FROM finance.journal_entries WHERE tenant_id=p_tenant AND source_key=p_key;
 IF FOUND THEN
  SELECT jsonb_agg(jsonb_build_array(account_id,amount) ORDER BY account_id) INTO existing
   FROM finance.journal_lines WHERE tenant_id=p_tenant AND entry_id=prior.entry_id;
  IF prior.currency<>p_currency OR prior.memo<>p_memo OR prior.payment_id IS DISTINCT FROM p_payment
   OR prior.refund_id IS DISTINCT FROM p_refund OR existing IS DISTINCT FROM normalized THEN
   RAISE EXCEPTION 'Journal idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.entry_id;
 END IF;
 IF (SELECT count(*) FROM finance.accounts a JOIN jsonb_to_recordset(p_lines) AS x(account_id uuid)
  ON a.account_id=x.account_id WHERE a.tenant_id=p_tenant AND a.currency=p_currency)<>n
 THEN RAISE EXCEPTION 'Account unavailable in tenant or currency' USING ERRCODE='23503'; END IF;
 INSERT INTO finance.journal_entries(tenant_id,source_key,currency,memo,payment_id,refund_id,posted_by)
 VALUES(p_tenant,p_key,p_currency,p_memo,p_payment,p_refund,iam.current_user_id()) RETURNING entry_id INTO eid;
 INSERT INTO finance.journal_lines(tenant_id,entry_id,account_id,currency,amount)
 SELECT p_tenant,eid,x.account_id,p_currency,x.amount FROM jsonb_to_recordset(p_lines) AS x(account_id uuid,amount numeric);
 RETURN eid;
END $$;
ALTER FUNCTION finance.require_access(text) OWNER TO upc_finance_executor;
ALTER FUNCTION finance.write_entry(uuid,text,text,text,jsonb,uuid,uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.require_access(text),finance.write_entry(uuid,text,text,text,jsonb,uuid,uuid) FROM PUBLIC;

CREATE FUNCTION finance.post_manual(p_key text,p_currency text,p_memo text,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.manual');
BEGIN
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200 THEN
  RAISE EXCEPTION 'Invalid journal key' USING ERRCODE='22023';
 END IF;
 RETURN finance.write_entry(t,'manual:'||p_key,p_currency,p_memo,p_lines,NULL,NULL);
END $$;
-- Capture = debit clearing asset, credit customer advance liability.
-- Revenue recognition is a separate future event, never inferred here.
CREATE FUNCTION finance.post_capture(p_payment uuid,p_clearing uuid,p_advance uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cash'); pay sales.payments%ROWTYPE;
BEGIN
 SELECT * INTO pay FROM sales.payments WHERE tenant_id=t AND payment_id=p_payment;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment unavailable' USING ERRCODE='23503'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_clearing AND currency=pay.currency AND account_type='asset')
 OR NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_advance AND currency=pay.currency AND account_type='liability')
 THEN RAISE EXCEPTION 'Capture requires matching asset and liability accounts' USING ERRCODE='23503'; END IF;
 RETURN finance.write_entry(t,'payment:'||p_payment::text,pay.currency,'Verified capture',
  jsonb_build_array(jsonb_build_object('account_id',p_clearing,'amount',pay.amount),
   jsonb_build_object('account_id',p_advance,'amount',-pay.amount)),p_payment,NULL);
END $$;
-- A full verified refund reverses the exact original posted capture accounts.
CREATE FUNCTION finance.post_refund(p_refund uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cash'); ref sales.refunds%ROWTYPE;
 original finance.journal_entries%ROWTYPE; reversed jsonb; debits numeric;
BEGIN
 SELECT * INTO ref FROM sales.refunds WHERE tenant_id=t AND refund_id=p_refund;
 IF NOT FOUND THEN RAISE EXCEPTION 'Refund unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO original FROM finance.journal_entries WHERE tenant_id=t AND payment_id=ref.payment_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Post original capture first' USING ERRCODE='23514'; END IF;
 SELECT jsonb_agg(jsonb_build_object('account_id',account_id,'amount',-amount) ORDER BY account_id),
  sum(amount) FILTER(WHERE amount>0) INTO reversed,debits
 FROM finance.journal_lines WHERE tenant_id=t AND entry_id=original.entry_id;
 IF debits IS DISTINCT FROM ref.amount OR original.currency<>ref.currency THEN
  RAISE EXCEPTION 'Refund does not match posted capture' USING ERRCODE='23514';
 END IF;
 RETURN finance.write_entry(t,'refund:'||p_refund::text,ref.currency,'Verified full refund',reversed,NULL,p_refund);
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['finance.post_manual(text,text,text,jsonb)'::regprocedure,
 'finance.post_capture(uuid,uuid,uuid)'::regprocedure,'finance.post_refund(uuid)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_finance_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
CREATE VIEW finance.trial_balance WITH(security_invoker=true) AS
 SELECT a.tenant_id,a.account_id,a.account_code,a.currency,
 COALESCE(sum(l.amount) FILTER(WHERE l.amount>0),0) AS debit,
 COALESCE(-sum(l.amount) FILTER(WHERE l.amount<0),0) AS credit,
 COALESCE(sum(l.amount),0) AS net_debit
 FROM finance.accounts a LEFT JOIN finance.journal_lines l USING(tenant_id,account_id,currency)
 GROUP BY a.tenant_id,a.account_id,a.account_code,a.currency;
GRANT SELECT ON finance.trial_balance TO upc_runtime;
COMMIT;

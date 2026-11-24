-- 0009: fiscal period gate and provisional fulfillment revenue recognition.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
INSERT INTO iam.permissions VALUES ('finance.period.manage','Open and close periods'),('finance.post.revenue','Recognize fulfilled order revenue');
CREATE TABLE finance.fiscal_periods (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 period_id uuid NOT NULL DEFAULT gen_random_uuid(),
 period_name text NOT NULL CHECK(btrim(period_name)<>''),
 dates daterange NOT NULL CHECK(NOT isempty(dates) AND NOT lower_inf(dates) AND NOT upper_inf(dates)
 AND isfinite(lower(dates)) AND isfinite(upper(dates))),
 opened_by uuid NOT NULL REFERENCES core.users(user_id),
 opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 closed_by uuid REFERENCES core.users(user_id),
 closed_at timestamptz,
 PRIMARY KEY(tenant_id,period_id), UNIQUE(tenant_id,period_name),
 EXCLUDE USING gist(tenant_id WITH =,dates WITH &&),
 CHECK((closed_at IS NULL)=(closed_by IS NULL)), CHECK(closed_at IS NULL OR closed_at>=opened_at)
);
ALTER TABLE finance.fiscal_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.fiscal_periods FORCE ROW LEVEL SECURITY;
CREATE POLICY period_read ON finance.fiscal_periods FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('finance.read') AND platform.module_enabled('finance'));
CREATE POLICY period_executor ON finance.fiscal_periods FOR ALL TO upc_finance_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT SELECT ON finance.fiscal_periods TO upc_runtime;
GRANT SELECT,INSERT ON finance.fiscal_periods TO upc_finance_executor;
GRANT UPDATE(closed_at,closed_by) ON finance.fiscal_periods TO upc_finance_executor;
ALTER TABLE finance.journal_entries ADD COLUMN period_id uuid NOT NULL;
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,period_id) REFERENCES finance.fiscal_periods(tenant_id,period_id);
ALTER TABLE finance.journal_entries ADD COLUMN recognition_order_id uuid;
ALTER TABLE finance.journal_entries ADD UNIQUE(tenant_id,recognition_order_id);
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,recognition_order_id) REFERENCES sales.orders(tenant_id,order_id);
DO $$
DECLARE n name;
BEGIN
 SELECT conname INTO STRICT n FROM pg_constraint WHERE conrelid='finance.journal_entries'::regclass
 AND contype='c' AND pg_get_constraintdef(oid) LIKE '%manual:%';
 EXECUTE format('ALTER TABLE finance.journal_entries DROP CONSTRAINT %I',n);
END $$;
ALTER TABLE finance.journal_entries ADD CONSTRAINT journal_source_kind CHECK(
 (recognition_order_id IS NULL AND (
  (payment_id IS NULL AND refund_id IS NULL AND source_key LIKE 'manual:%') OR
  (payment_id IS NOT NULL AND refund_id IS NULL AND source_key='payment:'||payment_id::text) OR
  (refund_id IS NOT NULL AND payment_id IS NULL AND source_key='refund:'||refund_id::text)))
 OR (recognition_order_id IS NOT NULL AND payment_id IS NULL AND refund_id IS NULL
  AND source_key='revenue:'||recognition_order_id::text));
CREATE INDEX journal_period_idx ON finance.journal_entries(tenant_id,period_id);
CREATE FUNCTION finance.lock_periods(p_tenant uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('finance-period',p_tenant)::text,0))
$$;
ALTER FUNCTION finance.lock_periods(uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.lock_periods(uuid) FROM PUBLIC;
CREATE FUNCTION finance.assign_period() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE pid uuid;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'Posting requires READ COMMITTED' USING ERRCODE='25000'; END IF;
 PERFORM finance.lock_periods(NEW.tenant_id);
 NEW.posted_at:=clock_timestamp();
 SELECT period_id INTO pid FROM finance.fiscal_periods WHERE tenant_id=NEW.tenant_id
 AND dates @> (NEW.posted_at AT TIME ZONE 'UTC')::date AND closed_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'No open fiscal period for posting date' USING ERRCODE='23514'; END IF;
 NEW.period_id:=pid;
 IF NEW.source_key LIKE 'revenue:%' THEN NEW.recognition_order_id:=substring(NEW.source_key from 9)::uuid; END IF;
 RETURN NEW;
END $$;
ALTER FUNCTION finance.assign_period() OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.assign_period() FROM PUBLIC;
CREATE TRIGGER journal_period_gate BEFORE INSERT ON finance.journal_entries FOR EACH ROW EXECUTE FUNCTION finance.assign_period();
CREATE FUNCTION finance.open_period(p_name text,p_start date,p_end date) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.period.manage'); p finance.fiscal_periods%ROWTYPE; pid uuid;
BEGIN
 IF p_name IS NULL OR btrim(p_name)='' OR p_start IS NULL OR p_end IS NULL OR NOT isfinite(p_start)
 OR NOT isfinite(p_end) OR p_end<=p_start THEN RAISE EXCEPTION 'Invalid fiscal period' USING ERRCODE='22023'; END IF;
 PERFORM finance.lock_periods(t);
 SELECT * INTO p FROM finance.fiscal_periods WHERE tenant_id=t AND period_name=p_name;
 IF FOUND THEN
  IF p.dates<>daterange(p_start,p_end,'[)') THEN RAISE EXCEPTION 'Period key conflict' USING ERRCODE='23505'; END IF;
  RETURN p.period_id;
 END IF;
 INSERT INTO finance.fiscal_periods(tenant_id,period_name,dates,opened_by)
 VALUES(t,p_name,daterange(p_start,p_end,'[)'),iam.current_user_id()) RETURNING period_id INTO pid;
 RETURN pid;
END $$;
CREATE FUNCTION finance.close_period(p_period uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.period.manage'); p finance.fiscal_periods%ROWTYPE;
BEGIN
 PERFORM finance.lock_periods(t);
 SELECT * INTO p FROM finance.fiscal_periods WHERE tenant_id=t AND period_id=p_period;
 IF NOT FOUND THEN RAISE EXCEPTION 'Period unavailable' USING ERRCODE='23503'; END IF;
 IF p.closed_at IS NOT NULL THEN RETURN p_period; END IF;
 UPDATE finance.fiscal_periods SET closed_at=clock_timestamp(),closed_by=iam.current_user_id() WHERE tenant_id=t AND period_id=p_period;
 RETURN p_period;
END $$;
GRANT SELECT ON sales.orders TO upc_finance_executor;
CREATE POLICY finance_order_dependency ON sales.orders FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE FUNCTION finance.recognize_order(p_order uuid,p_revenue uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.revenue'); o sales.orders%ROWTYPE;
 pay sales.payments%ROWTYPE; orig finance.journal_entries%ROWTYPE; advance uuid; prior uuid;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-order',t,p_order)::text,0));
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO pay FROM sales.payments WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Capture required' USING ERRCODE='23514'; END IF;
 SELECT * INTO orig FROM finance.journal_entries WHERE tenant_id=t AND payment_id=pay.payment_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Post capture first' USING ERRCODE='23514'; END IF;
 SELECT l.account_id INTO STRICT advance FROM finance.journal_lines l
 WHERE l.tenant_id=t AND l.entry_id=orig.entry_id AND l.amount=-pay.amount;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_revenue AND currency=pay.currency AND account_type='revenue')
 THEN RAISE EXCEPTION 'Revenue account unavailable' USING ERRCODE='23503'; END IF;
 SELECT entry_id INTO prior FROM finance.journal_entries WHERE tenant_id=t AND recognition_order_id=p_order;
 IF prior IS NULL AND o.state<>'fulfilled' THEN RAISE EXCEPTION 'Fulfilled order required' USING ERRCODE='23514'; END IF;
 RETURN finance.write_entry(t,'revenue:'||p_order::text,pay.currency,'Fulfilled order revenue',
  jsonb_build_array(jsonb_build_object('account_id',advance,'amount',pay.amount),
   jsonb_build_object('account_id',p_revenue,'amount',-pay.amount)),NULL,NULL);
END $$;
CREATE OR REPLACE FUNCTION finance.post_refund(p_refund uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.cash'); ref sales.refunds%ROWTYPE;
 pay sales.payments%ROWTYPE; original finance.journal_entries%ROWTYPE; recog finance.journal_entries%ROWTYPE;
 clearing uuid; debit_account uuid; reversed jsonb; debits numeric;
BEGIN
 SELECT * INTO ref FROM sales.refunds WHERE tenant_id=t AND refund_id=p_refund;
 IF NOT FOUND THEN RAISE EXCEPTION 'Refund unavailable' USING ERRCODE='23503'; END IF;
 SELECT * INTO STRICT pay FROM sales.payments WHERE tenant_id=t AND payment_id=ref.payment_id;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-order',t,pay.order_id)::text,0));
 SELECT * INTO original FROM finance.journal_entries WHERE tenant_id=t AND payment_id=ref.payment_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Post original capture first' USING ERRCODE='23514'; END IF;
 SELECT sum(amount) FILTER(WHERE amount>0) INTO debits FROM finance.journal_lines WHERE tenant_id=t AND entry_id=original.entry_id;
 IF debits IS DISTINCT FROM ref.amount OR original.currency<>ref.currency THEN RAISE EXCEPTION 'Refund does not match posted capture' USING ERRCODE='23514'; END IF;
 SELECT account_id INTO STRICT clearing FROM finance.journal_lines WHERE tenant_id=t AND entry_id=original.entry_id AND amount=ref.amount;
 SELECT * INTO recog FROM finance.journal_entries WHERE tenant_id=t AND recognition_order_id=pay.order_id;
 IF FOUND THEN
  SELECT account_id INTO STRICT debit_account FROM finance.journal_lines WHERE tenant_id=t AND entry_id=recog.entry_id AND amount=-ref.amount;
 ELSE
  SELECT account_id INTO STRICT debit_account FROM finance.journal_lines WHERE tenant_id=t AND entry_id=original.entry_id AND amount=-ref.amount;
 END IF;
 reversed:=jsonb_build_array(jsonb_build_object('account_id',debit_account,'amount',ref.amount),jsonb_build_object('account_id',clearing,'amount',-ref.amount));
 RETURN finance.write_entry(t,'refund:'||p_refund::text,ref.currency,'Verified full refund',reversed,NULL,p_refund);
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['finance.open_period(text,date,date)'::regprocedure,'finance.close_period(uuid)'::regprocedure,'finance.recognize_order(uuid,uuid)'::regprocedure] LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_finance_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
COMMIT;

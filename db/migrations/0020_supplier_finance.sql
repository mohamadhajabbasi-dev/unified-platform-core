-- 0020: verified purchase invoice and supplier settlement, posted to canonical journal.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE ROLE upc_supplier_document_verifier NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_supplier_payment_verifier NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions VALUES
 ('finance.post.purchase','Recognize verified supplier invoice'),
 ('finance.post.supplier_settlement','Record verified supplier settlement');
ALTER TABLE procurement.purchase_orders ADD UNIQUE(tenant_id,purchase_id,counterparty_id,currency);
CREATE TABLE finance.supplier_invoices (
 tenant_id uuid NOT NULL,
 invoice_id uuid NOT NULL DEFAULT gen_random_uuid(),
 purchase_id uuid NOT NULL,
 counterparty_id uuid NOT NULL,
 currency text NOT NULL,
 invoice_ref text NOT NULL CHECK(btrim(invoice_ref)=invoice_ref AND length(invoice_ref) BETWEEN 1 AND 200),
 invoice_date date NOT NULL CHECK(isfinite(invoice_date)),
 due_date date NOT NULL CHECK(isfinite(due_date) AND due_date>=invoice_date),
 amount numeric(40,4) NOT NULL CHECK(amount>0 AND amount<>'NaN'::numeric),
 evidence_digest bytea NOT NULL CHECK(octet_length(evidence_digest)=32),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,invoice_id), UNIQUE(tenant_id,purchase_id), UNIQUE(tenant_id,counterparty_id,invoice_ref),
 UNIQUE(tenant_id,invoice_id,currency),
 FOREIGN KEY(tenant_id,purchase_id,counterparty_id,currency) REFERENCES procurement.purchase_orders(tenant_id,purchase_id,counterparty_id,currency)
);
CREATE TABLE finance.supplier_settlements (
 tenant_id uuid NOT NULL,
 settlement_id uuid NOT NULL DEFAULT gen_random_uuid(),
 invoice_id uuid NOT NULL,
 currency text NOT NULL,
 payment_channel text NOT NULL CHECK(payment_channel IN ('bank','cash','other')),
 account_ref text NOT NULL CHECK(btrim(account_ref)=account_ref AND length(account_ref) BETWEEN 1 AND 200),
 payment_ref text NOT NULL CHECK(btrim(payment_ref)=payment_ref AND length(payment_ref) BETWEEN 1 AND 200),
 amount numeric(40,4) NOT NULL CHECK(amount>0 AND amount<>'NaN'::numeric),
 paid_at timestamptz NOT NULL CHECK(isfinite(paid_at)),
 evidence_digest bytea NOT NULL CHECK(octet_length(evidence_digest)=32),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,settlement_id), UNIQUE(tenant_id,payment_channel,account_ref,payment_ref),
 FOREIGN KEY(tenant_id,invoice_id,currency) REFERENCES finance.supplier_invoices(tenant_id,invoice_id,currency)
);
CREATE INDEX supplier_settlement_invoice_idx ON finance.supplier_settlements(tenant_id,invoice_id);
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['finance.supplier_invoices'::regclass,'finance.supplier_settlements'::regclass] LOOP
 EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
 EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
 EXECUTE format('CREATE POLICY supplier_finance_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''finance.read'') AND platform.module_enabled(''finance''))',rel);
 EXECUTE format('CREATE POLICY supplier_finance_private ON %s FOR ALL TO upc_finance_executor USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT ON finance.supplier_invoices,finance.supplier_settlements TO upc_runtime,upc_finance_executor;
GRANT INSERT ON finance.supplier_invoices,finance.supplier_settlements TO upc_finance_executor;
GRANT USAGE ON SCHEMA procurement TO upc_finance_executor;
GRANT USAGE ON SCHEMA finance TO upc_supplier_document_verifier,upc_supplier_payment_verifier;
GRANT SELECT ON procurement.purchase_orders,procurement.purchase_items,procurement.goods_receipts TO upc_finance_executor;
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['procurement.purchase_orders'::regclass,'procurement.purchase_items'::regclass,'procurement.goods_receipts'::regclass] LOOP
 EXECUTE format('CREATE POLICY finance_purchase_dependency ON %s FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
ALTER TABLE finance.journal_entries ADD COLUMN supplier_invoice_id uuid;
ALTER TABLE finance.journal_entries ADD COLUMN supplier_settlement_id uuid;
ALTER TABLE finance.journal_entries ADD UNIQUE(tenant_id,supplier_invoice_id);
ALTER TABLE finance.journal_entries ADD UNIQUE(tenant_id,supplier_settlement_id);
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,supplier_invoice_id) REFERENCES finance.supplier_invoices(tenant_id,invoice_id);
ALTER TABLE finance.journal_entries ADD FOREIGN KEY(tenant_id,supplier_settlement_id) REFERENCES finance.supplier_settlements(tenant_id,settlement_id);
ALTER TABLE finance.journal_entries DROP CONSTRAINT journal_source_kind;
ALTER TABLE finance.journal_entries ADD CONSTRAINT journal_source_kind CHECK(
 num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id)<=1 AND (
 (num_nonnulls(payment_id,refund_id,recognition_order_id,supplier_invoice_id,supplier_settlement_id)=0 AND source_key LIKE 'manual:%')
 OR (payment_id IS NOT NULL AND source_key='payment:'||payment_id::text)
 OR (refund_id IS NOT NULL AND source_key='refund:'||refund_id::text)
 OR (recognition_order_id IS NOT NULL AND source_key='revenue:'||recognition_order_id::text)
 OR (supplier_invoice_id IS NOT NULL AND source_key='supplier-invoice:'||supplier_invoice_id::text)
 OR (supplier_settlement_id IS NOT NULL AND source_key='supplier-settlement:'||supplier_settlement_id::text)));
CREATE OR REPLACE FUNCTION finance.assign_period() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
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
 IF NEW.source_key LIKE 'supplier-invoice:%' THEN NEW.supplier_invoice_id:=substring(NEW.source_key from 18)::uuid; END IF;
 IF NEW.source_key LIKE 'supplier-settlement:%' THEN NEW.supplier_settlement_id:=substring(NEW.source_key from 21)::uuid; END IF;
 RETURN NEW;
END $$;

-- Verified invoice and its journal are atomic. Exact full purchase match; no tax/variance here.
CREATE FUNCTION finance.record_supplier_invoice(p_purchase uuid,p_ref text,p_date date,p_due date,p_amount numeric,p_currency text,
 p_digest bytea,p_inventory uuid,p_payable uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.purchase'); o procurement.purchase_orders%ROWTYPE;
 prior finance.supplier_invoices%ROWTYPE; iid uuid; total numeric;
BEGIN
 IF NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Procurement access denied' USING ERRCODE='42501'; END IF;
 IF p_purchase IS NULL OR p_ref IS NULL OR btrim(p_ref)<>p_ref OR length(p_ref) NOT BETWEEN 1 AND 200
 OR p_date IS NULL OR NOT isfinite(p_date) OR p_date>(clock_timestamp() AT TIME ZONE 'UTC')::date
 OR p_due IS NULL OR NOT isfinite(p_due) OR p_due<p_date
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_amount>=1e36::numeric OR p_amount<>round(p_amount,4)
 OR p_currency IS NULL OR p_digest IS NULL OR octet_length(p_digest)<>32 THEN RAISE EXCEPTION 'Invalid invoice' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-order',t,p_purchase)::text,0));
 SELECT * INTO o FROM procurement.purchase_orders WHERE tenant_id=t AND purchase_id=p_purchase;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase unavailable' USING ERRCODE='23503'; END IF;
 IF o.cancelled_at IS NOT NULL OR NOT EXISTS(SELECT 1 FROM procurement.goods_receipts WHERE tenant_id=t AND purchase_id=p_purchase)
 THEN RAISE EXCEPTION 'Received purchase required' USING ERRCODE='23514'; END IF;
 SELECT sum(quantity*unit_cost) INTO total FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=p_purchase;
 IF total IS DISTINCT FROM p_amount OR o.currency<>p_currency THEN RAISE EXCEPTION 'Invoice must match received purchase cost and currency' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_inventory AND currency=p_currency AND account_type='asset')
 OR NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_payable AND currency=p_currency AND account_type='liability')
 THEN RAISE EXCEPTION 'Matching inventory asset and payable liability required' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM finance.supplier_invoices WHERE tenant_id=t AND purchase_id=p_purchase;
 IF FOUND THEN
 IF prior.invoice_ref<>p_ref OR prior.invoice_date<>p_date OR prior.due_date<>p_due OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.evidence_digest<>p_digest
 THEN RAISE EXCEPTION 'Invoice idempotency conflict' USING ERRCODE='23505'; END IF;
 iid:=prior.invoice_id;
 ELSE
 INSERT INTO finance.supplier_invoices(tenant_id,purchase_id,counterparty_id,currency,invoice_ref,invoice_date,due_date,amount,evidence_digest,recorded_by)
 VALUES(t,p_purchase,o.counterparty_id,p_currency,p_ref,p_date,p_due,p_amount,p_digest,iam.current_user_id()) RETURNING invoice_id INTO iid;
 END IF;
 PERFORM finance.write_entry(t,'supplier-invoice:'||iid::text,p_currency,'Verified supplier invoice',
 jsonb_build_array(jsonb_build_object('account_id',p_inventory,'amount',p_amount),jsonb_build_object('account_id',p_payable,'amount',-p_amount)),NULL,NULL);
 RETURN iid;
END $$;
-- Partial settlements allowed; serialize by invoice, never exceed its liability.
-- Record only an externally verified disbursement, not a payment instruction.
CREATE FUNCTION finance.record_supplier_settlement(p_invoice uuid,p_channel text,p_account_ref text,p_payment_ref text,
 p_amount numeric,p_currency text,p_paid_at timestamptz,p_digest bytea,p_cash uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.supplier_settlement'); inv finance.supplier_invoices%ROWTYPE;
 prior finance.supplier_settlements%ROWTYPE; sid uuid; payable uuid; posted uuid; paid numeric;
BEGIN
 IF p_invoice IS NULL OR p_channel IS NULL OR p_channel NOT IN ('bank','cash','other')
 OR p_account_ref IS NULL OR btrim(p_account_ref)<>p_account_ref OR length(p_account_ref) NOT BETWEEN 1 AND 200
 OR p_payment_ref IS NULL OR btrim(p_payment_ref)<>p_payment_ref OR length(p_payment_ref) NOT BETWEEN 1 AND 200
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_amount>=1e36::numeric OR p_amount<>round(p_amount,4)
 OR p_currency IS NULL OR p_paid_at IS NULL OR NOT isfinite(p_paid_at) OR p_paid_at>clock_timestamp()
 OR p_digest IS NULL OR octet_length(p_digest)<>32 THEN RAISE EXCEPTION 'Invalid verified settlement' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('supplier-payment-ref',t,p_channel,p_account_ref,p_payment_ref)::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('supplier-invoice',t,p_invoice)::text,0));
 SELECT * INTO inv FROM finance.supplier_invoices WHERE tenant_id=t AND invoice_id=p_invoice;
 IF NOT FOUND THEN RAISE EXCEPTION 'Supplier invoice unavailable' USING ERRCODE='23503'; END IF;
 IF p_currency<>inv.currency OR (p_paid_at AT TIME ZONE 'UTC')::date<inv.invoice_date THEN RAISE EXCEPTION 'Settlement currency or date mismatch' USING ERRCODE='23514'; END IF;
 SELECT entry_id INTO posted FROM finance.journal_entries WHERE tenant_id=t AND supplier_invoice_id=p_invoice;
 IF NOT FOUND THEN RAISE EXCEPTION 'Recognized invoice required' USING ERRCODE='23514'; END IF;
 SELECT account_id INTO STRICT payable FROM finance.journal_lines WHERE tenant_id=t AND entry_id=posted AND amount=-inv.amount;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_cash AND currency=p_currency AND account_type='asset')
 THEN RAISE EXCEPTION 'Matching disbursement asset account required' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM finance.supplier_settlements WHERE tenant_id=t AND payment_channel=p_channel AND account_ref=p_account_ref AND payment_ref=p_payment_ref;
 IF FOUND THEN
 IF prior.invoice_id<>p_invoice OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.paid_at<>p_paid_at OR prior.evidence_digest<>p_digest
 THEN RAISE EXCEPTION 'Settlement idempotency conflict' USING ERRCODE='23505'; END IF;
 sid:=prior.settlement_id;
 ELSE
 SELECT COALESCE(sum(amount),0) INTO paid FROM finance.supplier_settlements WHERE tenant_id=t AND invoice_id=p_invoice;
 IF paid+p_amount>inv.amount THEN RAISE EXCEPTION 'Settlement exceeds payable' USING ERRCODE='23514'; END IF;
 INSERT INTO finance.supplier_settlements(tenant_id,invoice_id,currency,payment_channel,account_ref,payment_ref,amount,paid_at,evidence_digest,recorded_by)
 VALUES(t,p_invoice,p_currency,p_channel,p_account_ref,p_payment_ref,p_amount,p_paid_at,p_digest,iam.current_user_id()) RETURNING settlement_id INTO sid;
 END IF;
 PERFORM finance.write_entry(t,'supplier-settlement:'||sid::text,p_currency,'Verified supplier settlement',
 jsonb_build_array(jsonb_build_object('account_id',payable,'amount',p_amount),jsonb_build_object('account_id',p_cash,'amount',-p_amount)),NULL,NULL);
 RETURN sid;
END $$;
ALTER FUNCTION finance.record_supplier_invoice(uuid,text,date,date,numeric,text,bytea,uuid,uuid) OWNER TO upc_finance_executor;
ALTER FUNCTION finance.record_supplier_settlement(uuid,text,text,text,numeric,text,timestamptz,bytea,uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.record_supplier_invoice(uuid,text,date,date,numeric,text,bytea,uuid,uuid),
 finance.record_supplier_settlement(uuid,text,text,text,numeric,text,timestamptz,bytea,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.record_supplier_invoice(uuid,text,date,date,numeric,text,bytea,uuid,uuid) TO upc_supplier_document_verifier;
GRANT EXECUTE ON FUNCTION finance.record_supplier_settlement(uuid,text,text,text,numeric,text,timestamptz,bytea,uuid) TO upc_supplier_payment_verifier;
CREATE VIEW finance.supplier_payables WITH(security_invoker=true) AS
 SELECT i.tenant_id,i.invoice_id,i.counterparty_id,i.currency,i.due_date,i.amount AS invoice_amount,
 COALESCE(s.paid,0) AS settled_amount,i.amount-COALESCE(s.paid,0) AS outstanding,
 CASE WHEN i.amount=COALESCE(s.paid,0) THEN 'settled' WHEN i.due_date<(statement_timestamp() AT TIME ZONE 'UTC')::date THEN 'overdue'
 WHEN COALESCE(s.paid,0)>0 THEN 'partial' ELSE 'unpaid' END AS state
 FROM finance.supplier_invoices i LEFT JOIN LATERAL (SELECT sum(amount) AS paid FROM finance.supplier_settlements s
 WHERE s.tenant_id=i.tenant_id AND s.invoice_id=i.invoice_id) s ON true;
GRANT SELECT ON finance.supplier_payables TO upc_runtime;
COMMIT;

-- 0007: full physical return and verified full refund; isolated prototype.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
ALTER TABLE sales.orders DROP CONSTRAINT orders_state_check;
ALTER TABLE sales.orders ADD CONSTRAINT orders_state_check CHECK(state IN
 ('pending','paid','fulfilled','cancelled','payment_review','returned','refunded'));
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('sales.return.receive','Receive all returned physical order items'),
 ('sales.refund.record','Record independently verified full refund');
CREATE ROLE upc_refund_recorder NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA sales TO upc_refund_recorder;

CREATE TABLE sales.returns (
 tenant_id uuid NOT NULL,
 return_id uuid NOT NULL DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL,
 request_key text NOT NULL CHECK(btrim(request_key)=request_key AND length(request_key) BETWEEN 1 AND 200),
 reason text NOT NULL CHECK(btrim(reason)<>''),
 received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 received_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,return_id),
 UNIQUE(tenant_id,order_id), UNIQUE(tenant_id,request_key),
 FOREIGN KEY(tenant_id,order_id) REFERENCES sales.orders(tenant_id,order_id)
);
ALTER TABLE sales.payments ADD UNIQUE(tenant_id,payment_id,provider,provider_account);
CREATE TABLE sales.refunds (
 tenant_id uuid NOT NULL,
 refund_id uuid NOT NULL DEFAULT gen_random_uuid(),
 payment_id uuid NOT NULL,
 provider text NOT NULL,
 provider_account text NOT NULL,
 provider_reference text NOT NULL CHECK(btrim(provider_reference)=provider_reference AND length(provider_reference) BETWEEN 1 AND 200),
 amount numeric(40,4) NOT NULL CHECK(amount>0 AND amount<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 refunded_at timestamptz NOT NULL CHECK(isfinite(refunded_at)),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,refund_id),
 UNIQUE(tenant_id,payment_id),
 UNIQUE(tenant_id,provider,provider_account,provider_reference),
 FOREIGN KEY(tenant_id,payment_id,provider,provider_account)
  REFERENCES sales.payments(tenant_id,payment_id,provider,provider_account)
);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['sales.returns'::regclass,'sales.refunds'::regclass] LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY sales_read ON %s FOR SELECT TO upc_runtime USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''sales.read'') AND platform.module_enabled(''sales''))',rel);
  EXECUTE format('CREATE POLICY sales_executor_scope ON %s FOR ALL TO upc_sales_executor USING (tenant_id=iam.current_tenant_id()) WITH CHECK (tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT ON sales.returns,sales.refunds TO upc_runtime;
GRANT SELECT,INSERT ON sales.returns,sales.refunds TO upc_sales_executor;

-- Existing ledger is authoritative; reserve a namespace for order returns.
ALTER FUNCTION inventory.adjust_stock(uuid,uuid,bigint,text,text) RENAME TO adjust_stock_internal;
REVOKE EXECUTE ON FUNCTION inventory.adjust_stock_internal(uuid,uuid,bigint,text,text) FROM upc_runtime;
GRANT EXECUTE ON FUNCTION inventory.adjust_stock_internal(uuid,uuid,bigint,text,text) TO upc_sales_executor;
CREATE FUNCTION inventory.adjust_stock(p_warehouse uuid,p_variant uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM inventory.require_access('inventory.adjust');
 IF p_key LIKE 'sales-return:%' THEN RAISE EXCEPTION 'Reserved return namespace' USING ERRCODE='42501'; END IF;
 RETURN inventory.adjust_stock_internal(p_warehouse,p_variant,p_delta,p_key,p_reason);
END $$;
ALTER FUNCTION inventory.adjust_stock(uuid,uuid,bigint,text,text) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.adjust_stock(uuid,uuid,bigint,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.adjust_stock(uuid,uuid,bigint,text,text) TO upc_runtime;

-- A late verified full capture for a cancelled/expired order is recorded, not lost.
-- payment_review is non-fulfillable; refund and reconciliation are explicit.
CREATE OR REPLACE FUNCTION sales.record_capture(p_order uuid,p_provider text,p_account text,p_reference text,
 p_amount numeric,p_currency text,p_captured_at timestamptz) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.payment.record'); o sales.orders%ROWTYPE; prior sales.payments%ROWTYPE; total numeric; pid uuid;
BEGIN
 IF p_order IS NULL OR p_provider IS NULL OR btrim(p_provider)<>p_provider OR length(p_provider) NOT BETWEEN 1 AND 100
 OR p_account IS NULL OR btrim(p_account)<>p_account OR length(p_account) NOT BETWEEN 1 AND 200
 OR p_reference IS NULL OR btrim(p_reference)<>p_reference OR length(p_reference) NOT BETWEEN 1 AND 200
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_amount<>round(p_amount,4)
 OR p_currency IS NULL OR p_captured_at IS NULL OR NOT isfinite(p_captured_at)
 OR p_captured_at>clock_timestamp() THEN RAISE EXCEPTION 'Invalid verified capture' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-capture',t,p_provider,p_account,p_reference)::text,0));
 PERFORM sales.lock_order(t,p_order);
 SELECT * INTO prior FROM sales.payments WHERE tenant_id=t AND provider=p_provider AND provider_account=p_account AND provider_reference=p_reference;
 IF FOUND THEN
  IF prior.order_id<>p_order OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.captured_at<>p_captured_at THEN
   RAISE EXCEPTION 'Payment idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.payment_id;
 END IF;
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF o.state NOT IN ('pending','cancelled') THEN RAISE EXCEPTION 'Order already settled; reconcile extra capture externally' USING ERRCODE='23514'; END IF;
 SELECT sum(quantity*unit_price) INTO total FROM sales.order_items WHERE tenant_id=t AND order_id=p_order;
 IF total IS DISTINCT FROM p_amount OR o.currency<>p_currency OR p_captured_at<o.created_at THEN
  RAISE EXCEPTION 'Capture amount, currency or timestamp mismatch' USING ERRCODE='23514';
 END IF;
 INSERT INTO sales.payments(tenant_id,order_id,provider,provider_account,provider_reference,amount,currency,captured_at,recorded_by)
 VALUES(t,p_order,p_provider,p_account,p_reference,p_amount,p_currency,p_captured_at,iam.current_user_id())
 RETURNING payment_id INTO pid;
 UPDATE sales.orders SET state=CASE WHEN o.state='cancelled' OR o.reservation_deadline<=clock_timestamp() THEN 'payment_review' ELSE 'paid' END WHERE tenant_id=t AND order_id=p_order;
 RETURN pid;
END $$;

CREATE FUNCTION sales.receive_full_return(p_order uuid,p_key text,p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.return.receive'); o sales.orders%ROWTYPE; prior sales.returns%ROWTYPE; rid uuid; i record;
BEGIN
 IF p_order IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_reason IS NULL OR btrim(p_reason)='' THEN RAISE EXCEPTION 'Invalid return' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-return-key',t,p_key)::text,0));
 PERFORM sales.lock_order(t,p_order);
 SELECT * INTO prior FROM sales.returns WHERE tenant_id=t AND request_key=p_key;
 IF FOUND THEN
  IF prior.order_id<>p_order OR prior.reason<>p_reason THEN RAISE EXCEPTION 'Return idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.return_id;
 END IF;
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF o.state<>'fulfilled' THEN RAISE EXCEPTION 'Only fulfilled orders can receive a full return' USING ERRCODE='23514'; END IF;
 INSERT INTO sales.returns(tenant_id,order_id,request_key,reason,received_by)
 VALUES(t,p_order,p_key,p_reason,iam.current_user_id()) RETURNING return_id INTO rid;
 -- Trusted operator confirms all units received, inspected and sellable.
 FOR i IN SELECT item_id,warehouse_id,variant_id,quantity FROM sales.order_items
  WHERE tenant_id=t AND order_id=p_order ORDER BY warehouse_id,variant_id LOOP
  PERFORM inventory.adjust_stock_internal(i.warehouse_id,i.variant_id,i.quantity,
    'sales-return:'||rid::text||':'||i.item_id::text,'full order return');
 END LOOP;
 UPDATE sales.orders SET state='returned' WHERE tenant_id=t AND order_id=p_order;
 RETURN rid;
END $$;

CREATE FUNCTION sales.record_full_refund(p_payment uuid,p_reference text,p_amount numeric,p_currency text,p_refunded_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.refund.record'); pay sales.payments%ROWTYPE; o sales.orders%ROWTYPE;
 prior sales.refunds%ROWTYPE; rid uuid; i record;
BEGIN
 IF p_payment IS NULL OR p_reference IS NULL OR btrim(p_reference)<>p_reference OR length(p_reference) NOT BETWEEN 1 AND 200
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_currency IS NULL
 OR p_refunded_at IS NULL OR NOT isfinite(p_refunded_at) OR p_refunded_at>clock_timestamp() THEN
  RAISE EXCEPTION 'Invalid verified refund' USING ERRCODE='22023';
 END IF;
 SELECT * INTO pay FROM sales.payments WHERE tenant_id=t AND payment_id=p_payment;
 IF NOT FOUND THEN RAISE EXCEPTION 'Payment unavailable' USING ERRCODE='23503'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-refund-ref',t,pay.provider,pay.provider_account,p_reference)::text,0));
 PERFORM sales.lock_order(t,pay.order_id);
 SELECT * INTO prior FROM sales.refunds WHERE tenant_id=t AND provider=pay.provider AND provider_account=pay.provider_account AND provider_reference=p_reference;
 IF FOUND THEN
  IF prior.payment_id<>p_payment OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.refunded_at<>p_refunded_at THEN
   RAISE EXCEPTION 'Refund idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.refund_id;
 END IF;
 SELECT * INTO STRICT o FROM sales.orders WHERE tenant_id=t AND order_id=pay.order_id;
 IF o.state NOT IN ('paid','payment_review','returned') THEN
  RAISE EXCEPTION 'Order must be unfulfilled or fully returned' USING ERRCODE='23514';
 END IF;
 IF p_amount<>pay.amount OR p_currency<>pay.currency OR p_refunded_at<pay.captured_at THEN
  RAISE EXCEPTION 'Full refund must match original capture' USING ERRCODE='23514';
 END IF;
 IF o.state IN ('paid','payment_review') THEN
  FOR i IN SELECT reservation_id FROM sales.order_items WHERE tenant_id=t AND order_id=pay.order_id ORDER BY warehouse_id,variant_id LOOP
   PERFORM inventory.release_reservation_internal(i.reservation_id);
  END LOOP;
 END IF;
 INSERT INTO sales.refunds(tenant_id,payment_id,provider,provider_account,provider_reference,amount,currency,refunded_at,recorded_by)
 VALUES(t,p_payment,pay.provider,pay.provider_account,p_reference,p_amount,p_currency,p_refunded_at,iam.current_user_id()) RETURNING refund_id INTO rid;
 UPDATE sales.orders SET state='refunded' WHERE tenant_id=t AND order_id=pay.order_id;
 RETURN rid;
END $$;
ALTER FUNCTION sales.receive_full_return(uuid,text,text) OWNER TO upc_sales_executor;
ALTER FUNCTION sales.record_full_refund(uuid,text,numeric,text,timestamptz) OWNER TO upc_sales_executor;
REVOKE ALL ON FUNCTION sales.receive_full_return(uuid,text,text),sales.record_full_refund(uuid,text,numeric,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION sales.receive_full_return(uuid,text,text) TO upc_runtime;
GRANT EXECUTE ON FUNCTION sales.record_full_refund(uuid,text,numeric,text,timestamptz) TO upc_refund_recorder;
COMMIT;

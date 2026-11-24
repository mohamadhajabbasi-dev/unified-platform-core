-- 0006: canonical checkout, verified payment recording and stock fulfillment.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
CREATE SCHEMA sales;
REVOKE ALL ON SCHEMA sales FROM PUBLIC;
CREATE ROLE upc_sales_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_payment_recorder NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('sales.read','Read orders and payments'),('sales.checkout','Create checkout'),
 ('sales.cancel','Cancel unpaid order'),('sales.payment.record','Record independently verified capture'),
 ('sales.fulfill','Fulfill paid order');
INSERT INTO platform.modules(module_key,version_label) VALUES ('sales','0.1');

CREATE TABLE sales.orders (
 tenant_id uuid NOT NULL,
 order_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 warehouse_id uuid NOT NULL,
 price_list_id uuid NOT NULL,
 checkout_key text NOT NULL CHECK (btrim(checkout_key)=checkout_key AND length(checkout_key) BETWEEN 1 AND 200),
 channel text NOT NULL CHECK (btrim(channel)=channel AND length(channel) BETWEEN 1 AND 100),
 currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
 created_at timestamptz NOT NULL,
 reservation_deadline timestamptz NOT NULL CHECK (isfinite(reservation_deadline)),
 created_by uuid NOT NULL REFERENCES core.users(user_id),
 state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','paid','fulfilled','cancelled')),
 PRIMARY KEY(tenant_id,order_id),
 UNIQUE(tenant_id,checkout_key),
 UNIQUE(tenant_id,order_id,warehouse_id,price_list_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 FOREIGN KEY(tenant_id,price_list_id) REFERENCES catalog.price_lists(tenant_id,price_list_id),
 CHECK (reservation_deadline>created_at)
);
CREATE INDEX orders_customer_idx ON sales.orders(tenant_id,customer_id,created_at);
-- Composite keys enforce that snapshots point to the exact variant/list and reservation.
ALTER TABLE catalog.price_entries ADD UNIQUE(tenant_id,price_id,variant_id,price_list_id);
ALTER TABLE inventory.reservations ADD UNIQUE(tenant_id,reservation_id,warehouse_id,variant_id,quantity);
CREATE TABLE sales.order_items (
 tenant_id uuid NOT NULL,
 order_id uuid NOT NULL,
 item_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL,
 price_list_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 price_id uuid NOT NULL,
 reservation_id uuid NOT NULL,
 quantity bigint NOT NULL CHECK (quantity>0),
 unit_price numeric(20,4) NOT NULL CHECK (unit_price>=0 AND unit_price<>'NaN'::numeric),
 sku_snapshot text NOT NULL CHECK (btrim(sku_snapshot)<>''),
 name_snapshot text NOT NULL CHECK (btrim(name_snapshot)<>''),
 PRIMARY KEY(tenant_id,item_id),
 UNIQUE(tenant_id,order_id,variant_id),
 UNIQUE(tenant_id,reservation_id),
 FOREIGN KEY(tenant_id,order_id,warehouse_id,price_list_id)
  REFERENCES sales.orders(tenant_id,order_id,warehouse_id,price_list_id),
 FOREIGN KEY(tenant_id,price_id,variant_id,price_list_id)
  REFERENCES catalog.price_entries(tenant_id,price_id,variant_id,price_list_id),
 FOREIGN KEY(tenant_id,reservation_id,warehouse_id,variant_id,quantity)
  REFERENCES inventory.reservations(tenant_id,reservation_id,warehouse_id,variant_id,quantity)
);
CREATE INDEX order_items_order_idx ON sales.order_items(tenant_id,order_id);
-- Initial scope: one exact, independently verified full capture per order.
CREATE TABLE sales.payments (
 tenant_id uuid NOT NULL,
 payment_id uuid NOT NULL DEFAULT gen_random_uuid(),
 order_id uuid NOT NULL,
 provider text NOT NULL CHECK (btrim(provider)=provider AND length(provider) BETWEEN 1 AND 100),
 provider_account text NOT NULL CHECK (btrim(provider_account)=provider_account AND length(provider_account) BETWEEN 1 AND 200),
 provider_reference text NOT NULL CHECK (btrim(provider_reference)=provider_reference AND length(provider_reference) BETWEEN 1 AND 200),
 amount numeric(40,4) NOT NULL CHECK (amount>0 AND amount<>'NaN'::numeric),
 currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
 captured_at timestamptz NOT NULL CHECK (isfinite(captured_at)),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,payment_id),
 UNIQUE(tenant_id,order_id),
 UNIQUE(tenant_id,provider,provider_account,provider_reference),
 FOREIGN KEY(tenant_id,order_id) REFERENCES sales.orders(tenant_id,order_id)
);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['sales.orders'::regclass,'sales.order_items'::regclass,'sales.payments'::regclass]
 LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY sales_read ON %s FOR SELECT TO upc_runtime USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''sales.read'') AND platform.module_enabled(''sales''))',rel);
  EXECUTE format('CREATE POLICY sales_executor_scope ON %s FOR ALL TO upc_sales_executor USING (tenant_id=iam.current_tenant_id()) WITH CHECK (tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA sales TO upc_runtime,upc_payment_recorder,upc_sales_executor;
GRANT SELECT ON sales.orders,sales.order_items,sales.payments TO upc_runtime;
GRANT SELECT,INSERT ON sales.orders,sales.order_items,sales.payments TO upc_sales_executor;
GRANT UPDATE(state) ON sales.orders TO upc_sales_executor;
GRANT USAGE ON SCHEMA iam,platform,crm,catalog,inventory TO upc_sales_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_sales_executor;
GRANT SELECT ON crm.customers TO upc_sales_executor;
CREATE POLICY sales_customer_gate ON crm.customers AS RESTRICTIVE FOR SELECT TO upc_sales_executor
 USING(iam.has_permission('crm.read') AND platform.module_enabled('crm'));
GRANT SELECT ON catalog.products,catalog.variants,catalog.price_lists,catalog.price_entries TO upc_sales_executor;
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['catalog.products'::regclass,'catalog.variants'::regclass,'catalog.price_lists'::regclass,'catalog.price_entries'::regclass]
 LOOP
  EXECUTE format('CREATE POLICY sales_catalog_dependency ON %s FOR SELECT TO upc_sales_executor USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND platform.module_enabled(''catalog''))',rel);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION catalog.price_at(uuid,uuid,timestamptz) TO upc_sales_executor;

-- Reserve the sales: namespace. Existing inventory APIs remain available for
-- standalone reservations, but cannot create or close order-owned holds.
ALTER FUNCTION inventory.reserve_stock(uuid,uuid,bigint,text,timestamptz) RENAME TO reserve_stock_internal;
ALTER FUNCTION inventory.release_reservation(uuid) RENAME TO release_reservation_internal;
ALTER FUNCTION inventory.consume_reservation(uuid) RENAME TO consume_reservation_internal;
REVOKE EXECUTE ON FUNCTION inventory.reserve_stock_internal(uuid,uuid,bigint,text,timestamptz),
 inventory.release_reservation_internal(uuid),inventory.consume_reservation_internal(uuid) FROM upc_runtime;
GRANT EXECUTE ON FUNCTION inventory.reserve_stock_internal(uuid,uuid,bigint,text,timestamptz),
 inventory.release_reservation_internal(uuid),inventory.consume_reservation_internal(uuid) TO upc_sales_executor;

CREATE FUNCTION inventory.reserve_stock(p_warehouse uuid,p_variant uuid,p_quantity bigint,p_key text,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM inventory.require_access('inventory.reserve');
 IF p_key LIKE 'sales:%' THEN RAISE EXCEPTION 'Reserved checkout namespace' USING ERRCODE='42501'; END IF;
 RETURN inventory.reserve_stock_internal(p_warehouse,p_variant,p_quantity,p_key,p_expires_at);
END $$;
CREATE FUNCTION inventory.release_reservation(p_reservation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.reserve');
BEGIN
 IF EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation AND request_key LIKE 'sales:%') THEN
  RAISE EXCEPTION 'Use sales cancellation' USING ERRCODE='42501';
 END IF;
 RETURN inventory.release_reservation_internal(p_reservation);
END $$;
CREATE FUNCTION inventory.consume_reservation(p_reservation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.fulfill');
BEGIN
 IF EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation AND request_key LIKE 'sales:%') THEN
  RAISE EXCEPTION 'Use sales fulfillment' USING ERRCODE='42501';
 END IF;
 RETURN inventory.consume_reservation_internal(p_reservation);
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['inventory.reserve_stock(uuid,uuid,bigint,text,timestamptz)'::regprocedure,
 'inventory.release_reservation(uuid)'::regprocedure,'inventory.consume_reservation(uuid)'::regprocedure]
 LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_inventory_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;

CREATE FUNCTION sales.require_access(p_permission text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR NOT platform.module_enabled('sales') THEN
  RAISE EXCEPTION 'Sales access denied' USING ERRCODE='42501';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Sales mutations require READ COMMITTED' USING ERRCODE='25000';
 END IF;
 RETURN t;
END $$;
CREATE FUNCTION sales.lock_order(p_tenant uuid,p_order uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-order',p_tenant,p_order)::text,0))
$$;
ALTER FUNCTION sales.require_access(text) OWNER TO upc_sales_executor;
ALTER FUNCTION sales.lock_order(uuid,uuid) OWNER TO upc_sales_executor;
REVOKE ALL ON FUNCTION sales.require_access(text),sales.lock_order(uuid,uuid) FROM PUBLIC;

-- One warehouse/list per physical checkout; client supplies expected price, never actual amount.
CREATE FUNCTION sales.create_checkout(p_key text,p_customer uuid,p_warehouse uuid,p_list uuid,
 p_channel text,p_deadline timestamptz,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.checkout'); existing sales.orders%ROWTYPE;
 oid uuid:=gen_random_uuid(); normalized jsonb; prior jsonb; line record; rid uuid;
 cur text; ts timestamptz:=statement_timestamp(); total numeric:=0;
BEGIN
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_channel IS NULL OR btrim(p_channel)<>p_channel OR length(p_channel) NOT BETWEEN 1 AND 100
 OR p_customer IS NULL OR p_warehouse IS NULL OR p_list IS NULL
 OR p_deadline IS NULL OR NOT isfinite(p_deadline)
 OR p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN
  RAISE EXCEPTION 'Invalid checkout' USING ERRCODE='22023';
 END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid line count' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) AS x(variant_id uuid,quantity bigint,expected_unit_price numeric)
  WHERE x.variant_id IS NULL OR x.quantity IS NULL OR x.quantity<=0 OR x.expected_unit_price IS NULL
  OR x.expected_unit_price<0 OR x.expected_unit_price='NaN'::numeric OR x.expected_unit_price<>round(x.expected_unit_price,4))
 OR (SELECT count(DISTINCT x.variant_id) FROM jsonb_to_recordset(p_lines) AS x(variant_id uuid))<>jsonb_array_length(p_lines)
 THEN RAISE EXCEPTION 'Invalid or duplicate checkout line' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_array(x.variant_id,x.quantity,x.expected_unit_price) ORDER BY x.variant_id)
 INTO normalized FROM jsonb_to_recordset(p_lines) AS x(variant_id uuid,quantity bigint,expected_unit_price numeric);
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-checkout',t,p_key)::text,0));
 SELECT * INTO existing FROM sales.orders WHERE tenant_id=t AND checkout_key=p_key;
 IF FOUND THEN
  SELECT jsonb_agg(jsonb_build_array(i.variant_id,i.quantity,i.unit_price) ORDER BY i.variant_id) INTO prior
   FROM sales.order_items i WHERE i.tenant_id=t AND i.order_id=existing.order_id;
  IF existing.customer_id<>p_customer OR existing.warehouse_id<>p_warehouse OR existing.price_list_id<>p_list
   OR existing.channel<>p_channel OR existing.reservation_deadline<>p_deadline OR prior IS DISTINCT FROM normalized THEN
   RAISE EXCEPTION 'Checkout idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN existing.order_id;
 END IF;
 IF p_deadline<=clock_timestamp() THEN RAISE EXCEPTION 'Checkout deadline elapsed' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=t AND customer_id=p_customer) THEN
  RAISE EXCEPTION 'Customer unavailable' USING ERRCODE='23503';
 END IF;
 SELECT currency INTO cur FROM catalog.price_lists WHERE tenant_id=t AND price_list_id=p_list AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Price list unavailable' USING ERRCODE='23503'; END IF;
 INSERT INTO sales.orders(tenant_id,order_id,customer_id,warehouse_id,price_list_id,checkout_key,channel,currency,created_at,reservation_deadline,created_by)
 VALUES(t,oid,p_customer,p_warehouse,p_list,p_key,p_channel,cur,ts,p_deadline,iam.current_user_id());
 -- One consistent query snapshot for all prices; lock inventory pairs in variant order.
 FOR line IN SELECT x.variant_id,x.quantity,x.expected_unit_price,v.sku,v.name,p.kind,q.price_id,q.amount,q.currency
  FROM jsonb_to_recordset(p_lines) AS x(variant_id uuid,quantity bigint,expected_unit_price numeric)
  LEFT JOIN catalog.variants v ON v.tenant_id=t AND v.variant_id=x.variant_id
  LEFT JOIN catalog.products p ON p.tenant_id=v.tenant_id AND p.product_id=v.product_id
  LEFT JOIN LATERAL catalog.price_at(x.variant_id,p_list,ts) q ON true
  ORDER BY x.variant_id
 LOOP
  IF line.price_id IS NULL OR line.kind IS DISTINCT FROM 'physical' OR line.currency IS DISTINCT FROM cur THEN
   RAISE EXCEPTION 'Physical variant or effective price unavailable' USING ERRCODE='23503';
  END IF;
  IF line.amount IS DISTINCT FROM line.expected_unit_price THEN RAISE EXCEPTION 'Price changed; refresh checkout' USING ERRCODE='23514'; END IF;
  rid:=inventory.reserve_stock_internal(p_warehouse,line.variant_id,line.quantity,'sales:'||oid::text||':'||line.variant_id::text,p_deadline);
  INSERT INTO sales.order_items(tenant_id,order_id,warehouse_id,price_list_id,variant_id,price_id,reservation_id,quantity,unit_price,sku_snapshot,name_snapshot)
  VALUES(t,oid,p_warehouse,p_list,line.variant_id,line.price_id,rid,line.quantity,line.amount,line.sku,line.name);
  total:=total+line.amount*line.quantity;
 END LOOP;
 IF total<=0 THEN RAISE EXCEPTION 'Zero-total checkout not supported in prototype' USING ERRCODE='23514'; END IF;
 RETURN oid;
END $$;

-- Trusted verifier must independently authenticate the provider capture.
-- This function records money already received; it never initiates a charge.
CREATE FUNCTION sales.record_capture(p_order uuid,p_provider text,p_account text,p_reference text,
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
 IF o.state<>'pending' THEN RAISE EXCEPTION 'Order not pending; reconcile capture externally' USING ERRCODE='23514'; END IF;
 SELECT sum(quantity*unit_price) INTO total FROM sales.order_items WHERE tenant_id=t AND order_id=p_order;
 IF total IS DISTINCT FROM p_amount OR o.currency<>p_currency OR p_captured_at<o.created_at THEN
  RAISE EXCEPTION 'Capture amount, currency or timestamp mismatch' USING ERRCODE='23514';
 END IF;
 INSERT INTO sales.payments(tenant_id,order_id,provider,provider_account,provider_reference,amount,currency,captured_at,recorded_by)
 VALUES(t,p_order,p_provider,p_account,p_reference,p_amount,p_currency,p_captured_at,iam.current_user_id())
 RETURNING payment_id INTO pid;
 UPDATE sales.orders SET state='paid' WHERE tenant_id=t AND order_id=p_order;
 RETURN pid;
END $$;
CREATE FUNCTION sales.cancel_order(p_order uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.cancel'); o sales.orders%ROWTYPE; i record;
BEGIN
 PERFORM sales.lock_order(t,p_order);
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF o.state='cancelled' THEN RETURN p_order; END IF;
 IF o.state<>'pending' THEN RAISE EXCEPTION 'Only unpaid orders may be cancelled' USING ERRCODE='23514'; END IF;
 FOR i IN SELECT reservation_id FROM sales.order_items WHERE tenant_id=t AND order_id=p_order ORDER BY warehouse_id,variant_id LOOP
  PERFORM inventory.release_reservation_internal(i.reservation_id);
 END LOOP;
 UPDATE sales.orders SET state='cancelled' WHERE tenant_id=t AND order_id=p_order;
 RETURN p_order;
END $$;
CREATE FUNCTION sales.fulfill_order(p_order uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.fulfill'); o sales.orders%ROWTYPE; i record;
BEGIN
 PERFORM sales.lock_order(t,p_order);
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF o.state='fulfilled' THEN RETURN p_order; END IF;
 IF o.state<>'paid' OR NOT EXISTS(SELECT 1 FROM sales.payments WHERE tenant_id=t AND order_id=p_order) THEN
  RAISE EXCEPTION 'Verified payment required' USING ERRCODE='23514';
 END IF;
 FOR i IN SELECT reservation_id FROM sales.order_items WHERE tenant_id=t AND order_id=p_order ORDER BY warehouse_id,variant_id LOOP
  PERFORM inventory.consume_reservation_internal(i.reservation_id);
 END LOOP;
 UPDATE sales.orders SET state='fulfilled' WHERE tenant_id=t AND order_id=p_order;
 RETURN p_order;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['sales.create_checkout(text,uuid,uuid,uuid,text,timestamptz,jsonb)'::regprocedure,
 'sales.cancel_order(uuid)'::regprocedure,'sales.fulfill_order(uuid)'::regprocedure,
 'sales.record_capture(uuid,text,text,text,numeric,text,timestamptz)'::regprocedure]
 LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_sales_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION sales.create_checkout(text,uuid,uuid,uuid,text,timestamptz,jsonb),
 sales.cancel_order(uuid),sales.fulfill_order(uuid) TO upc_runtime;
GRANT EXECUTE ON FUNCTION sales.record_capture(uuid,text,text,text,numeric,text,timestamptz) TO upc_payment_recorder;
CREATE VIEW sales.order_totals WITH (security_invoker=true) AS
 SELECT o.tenant_id,o.order_id,o.currency,COALESCE(sum(i.quantity*i.unit_price),0) AS total
 FROM sales.orders o LEFT JOIN sales.order_items i USING(tenant_id,order_id)
 GROUP BY o.tenant_id,o.order_id,o.currency;
GRANT SELECT ON sales.order_totals TO upc_runtime;
COMMIT;

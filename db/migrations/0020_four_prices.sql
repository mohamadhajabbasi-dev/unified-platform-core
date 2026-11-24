-- 0017: canonical four-price selection, private price controls and checkout.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_pricing_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_price_customer_verifier NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions VALUES
 ('catalog.price.eligibility.write','Approve customer-specific colleague/wholesale eligibility'),
 ('catalog.price.customer','Resolve private price for independently authenticated customer');
-- Append decisions; no duplicate customer master. Latest decision wins, no fallback after expiry.
CREATE TABLE catalog.customer_price_decisions(
 tenant_id uuid NOT NULL,
 decision_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 customer_id uuid NOT NULL,
 audience text NOT NULL CHECK(audience IN ('colleague','wholesale')),
 approved boolean NOT NULL,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz,
 decided_by uuid NOT NULL REFERENCES core.users(user_id),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 500),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 CHECK(expires_at IS NULL OR (approved AND isfinite(expires_at) AND expires_at>decided_at))
);
CREATE INDEX price_decisions_latest_idx ON catalog.customer_price_decisions(tenant_id,customer_id,audience,decision_id DESC);
ALTER TABLE catalog.customer_price_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE catalog.customer_price_decisions FORCE ROW LEVEL SECURITY;
CREATE POLICY price_decisions_scope ON catalog.customer_price_decisions FOR ALL TO upc_pricing_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY price_decisions_read ON catalog.customer_price_decisions FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.price.eligibility.write') AND platform.module_enabled('catalog'));
GRANT USAGE ON SCHEMA catalog,iam,platform,crm TO upc_pricing_executor;
GRANT USAGE ON SCHEMA catalog TO upc_price_customer_verifier;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text),
 platform.commerce_eligible(),platform.app_eligible() TO upc_pricing_executor;
GRANT SELECT ON catalog.customer_price_decisions TO upc_runtime,upc_pricing_executor;
GRANT INSERT ON catalog.customer_price_decisions TO upc_pricing_executor;
GRANT USAGE ON SEQUENCE catalog.customer_price_decisions_decision_id_seq TO upc_pricing_executor;
GRANT SELECT ON crm.customers TO upc_pricing_executor;
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['catalog.price_lists'::regclass,'catalog.price_entries'::regclass,'catalog.price_quantity_tiers'::regclass,'catalog.products'::regclass,'catalog.variants'::regclass] LOOP
 EXECUTE format('CREATE POLICY pricing_executor_read ON %s FOR SELECT TO upc_pricing_executor USING(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT ON catalog.price_lists,catalog.price_entries,catalog.price_quantity_tiers,catalog.products,catalog.variants TO upc_pricing_executor;
-- Only price managers may read raw private/custom prices. Buyer-facing resolution is separate.
CREATE POLICY price_list_visibility ON catalog.price_lists AS RESTRICTIVE FOR SELECT TO upc_runtime
 USING(list_key IN ('original','discounted','retail') OR iam.has_permission('catalog.price.write'));
CREATE POLICY price_entry_visibility ON catalog.price_entries AS RESTRICTIVE FOR SELECT TO upc_runtime
 USING(EXISTS(SELECT 1 FROM catalog.price_lists l WHERE l.tenant_id=price_entries.tenant_id AND l.price_list_id=price_entries.price_list_id));
CREATE POLICY price_tier_visibility ON catalog.price_quantity_tiers AS RESTRICTIVE FOR SELECT TO upc_runtime
 USING(EXISTS(SELECT 1 FROM catalog.price_entries e WHERE e.tenant_id=price_quantity_tiers.tenant_id AND e.price_id=price_quantity_tiers.price_id));
ALTER TABLE catalog.price_entries ADD COLUMN minimum_quantity bigint NOT NULL DEFAULT 1 CHECK(minimum_quantity>=1);
ALTER TABLE catalog.price_quantity_tiers ADD UNIQUE(tenant_id,price_id,tier_id);
CREATE FUNCTION catalog.lock_prices(p_tenant uuid) RETURNS void LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('catalog-pricing',p_tenant)::text,0))
$$;
ALTER FUNCTION catalog.lock_prices(uuid) OWNER TO upc_pricing_executor;
REVOKE ALL ON FUNCTION catalog.lock_prices(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.lock_prices(uuid) TO upc_sales_executor;
-- Guard all price writes with shared per-tenant lock; validate in a fresh READ COMMITTED query.
CREATE FUNCTION catalog.guard_four_prices() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE k text; cur text; base_cur text; entry catalog.price_entries%ROWTYPE;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 -- Bootstrap test fixtures use an unmapped superuser; ordinary writes must be scoped.
 PERFORM catalog.lock_prices(NEW.tenant_id);
 IF TG_TABLE_NAME='price_lists' THEN
  IF NEW.list_key IN ('original','discounted','colleague','wholesale') THEN
   IF EXISTS(SELECT 1 FROM catalog.price_lists l WHERE l.tenant_id=NEW.tenant_id AND l.list_key IN ('original','discounted','colleague','wholesale') AND l.currency<>NEW.currency)
   THEN RAISE EXCEPTION 'Standard price currency mismatch' USING ERRCODE='23514'; END IF;
  END IF;
  RETURN NEW;
 END IF;
 IF TG_TABLE_NAME='price_quantity_tiers' THEN
  SELECT * INTO entry FROM catalog.price_entries e WHERE e.tenant_id=NEW.tenant_id AND e.price_id=NEW.price_id;
  SELECT list_key INTO k FROM catalog.price_lists WHERE tenant_id=NEW.tenant_id AND price_list_id=entry.price_list_id;
  IF k IN ('original','discounted','colleague') OR (k='wholesale' AND (lower(NEW.quantity_range)<entry.minimum_quantity OR NEW.tier_amount>entry.amount))
  THEN RAISE EXCEPTION 'Invalid standard quantity tier' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END IF;
 SELECT list_key,currency INTO k,cur FROM catalog.price_lists WHERE tenant_id=NEW.tenant_id AND price_list_id=NEW.price_list_id;
 IF k='wholesale' AND NEW.minimum_quantity<2 THEN RAISE EXCEPTION 'Wholesale minimum must be at least two' USING ERRCODE='23514'; END IF;
 IF k IN ('original','discounted','colleague') AND NEW.minimum_quantity<>1 THEN RAISE EXCEPTION 'Invalid minimum for price kind' USING ERRCODE='23514'; END IF;
 IF k='discounted' THEN
  IF NOT EXISTS(SELECT 1 FROM catalog.price_entries e JOIN catalog.price_lists l USING(tenant_id,price_list_id)
   WHERE e.tenant_id=NEW.tenant_id AND e.variant_id=NEW.variant_id AND l.list_key='original' AND l.currency=cur
   AND e.valid_during @> NEW.valid_during AND e.amount>=NEW.amount)
  THEN RAISE EXCEPTION 'Discount requires covering original price, same currency and no higher amount' USING ERRCODE='23514'; END IF;
 END IF;
 IF k='original' AND TG_OP='UPDATE' THEN
  IF EXISTS(SELECT 1 FROM catalog.price_entries e JOIN catalog.price_lists l USING(tenant_id,price_list_id)
   WHERE e.tenant_id=NEW.tenant_id AND e.variant_id=NEW.variant_id AND l.list_key='discounted'
   AND OLD.valid_during @> e.valid_during AND NOT NEW.valid_during @> e.valid_during)
  THEN RAISE EXCEPTION 'Shorten dependent discount first' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;
-- A trusted bootstrap actor is only used in disposable CI. Trigger uses scoped private reader;
-- no application bypass or extra grant to runtime.
ALTER FUNCTION catalog.guard_four_prices() OWNER TO upc_pricing_executor;
REVOKE ALL ON FUNCTION catalog.guard_four_prices() FROM PUBLIC;
CREATE TRIGGER four_list_guard BEFORE INSERT OR UPDATE ON catalog.price_lists FOR EACH ROW EXECUTE FUNCTION catalog.guard_four_prices();
CREATE TRIGGER four_entry_guard BEFORE INSERT OR UPDATE ON catalog.price_entries FOR EACH ROW EXECUTE FUNCTION catalog.guard_four_prices();
CREATE TRIGGER four_tier_guard BEFORE INSERT ON catalog.price_quantity_tiers FOR EACH ROW EXECUTE FUNCTION catalog.guard_four_prices();
-- Initialize the four lists through the existing pricing-admin capability. No price amounts invented.
CREATE POLICY pricing_executor_list_insert ON catalog.price_lists FOR INSERT TO upc_pricing_executor WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT INSERT ON catalog.price_lists TO upc_pricing_executor;
CREATE FUNCTION catalog.initialize_standard_prices(p_currency text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('catalog.price.write') OR NOT platform.module_enabled('catalog')
 THEN RAISE EXCEPTION 'Pricing administrator required' USING ERRCODE='42501'; END IF;
 IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$' THEN RAISE EXCEPTION 'Invalid currency' USING ERRCODE='22023'; END IF;
 PERFORM catalog.lock_prices(t);
 IF EXISTS(SELECT 1 FROM catalog.price_lists WHERE tenant_id=t AND list_key IN ('original','discounted','colleague','wholesale') AND currency<>p_currency)
 THEN RAISE EXCEPTION 'Standard currency mismatch' USING ERRCODE='23514'; END IF;
 INSERT INTO catalog.price_lists(tenant_id,list_key,currency,name)
 SELECT t,k,p_currency,k FROM unnest(ARRAY['original','discounted','colleague','wholesale']) k
 ON CONFLICT(tenant_id,list_key) DO NOTHING;
END $$;
CREATE FUNCTION catalog.decide_customer_price(p_customer uuid,p_audience text,p_approved boolean,p_expiry timestamptz,p_reason text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); did bigint;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.price.eligibility.write') OR NOT platform.module_enabled('catalog')
 OR NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm')
 THEN RAISE EXCEPTION 'Price eligibility administrator required' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 PERFORM catalog.lock_prices(t);
 INSERT INTO catalog.customer_price_decisions(tenant_id,customer_id,audience,approved,expires_at,decided_by,reason)
 VALUES(t,p_customer,p_audience,p_approved,p_expiry,iam.current_user_id(),p_reason) RETURNING decision_id INTO did;
 RETURN did;
END $$;
CREATE FUNCTION catalog.price_channel_allowed(p_channel text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT CASE p_channel WHEN 'web' THEN platform.commerce_eligible() WHEN 'app' THEN platform.app_eligible()
 WHEN 'in_person' THEN true WHEN 'phone' THEN true WHEN 'erp' THEN true ELSE false END
$$;
ALTER FUNCTION catalog.price_channel_allowed(text) OWNER TO upc_pricing_executor;
REVOKE ALL ON FUNCTION catalog.price_channel_allowed(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.price_channel_allowed(text) TO upc_sales_executor;
-- Priority provisional: eligible wholesale at minimum, then colleague, then valid discount, then original.
-- Private quote requires independently authenticated customer context at trusted service, never client UUID alone.
CREATE FUNCTION catalog.resolve_price_internal(p_variant uuid,p_customer uuid,p_quantity bigint,p_channel text,p_at timestamptz,p_base uuid)
RETURNS TABLE(price_id uuid,amount numeric,currency text,selected_list_id uuid,price_kind text,tier_id uuid,original_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); base record; eligible boolean;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR p_quantity IS NULL OR p_quantity<1 THEN RETURN; END IF;
 SELECT e.price_id,e.amount,l.currency,l.price_list_id,l.list_key INTO base
 FROM catalog.price_entries e JOIN catalog.price_lists l USING(tenant_id,price_list_id)
 JOIN catalog.variants v USING(tenant_id,variant_id) JOIN catalog.products p ON p.tenant_id=v.tenant_id AND p.product_id=v.product_id
 WHERE e.tenant_id=t AND e.variant_id=p_variant AND e.valid_during @> p_at AND l.is_active AND v.is_active AND p.is_active
 AND (l.list_key='original' AND (p_base IS NULL OR l.price_list_id=p_base) OR
 l.list_key='retail' AND l.price_list_id=p_base AND NOT EXISTS(SELECT 1 FROM catalog.price_lists z WHERE z.tenant_id=t AND z.list_key='original'));
 IF NOT FOUND THEN RETURN; END IF;
 IF base.list_key='retail' THEN RETURN QUERY SELECT base.price_id,base.amount,base.currency,base.price_list_id,'retail'::text,NULL::uuid,base.amount; RETURN; END IF;
 IF NOT catalog.price_channel_allowed(p_channel) THEN RETURN; END IF;
 eligible:=p_customer IS NOT NULL AND pg_has_role(session_user,'upc_price_customer_verifier','MEMBER')
 AND iam.has_permission('catalog.price.customer') AND platform.module_enabled('crm')
 AND EXISTS(SELECT 1 FROM crm.customers c WHERE c.tenant_id=t AND c.customer_id=p_customer);
 RETURN QUERY
 SELECT e.price_id,COALESCE(q.tier_amount,e.amount),l.currency,l.price_list_id,l.list_key,q.tier_id,base.amount
 FROM catalog.price_entries e JOIN catalog.price_lists l USING(tenant_id,price_list_id)
 LEFT JOIN LATERAL(SELECT x.tier_id,x.tier_amount FROM catalog.price_quantity_tiers x WHERE x.tenant_id=t AND x.price_id=e.price_id AND x.quantity_range @> p_quantity AND l.list_key='wholesale') q ON true
 WHERE e.tenant_id=t AND e.variant_id=p_variant AND e.valid_during @> p_at AND l.is_active AND l.currency=base.currency
 AND (l.list_key='original' OR (l.list_key='discounted' AND e.amount<=base.amount)
 OR (eligible AND l.list_key IN ('wholesale','colleague') AND p_quantity>=e.minimum_quantity AND COALESCE(
 (SELECT d.approved AND (d.expires_at IS NULL OR d.expires_at>p_at) FROM catalog.customer_price_decisions d
 WHERE d.tenant_id=t AND d.customer_id=p_customer AND d.audience=l.list_key AND d.decided_at<=p_at
 ORDER BY d.decision_id DESC LIMIT 1),false)))
 ORDER BY CASE l.list_key WHEN 'wholesale' THEN 1 WHEN 'colleague' THEN 2 WHEN 'discounted' THEN 3 ELSE 4 END LIMIT 1;
END $$;
ALTER FUNCTION catalog.resolve_price_internal(uuid,uuid,bigint,text,timestamptz,uuid) OWNER TO upc_pricing_executor;
REVOKE ALL ON FUNCTION catalog.resolve_price_internal(uuid,uuid,bigint,text,timestamptz,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.resolve_price_internal(uuid,uuid,bigint,text,timestamptz,uuid) TO upc_sales_executor;
CREATE FUNCTION catalog.quote_price(p_variant uuid,p_customer uuid,p_quantity bigint,p_channel text)
RETURNS TABLE(price_id uuid,amount numeric,currency text,selected_list_id uuid,price_kind text,tier_id uuid,original_amount numeric)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 PERFORM catalog.lock_prices(iam.current_tenant_id());
 RETURN QUERY SELECT * FROM catalog.resolve_price_internal(p_variant,p_customer,p_quantity,p_channel,clock_timestamp(),NULL);
END $$;
DO $$ DECLARE f regprocedure; BEGIN
 FOREACH f IN ARRAY ARRAY['catalog.initialize_standard_prices(text)'::regprocedure,'catalog.decide_customer_price(uuid,text,boolean,timestamptz,text)'::regprocedure,'catalog.quote_price(uuid,uuid,bigint,text)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_pricing_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
-- Order header points to base list; line points to exact selected price/list and tier.
ALTER TABLE sales.orders ADD UNIQUE(tenant_id,order_id,warehouse_id);
DO $$ DECLARE n name; BEGIN
 SELECT conname INTO STRICT n FROM pg_constraint WHERE conrelid='sales.order_items'::regclass AND confrelid='sales.orders'::regclass AND contype='f';
 EXECUTE format('ALTER TABLE sales.order_items DROP CONSTRAINT %I',n);
END $$;
ALTER TABLE sales.order_items ADD FOREIGN KEY(tenant_id,order_id,warehouse_id) REFERENCES sales.orders(tenant_id,order_id,warehouse_id);
ALTER TABLE sales.order_items ADD COLUMN price_kind_snapshot text NOT NULL DEFAULT 'retail' CHECK(price_kind_snapshot IN ('retail','original','discounted','colleague','wholesale'));
ALTER TABLE sales.order_items ADD COLUMN price_tier_id uuid;
ALTER TABLE sales.order_items ADD COLUMN original_unit_price numeric(20,4) CHECK(original_unit_price>=0 AND original_unit_price<>'NaN'::numeric);
ALTER TABLE sales.order_items ADD FOREIGN KEY(tenant_id,price_id,price_tier_id) REFERENCES catalog.price_quantity_tiers(tenant_id,price_id,tier_id);
CREATE OR REPLACE FUNCTION sales.create_checkout(p_key text,p_customer uuid,p_warehouse uuid,p_list uuid,
 p_channel text,p_deadline timestamptz,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.checkout'); existing sales.orders%ROWTYPE;
 oid uuid:=gen_random_uuid(); normalized jsonb; prior jsonb; line record; rid uuid;
 cur text; base_key text; ts timestamptz; total numeric:=0;
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
 PERFORM catalog.lock_prices(t);
 ts:=clock_timestamp();
 SELECT currency,list_key INTO cur,base_key FROM catalog.price_lists WHERE tenant_id=t AND price_list_id=p_list AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Price list unavailable' USING ERRCODE='23503'; END IF;
 IF base_key NOT IN ('original','retail') OR (base_key='retail' AND EXISTS(SELECT 1 FROM catalog.price_lists WHERE tenant_id=t AND list_key='original')) THEN
  RAISE EXCEPTION 'Checkout requires canonical original list' USING ERRCODE='42501'; END IF;
 IF base_key='original' AND NOT catalog.price_channel_allowed(p_channel) THEN RAISE EXCEPTION 'Channel not eligible' USING ERRCODE='42501'; END IF;
 INSERT INTO sales.orders(tenant_id,order_id,customer_id,warehouse_id,price_list_id,checkout_key,channel,currency,created_at,reservation_deadline,created_by)
 VALUES(t,oid,p_customer,p_warehouse,p_list,p_key,p_channel,cur,ts,p_deadline,iam.current_user_id());
 -- One consistent query snapshot for all prices; lock inventory pairs in variant order.
 FOR line IN SELECT x.variant_id,x.quantity,x.expected_unit_price,v.sku,v.name,p.kind,q.price_id,q.amount,q.currency,q.selected_list_id,q.price_kind,q.tier_id,q.original_amount
  FROM jsonb_to_recordset(p_lines) AS x(variant_id uuid,quantity bigint,expected_unit_price numeric)
  LEFT JOIN catalog.variants v ON v.tenant_id=t AND v.variant_id=x.variant_id
  LEFT JOIN catalog.products p ON p.tenant_id=v.tenant_id AND p.product_id=v.product_id
  LEFT JOIN LATERAL catalog.resolve_price_internal(x.variant_id,p_customer,x.quantity,p_channel,ts,p_list) q ON true
  ORDER BY x.variant_id
 LOOP
  IF line.price_id IS NULL OR line.kind IS DISTINCT FROM 'physical' OR line.currency IS DISTINCT FROM cur THEN
   RAISE EXCEPTION 'Physical variant or effective price unavailable' USING ERRCODE='23503';
  END IF;
  IF line.amount IS DISTINCT FROM line.expected_unit_price THEN RAISE EXCEPTION 'Price changed; refresh checkout' USING ERRCODE='23514'; END IF;
  rid:=inventory.reserve_stock_internal(p_warehouse,line.variant_id,line.quantity,'sales:'||oid::text||':'||line.variant_id::text,p_deadline);
  INSERT INTO sales.order_items(tenant_id,order_id,warehouse_id,price_list_id,variant_id,price_id,reservation_id,quantity,unit_price,sku_snapshot,name_snapshot,price_kind_snapshot,price_tier_id,original_unit_price)
  VALUES(t,oid,p_warehouse,line.selected_list_id,line.variant_id,line.price_id,rid,line.quantity,line.amount,line.sku,line.name,line.price_kind,line.tier_id,line.original_amount);
  total:=total+line.amount*line.quantity;
 END LOOP;
 IF total<=0 THEN RAISE EXCEPTION 'Zero-total checkout not supported in prototype' USING ERRCODE='23514'; END IF;
 RETURN oid;
END $$;


COMMIT;

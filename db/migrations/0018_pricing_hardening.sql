-- 0018: remove retail checkout bypass; explicit channel trust and lock-first guard.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE ROLE upc_checkout_web NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_checkout_app NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_checkout_offline NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE FUNCTION catalog.checkout_channel_authorized(p_channel text) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT CASE p_channel WHEN 'web' THEN pg_has_role(session_user,'upc_checkout_web','MEMBER')
 WHEN 'app' THEN pg_has_role(session_user,'upc_checkout_app','MEMBER')
 WHEN 'in_person' THEN pg_has_role(session_user,'upc_checkout_offline','MEMBER')
 WHEN 'phone' THEN pg_has_role(session_user,'upc_checkout_offline','MEMBER')
 WHEN 'erp' THEN pg_has_role(session_user,'upc_checkout_offline','MEMBER') ELSE false END
$$;
ALTER FUNCTION catalog.checkout_channel_authorized(text) OWNER TO upc_pricing_executor;
REVOKE ALL ON FUNCTION catalog.checkout_channel_authorized(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.checkout_channel_authorized(text) TO upc_sales_executor;
DROP POLICY price_list_visibility ON catalog.price_lists;
CREATE POLICY price_list_visibility ON catalog.price_lists AS RESTRICTIVE FOR SELECT TO upc_runtime
 USING(list_key IN ('original','discounted') OR iam.has_permission('catalog.price.write'));
-- Dedicated trigger-only validation reader; cannot be assumed by application roles.
-- Scope checked against mapped tenant (or disposable bootstrap superuser).
CREATE ROLE upc_price_constraint_reader NOLOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA catalog,iam TO upc_price_constraint_reader;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),catalog.lock_prices(uuid) TO upc_price_constraint_reader;
GRANT SELECT ON catalog.price_lists,catalog.price_entries TO upc_price_constraint_reader;
CREATE POLICY price_constraint_read ON catalog.price_lists FOR SELECT TO upc_price_constraint_reader USING(true);
CREATE POLICY price_constraint_read ON catalog.price_entries FOR SELECT TO upc_price_constraint_reader USING(true);
CREATE OR REPLACE FUNCTION catalog.guard_four_prices() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE k text; cur text; base_cur text; entry catalog.price_entries%ROWTYPE;
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF NEW.tenant_id IS DISTINCT FROM iam.current_tenant_id() AND NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=session_user AND rolsuper) THEN
  RAISE EXCEPTION 'Price write scope mismatch' USING ERRCODE='42501'; END IF;
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

ALTER FUNCTION catalog.guard_four_prices() OWNER TO upc_price_constraint_reader;
REVOKE ALL ON FUNCTION catalog.guard_four_prices() FROM PUBLIC;
-- Mapped writes acquire tenant lock before touching rows, including multi-row UPDATE.
-- Unmapped bootstrap is limited to disposable test data, row trigger still validates.
CREATE FUNCTION catalog.lock_price_statement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF t IS NOT NULL THEN PERFORM catalog.lock_prices(t); END IF;
 RETURN NULL;
END $$;
ALTER FUNCTION catalog.lock_price_statement() OWNER TO upc_price_constraint_reader;
REVOKE ALL ON FUNCTION catalog.lock_price_statement() FROM PUBLIC;
CREATE TRIGGER price_lock_first BEFORE INSERT OR UPDATE ON catalog.price_lists FOR EACH STATEMENT EXECUTE FUNCTION catalog.lock_price_statement();
CREATE TRIGGER price_lock_first BEFORE INSERT OR UPDATE ON catalog.price_entries FOR EACH STATEMENT EXECUTE FUNCTION catalog.lock_price_statement();
CREATE TRIGGER price_lock_first BEFORE INSERT ON catalog.price_quantity_tiers FOR EACH STATEMENT EXECUTE FUNCTION catalog.lock_price_statement();
CREATE OR REPLACE FUNCTION catalog.resolve_price_internal(p_variant uuid,p_customer uuid,p_quantity bigint,p_channel text,p_at timestamptz,p_base uuid)
RETURNS TABLE(price_id uuid,amount numeric,currency text,selected_list_id uuid,price_kind text,tier_id uuid,original_amount numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); base record; eligible boolean;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('catalog.read') OR NOT platform.module_enabled('catalog') OR p_quantity IS NULL OR p_quantity<1 THEN RETURN; END IF;
 SELECT e.price_id,e.amount,l.currency,l.price_list_id,l.list_key INTO base
 FROM catalog.price_entries e JOIN catalog.price_lists l USING(tenant_id,price_list_id)
 JOIN catalog.variants v USING(tenant_id,variant_id) JOIN catalog.products p ON p.tenant_id=v.tenant_id AND p.product_id=v.product_id
 WHERE e.tenant_id=t AND e.variant_id=p_variant AND e.valid_during @> p_at AND l.is_active AND v.is_active AND p.is_active
 AND l.list_key='original' AND (p_base IS NULL OR l.price_list_id=p_base);
 IF NOT FOUND THEN RETURN; END IF;
 IF NOT catalog.price_channel_allowed(p_channel) THEN RETURN; END IF;
 eligible:=p_customer IS NOT NULL AND catalog.checkout_channel_authorized(p_channel) AND pg_has_role(session_user,'upc_price_customer_verifier','MEMBER')
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
 IF NOT catalog.checkout_channel_authorized(p_channel) THEN RAISE EXCEPTION 'Trusted checkout channel required' USING ERRCODE='42501'; END IF;
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
 IF base_key<>'original' THEN
  RAISE EXCEPTION 'Checkout requires canonical original list' USING ERRCODE='42501'; END IF;
 IF NOT catalog.price_channel_allowed(p_channel) THEN RAISE EXCEPTION 'Channel not eligible' USING ERRCODE='42501'; END IF;
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



-- Canonical order creation now requires original. Historical retail snapshots remain readable.
ALTER TABLE sales.order_items ALTER COLUMN price_kind_snapshot DROP DEFAULT;
COMMIT;

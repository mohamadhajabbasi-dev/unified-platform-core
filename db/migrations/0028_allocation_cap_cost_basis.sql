-- 0025: bound total tracked checkout allocations and expose actual purchase cost provenance.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE OR REPLACE FUNCTION sales.create_checkout(p_key text,p_customer uuid,p_warehouse uuid,p_list uuid,
 p_channel text,p_deadline timestamptz,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.checkout'); existing sales.orders%ROWTYPE;
 oid uuid:=gen_random_uuid(); normalized jsonb; prior jsonb; line record; rid uuid;
 cur text; base_key text; ts timestamptz; total numeric:=0; allocations_used bigint:=0;
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
  SELECT allocations_used+count(*) INTO allocations_used FROM inventory.reservation_allocations
   WHERE tenant_id=t AND reservation_id=rid;
  IF allocations_used>1000 THEN RAISE EXCEPTION 'Order exceeds 1000 traced allocations' USING ERRCODE='23514'; END IF;
  INSERT INTO sales.order_items(tenant_id,order_id,warehouse_id,price_list_id,variant_id,price_id,reservation_id,quantity,unit_price,sku_snapshot,name_snapshot,price_kind_snapshot,price_tier_id,original_unit_price)
  VALUES(t,oid,p_warehouse,line.selected_list_id,line.variant_id,line.price_id,rid,line.quantity,line.amount,line.sku,line.name,line.price_kind,line.tier_id,line.original_amount);
  total:=total+line.amount*line.quantity;
 END LOOP;
 IF total<=0 THEN RAISE EXCEPTION 'Zero-total checkout not supported in prototype' USING ERRCODE='23514'; END IF;
 RETURN oid;
END $$;




-- This is historical purchase receipt cost evidence, NOT remaining stock value or COGS.
-- Existing invoker RLS applies to every dependency; no privileged reader bypass.
CREATE VIEW finance.receipt_cost_basis WITH(security_invoker=true) AS
 SELECT r.tenant_id,r.receipt_id,r.purchase_id,i.item_id,i.movement_id,i.warehouse_id,i.variant_id,
 l.lot_id,l.serial_id,r.received_at,i.quantity,p.unit_cost,o.currency,
 i.quantity*p.unit_cost AS agreed_cost,
 f.invoice_id,CASE WHEN f.invoice_id IS NOT NULL THEN 'invoiced_exact_cost' ELSE 'agreed_uninvoiced' END AS cost_status
 FROM procurement.goods_receipts r
 JOIN procurement.receipt_items i USING(tenant_id,receipt_id,purchase_id,warehouse_id)
 JOIN procurement.purchase_items p ON p.tenant_id=i.tenant_id AND p.purchase_id=i.purchase_id AND p.item_id=i.item_id
 JOIN procurement.purchase_orders o ON o.tenant_id=r.tenant_id AND o.purchase_id=r.purchase_id
 JOIN inventory.stock_ledger l ON l.tenant_id=i.tenant_id AND l.movement_id=i.movement_id
 LEFT JOIN finance.supplier_invoices f ON f.tenant_id=r.tenant_id AND f.purchase_id=r.purchase_id
 WHERE iam.has_permission('finance.read') AND platform.module_enabled('finance')
 AND iam.has_permission('procurement.read') AND platform.module_enabled('procurement')
 AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory');
GRANT SELECT ON finance.receipt_cost_basis TO upc_runtime;
COMMIT;

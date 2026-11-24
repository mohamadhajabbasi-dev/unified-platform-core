-- 0019: tenant counterparties, purchase commitments and full goods receipt.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE SCHEMA procurement;
REVOKE ALL ON SCHEMA procurement FROM PUBLIC;
CREATE ROLE upc_procurement_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO platform.modules(module_key,version_label) VALUES('procurement','0.1');
INSERT INTO iam.permissions VALUES
 ('procurement.read','Read own purchase orders and supplier relationships'),
 ('procurement.supplier.write','Register supplier relationship'),
 ('procurement.order.write','Issue or cancel purchase order'),
 ('procurement.receive','Confirm full physical receipt'),
 ('inventory.receive','Post purchase receipt to stock ledger');
-- One reusable counterparty relation. A linked CRM customer has no second name master.
CREATE TABLE procurement.counterparties(
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 counterparty_id uuid NOT NULL DEFAULT gen_random_uuid(),
 party_key text NOT NULL CHECK(party_key ~ '^[a-z0-9][a-z0-9_-]{0,99}$'),
 customer_id uuid,
 standalone_name text CHECK(length(btrim(standalone_name)) BETWEEN 1 AND 300),
 created_by uuid NOT NULL REFERENCES core.users(user_id),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,counterparty_id),
 UNIQUE(tenant_id,party_key), UNIQUE(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 CHECK((customer_id IS NULL)<>(standalone_name IS NULL))
);
CREATE TABLE procurement.purchase_orders(
 tenant_id uuid NOT NULL,
 purchase_id uuid NOT NULL DEFAULT gen_random_uuid(),
 counterparty_id uuid NOT NULL,
 warehouse_id uuid NOT NULL,
 request_key text NOT NULL CHECK(btrim(request_key)=request_key AND length(request_key) BETWEEN 1 AND 200),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 issued_by uuid NOT NULL REFERENCES core.users(user_id),
 cancelled_at timestamptz,
 cancelled_by uuid REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,purchase_id), UNIQUE(tenant_id,request_key),
 UNIQUE(tenant_id,purchase_id,warehouse_id),
 FOREIGN KEY(tenant_id,counterparty_id) REFERENCES procurement.counterparties(tenant_id,counterparty_id),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 CHECK((cancelled_at IS NULL)=(cancelled_by IS NULL)),
 CHECK(cancelled_at IS NULL OR cancelled_at>=issued_at)
);
CREATE INDEX purchase_supplier_idx ON procurement.purchase_orders(tenant_id,counterparty_id,issued_at);
CREATE TABLE procurement.purchase_items(
 tenant_id uuid NOT NULL,
 purchase_id uuid NOT NULL,
 item_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 quantity bigint NOT NULL CHECK(quantity>0),
 unit_cost numeric(20,4) NOT NULL CHECK(unit_cost>=0 AND unit_cost<>'NaN'::numeric),
 PRIMARY KEY(tenant_id,item_id), UNIQUE(tenant_id,purchase_id,variant_id),
 UNIQUE(tenant_id,purchase_id,item_id,warehouse_id,variant_id,quantity),
 FOREIGN KEY(tenant_id,purchase_id,warehouse_id) REFERENCES procurement.purchase_orders(tenant_id,purchase_id,warehouse_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE TABLE procurement.goods_receipts(
 tenant_id uuid NOT NULL,
 receipt_id uuid NOT NULL DEFAULT gen_random_uuid(),
 purchase_id uuid NOT NULL,
 warehouse_id uuid NOT NULL,
 receipt_key text NOT NULL CHECK(btrim(receipt_key)=receipt_key AND length(receipt_key) BETWEEN 1 AND 200),
 delivery_ref text NOT NULL CHECK(btrim(delivery_ref)=delivery_ref AND length(delivery_ref) BETWEEN 1 AND 200),
 received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 received_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,receipt_id), UNIQUE(tenant_id,purchase_id), UNIQUE(tenant_id,receipt_key),
 UNIQUE(tenant_id,receipt_id,purchase_id,warehouse_id),
 FOREIGN KEY(tenant_id,purchase_id,warehouse_id) REFERENCES procurement.purchase_orders(tenant_id,purchase_id,warehouse_id)
);
-- Receipt line is provenance for the canonical movement, not another stock ledger.
ALTER TABLE inventory.stock_ledger ADD UNIQUE(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta);
CREATE TABLE procurement.receipt_items(
 tenant_id uuid NOT NULL,
 receipt_id uuid NOT NULL,
 purchase_id uuid NOT NULL,
 item_id uuid NOT NULL,
 warehouse_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 quantity bigint NOT NULL CHECK(quantity>0),
 movement_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,receipt_id,item_id), UNIQUE(tenant_id,item_id), UNIQUE(tenant_id,movement_id),
 FOREIGN KEY(tenant_id,receipt_id,purchase_id,warehouse_id) REFERENCES procurement.goods_receipts(tenant_id,receipt_id,purchase_id,warehouse_id),
 FOREIGN KEY(tenant_id,purchase_id,item_id,warehouse_id,variant_id,quantity) REFERENCES procurement.purchase_items(tenant_id,purchase_id,item_id,warehouse_id,variant_id,quantity),
 FOREIGN KEY(tenant_id,movement_id,warehouse_id,variant_id,quantity) REFERENCES inventory.stock_ledger(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta)
);
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['procurement.counterparties'::regclass,'procurement.purchase_orders'::regclass,
 'procurement.purchase_items'::regclass,'procurement.goods_receipts'::regclass,'procurement.receipt_items'::regclass] LOOP
 EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
 EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
 EXECUTE format('CREATE POLICY procurement_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''procurement.read'') AND platform.module_enabled(''procurement''))',rel);
 EXECUTE format('CREATE POLICY procurement_private ON %s FOR ALL TO upc_procurement_executor USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT USAGE ON SCHEMA procurement TO upc_runtime,upc_procurement_executor;
GRANT USAGE ON SCHEMA iam,platform,crm,catalog,inventory TO upc_procurement_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_procurement_executor;
GRANT SELECT ON ALL TABLES IN SCHEMA procurement TO upc_runtime,upc_procurement_executor;
GRANT INSERT ON ALL TABLES IN SCHEMA procurement TO upc_procurement_executor;
GRANT UPDATE(cancelled_at,cancelled_by) ON procurement.purchase_orders TO upc_procurement_executor;
GRANT SELECT ON crm.customers,catalog.products,catalog.variants,inventory.warehouses TO upc_procurement_executor;
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['catalog.products'::regclass,'catalog.variants'::regclass,'inventory.warehouses'::regclass] LOOP
 EXECUTE format('CREATE POLICY procurement_dependency ON %s FOR SELECT TO upc_procurement_executor USING(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
-- Separate receipt permission, no generic inventory.adjust privilege needed.
CREATE FUNCTION inventory.post_purchase_movement(p_warehouse uuid,p_variant uuid,p_quantity bigint,p_key text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.receive'); prior inventory.stock_ledger%ROWTYPE; mid uuid;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_key IS NULL OR p_key NOT LIKE 'purchase-receipt:%'
 THEN RAISE EXCEPTION 'Invalid purchase movement' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-adjust-key',t,p_key)::text,0));
 SELECT * INTO prior FROM inventory.stock_ledger WHERE tenant_id=t AND adjustment_key=p_key;
 IF FOUND THEN
 IF prior.warehouse_id IS DISTINCT FROM p_warehouse OR prior.variant_id IS DISTINCT FROM p_variant
 OR prior.quantity_delta<>p_quantity OR prior.reason<>'purchase receipt'
 THEN RAISE EXCEPTION 'Purchase movement conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.movement_id;
 END IF;
 PERFORM inventory.lock_pair(t,p_warehouse,p_variant);
 PERFORM inventory.assert_pair(t,p_warehouse,p_variant,false);
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_warehouse,p_variant,p_quantity,p_key,'purchase receipt',iam.current_user_id()) RETURNING movement_id INTO mid;
 RETURN mid;
END $$;
ALTER FUNCTION inventory.post_purchase_movement(uuid,uuid,bigint,text) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.post_purchase_movement(uuid,uuid,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.post_purchase_movement(uuid,uuid,bigint,text) TO upc_procurement_executor;
CREATE OR REPLACE FUNCTION inventory.adjust_stock(p_warehouse uuid,p_variant uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM inventory.require_access('inventory.adjust');
 IF p_key LIKE 'sales-return:%' OR p_key LIKE 'purchase-receipt:%' THEN
 RAISE EXCEPTION 'Reserved movement namespace' USING ERRCODE='42501'; END IF;
 RETURN inventory.adjust_stock_internal(p_warehouse,p_variant,p_delta,p_key,p_reason);
END $$;
CREATE FUNCTION procurement.require_access(p_permission text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Procurement access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 RETURN t;
END $$;
ALTER FUNCTION procurement.require_access(text) OWNER TO upc_procurement_executor;
REVOKE ALL ON FUNCTION procurement.require_access(text) FROM PUBLIC;
CREATE FUNCTION procurement.register_counterparty(p_key text,p_customer uuid,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=procurement.require_access('procurement.supplier.write'); prior procurement.counterparties%ROWTYPE; cid uuid;
BEGIN
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_-]{0,99}$' OR (p_customer IS NULL)=(p_name IS NULL)
 THEN RAISE EXCEPTION 'Invalid counterparty' USING ERRCODE='22023'; END IF;
 IF p_customer IS NOT NULL THEN
 IF NOT iam.has_permission('crm.read') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'CRM access denied' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM crm.customers WHERE tenant_id=t AND customer_id=p_customer) THEN RAISE EXCEPTION 'Customer unavailable' USING ERRCODE='23503'; END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-party',t,p_key)::text,0));
 SELECT * INTO prior FROM procurement.counterparties WHERE tenant_id=t AND party_key=p_key;
 IF FOUND THEN
 IF prior.customer_id IS DISTINCT FROM p_customer OR prior.standalone_name IS DISTINCT FROM p_name THEN RAISE EXCEPTION 'Counterparty conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.counterparty_id;
 END IF;
 INSERT INTO procurement.counterparties(tenant_id,party_key,customer_id,standalone_name,created_by)
 VALUES(t,p_key,p_customer,p_name,iam.current_user_id()) RETURNING counterparty_id INTO cid;
 RETURN cid;
END $$;
CREATE FUNCTION procurement.lock_order(p_tenant uuid,p_purchase uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-order',p_tenant,p_purchase)::text,0))
$$;
ALTER FUNCTION procurement.lock_order(uuid,uuid) OWNER TO upc_procurement_executor;
REVOKE ALL ON FUNCTION procurement.lock_order(uuid,uuid) FROM PUBLIC;
CREATE FUNCTION procurement.issue_purchase(p_key text,p_supplier uuid,p_warehouse uuid,p_currency text,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=procurement.require_access('procurement.order.write'); prior procurement.purchase_orders%ROWTYPE;
 norm jsonb; existing jsonb; pid uuid; total numeric;
BEGIN
 IF NOT platform.module_enabled('catalog') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('catalog.read') OR NOT iam.has_permission('inventory.read')
 THEN RAISE EXCEPTION 'Catalog and inventory access required' USING ERRCODE='42501'; END IF;
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_supplier IS NULL OR p_warehouse IS NULL OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
 OR p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION 'Invalid purchase order' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid purchase line count' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) x(variant_id uuid,quantity bigint,unit_cost numeric)
 WHERE variant_id IS NULL OR quantity IS NULL OR quantity<=0 OR unit_cost IS NULL OR unit_cost<0
 OR unit_cost='NaN'::numeric OR unit_cost>=1e16::numeric OR unit_cost<>round(unit_cost,4))
 OR (SELECT count(DISTINCT variant_id) FROM jsonb_to_recordset(p_lines) x(variant_id uuid))<>jsonb_array_length(p_lines)
 THEN RAISE EXCEPTION 'Invalid or duplicate purchase line' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_array(variant_id,quantity,unit_cost) ORDER BY variant_id),sum(quantity*unit_cost)
 INTO norm,total FROM jsonb_to_recordset(p_lines) x(variant_id uuid,quantity bigint,unit_cost numeric);
 IF total<=0 THEN RAISE EXCEPTION 'Positive purchase total required' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-request',t,p_key)::text,0));
 SELECT * INTO prior FROM procurement.purchase_orders WHERE tenant_id=t AND request_key=p_key;
 IF FOUND THEN
 SELECT jsonb_agg(jsonb_build_array(variant_id,quantity,unit_cost) ORDER BY variant_id) INTO existing
 FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=prior.purchase_id;
 IF prior.counterparty_id<>p_supplier OR prior.warehouse_id<>p_warehouse OR prior.currency<>p_currency OR norm IS DISTINCT FROM existing
 THEN RAISE EXCEPTION 'Purchase idempotency conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.purchase_id;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM procurement.counterparties WHERE tenant_id=t AND counterparty_id=p_supplier)
 OR NOT EXISTS(SELECT 1 FROM inventory.warehouses WHERE tenant_id=t AND warehouse_id=p_warehouse)
 OR EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) x(variant_id uuid) WHERE NOT EXISTS(
 SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
 WHERE v.tenant_id=t AND v.variant_id=x.variant_id AND v.is_active AND p.is_active AND p.kind='physical'))
 THEN RAISE EXCEPTION 'Supplier, warehouse or physical variant unavailable' USING ERRCODE='23503'; END IF;
 INSERT INTO procurement.purchase_orders(tenant_id,counterparty_id,warehouse_id,request_key,currency,issued_by)
 VALUES(t,p_supplier,p_warehouse,p_key,p_currency,iam.current_user_id()) RETURNING purchase_id INTO pid;
 INSERT INTO procurement.purchase_items(tenant_id,purchase_id,warehouse_id,variant_id,quantity,unit_cost)
 SELECT t,pid,p_warehouse,variant_id,quantity,unit_cost FROM jsonb_to_recordset(p_lines) x(variant_id uuid,quantity bigint,unit_cost numeric);
 RETURN pid;
END $$;
CREATE FUNCTION procurement.cancel_purchase(p_purchase uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=procurement.require_access('procurement.order.write'); o procurement.purchase_orders%ROWTYPE;
BEGIN
 PERFORM procurement.lock_order(t,p_purchase);
 SELECT * INTO o FROM procurement.purchase_orders WHERE tenant_id=t AND purchase_id=p_purchase;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase unavailable' USING ERRCODE='23503'; END IF;
 IF o.cancelled_at IS NOT NULL THEN RETURN p_purchase; END IF;
 IF EXISTS(SELECT 1 FROM procurement.goods_receipts WHERE tenant_id=t AND purchase_id=p_purchase)
 THEN RAISE EXCEPTION 'Received purchase cannot be cancelled' USING ERRCODE='23514'; END IF;
 UPDATE procurement.purchase_orders SET cancelled_at=clock_timestamp(),cancelled_by=iam.current_user_id() WHERE tenant_id=t AND purchase_id=p_purchase;
 RETURN p_purchase;
END $$;
CREATE FUNCTION procurement.receive_purchase(p_purchase uuid,p_key text,p_delivery text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=procurement.require_access('procurement.receive'); o procurement.purchase_orders%ROWTYPE;
 prior procurement.goods_receipts%ROWTYPE; rid uuid; mid uuid; i procurement.purchase_items%ROWTYPE;
BEGIN
 IF NOT platform.module_enabled('inventory') OR NOT iam.has_permission('inventory.receive') THEN RAISE EXCEPTION 'Inventory receipt permission required' USING ERRCODE='42501'; END IF;
 IF p_purchase IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_delivery IS NULL OR btrim(p_delivery)<>p_delivery OR length(p_delivery) NOT BETWEEN 1 AND 200
 THEN RAISE EXCEPTION 'Invalid receipt' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-receipt-key',t,p_key)::text,0));
 PERFORM procurement.lock_order(t,p_purchase);
 SELECT * INTO prior FROM procurement.goods_receipts WHERE tenant_id=t AND receipt_key=p_key;
 IF FOUND THEN
 IF prior.purchase_id<>p_purchase OR prior.delivery_ref<>p_delivery THEN RAISE EXCEPTION 'Receipt idempotency conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.receipt_id;
 END IF;
 SELECT * INTO o FROM procurement.purchase_orders WHERE tenant_id=t AND purchase_id=p_purchase;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase unavailable' USING ERRCODE='23503'; END IF;
 IF o.cancelled_at IS NOT NULL OR EXISTS(SELECT 1 FROM procurement.goods_receipts WHERE tenant_id=t AND purchase_id=p_purchase)
 THEN RAISE EXCEPTION 'Purchase cancelled or already received' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=p_purchase) THEN RAISE EXCEPTION 'Empty purchase' USING ERRCODE='23514'; END IF;
 INSERT INTO procurement.goods_receipts(tenant_id,purchase_id,warehouse_id,receipt_key,delivery_ref,received_by)
 VALUES(t,p_purchase,o.warehouse_id,p_key,p_delivery,iam.current_user_id()) RETURNING receipt_id INTO rid;
 FOR i IN SELECT * FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=p_purchase ORDER BY variant_id LOOP
 mid:=inventory.post_purchase_movement(i.warehouse_id,i.variant_id,i.quantity,'purchase-receipt:'||rid::text||':'||i.item_id::text);
 INSERT INTO procurement.receipt_items(tenant_id,receipt_id,purchase_id,item_id,warehouse_id,variant_id,quantity,movement_id)
 VALUES(t,rid,p_purchase,i.item_id,i.warehouse_id,i.variant_id,i.quantity,mid);
 END LOOP;
 RETURN rid;
END $$;
DO $$ DECLARE f regprocedure; BEGIN
 FOREACH f IN ARRAY ARRAY['procurement.register_counterparty(text,uuid,text)'::regprocedure,
 'procurement.issue_purchase(text,uuid,uuid,text,jsonb)'::regprocedure,'procurement.cancel_purchase(uuid)'::regprocedure,
 'procurement.receive_purchase(uuid,text,text)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_procurement_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
CREATE VIEW procurement.purchase_summary WITH(security_invoker=true) AS
 SELECT o.tenant_id,o.purchase_id,o.counterparty_id,o.warehouse_id,o.currency,
 CASE WHEN r.receipt_id IS NOT NULL THEN 'received' WHEN o.cancelled_at IS NOT NULL THEN 'cancelled' ELSE 'issued' END AS state,
 r.receipt_id,(SELECT sum(i.quantity*i.unit_cost) FROM procurement.purchase_items i WHERE i.tenant_id=o.tenant_id AND i.purchase_id=o.purchase_id) AS ordered_total
 FROM procurement.purchase_orders o LEFT JOIN procurement.goods_receipts r USING(tenant_id,purchase_id);
GRANT SELECT ON procurement.purchase_summary TO upc_runtime;
COMMIT;

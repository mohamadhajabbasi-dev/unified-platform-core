-- 0023: multi-lot/serial allocation through existing receipt and transfer relations.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
-- Keep variant-first ordering across single- and multi-warehouse operations.
CREATE OR REPLACE FUNCTION inventory.lock_pair(p_tenant uuid,p_warehouse uuid,p_variant uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF p_warehouse IS NULL OR p_variant IS NULL THEN RAISE EXCEPTION 'Warehouse and variant required' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(p_tenant,p_variant);
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-pair',p_tenant,p_warehouse,p_variant)::text,0));
END $$;
CREATE OR REPLACE FUNCTION inventory.guard_trace_movement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE pol inventory.tracking_policies%ROWTYPE; s inventory.serial_numbers%ROWTYPE; qty numeric; total numeric; expiry date;
BEGIN
 IF NEW.tenant_id IS DISTINCT FROM iam.current_tenant_id() THEN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=session_user AND rolsuper) AND NEW.lot_id IS NULL AND NEW.serial_id IS NULL THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Movement scope mismatch' USING ERRCODE='42501';
 END IF;
 PERFORM inventory.lock_trace_variant(NEW.tenant_id,NEW.variant_id);
 SELECT * INTO pol FROM inventory.tracking_policies WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id;
 IF NOT FOUND THEN
 IF NEW.lot_id IS NOT NULL OR NEW.serial_id IS NOT NULL THEN RAISE EXCEPTION 'Untracked variant' USING ERRCODE='23514'; END IF;
 RETURN NEW;
 END IF;
 IF NEW.adjustment_key IS NULL OR (NEW.adjustment_key NOT LIKE 'trace:%' AND NEW.adjustment_key NOT LIKE 'purchase-receipt:%' AND NEW.adjustment_key NOT LIKE 'transfer:%') THEN RAISE EXCEPTION 'Tracked variant requires trace-aware movement' USING ERRCODE='23514'; END IF;
 IF pol.tracking_mode='lot' THEN
 IF NEW.lot_id IS NULL OR NEW.serial_id IS NOT NULL THEN RAISE EXCEPTION 'Lot required' USING ERRCODE='23514'; END IF;
 SELECT COALESCE(sum(quantity_delta),0) INTO qty FROM inventory.stock_ledger WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id AND warehouse_id=NEW.warehouse_id AND lot_id=NEW.lot_id;
 IF qty+NEW.quantity_delta<0 THEN RAISE EXCEPTION 'Insufficient lot stock' USING ERRCODE='23514'; END IF;
 ELSE
 IF NEW.serial_id IS NULL OR NEW.quantity_delta NOT IN (-1,1) THEN RAISE EXCEPTION 'One unit per serial' USING ERRCODE='23514'; END IF;
 SELECT * INTO s FROM inventory.serial_numbers WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id AND serial_id=NEW.serial_id;
 IF NOT FOUND OR s.lot_id IS DISTINCT FROM NEW.lot_id THEN RAISE EXCEPTION 'Serial or lot mismatch' USING ERRCODE='23514'; END IF;
 SELECT COALESCE(sum(quantity_delta),0),COALESCE(sum(quantity_delta) FILTER(WHERE warehouse_id=NEW.warehouse_id),0)
 INTO total,qty FROM inventory.stock_ledger WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id AND serial_id=NEW.serial_id;
 IF total+NEW.quantity_delta NOT BETWEEN 0 AND 1 OR qty+NEW.quantity_delta NOT BETWEEN 0 AND 1 THEN RAISE EXCEPTION 'Serial stock conflict' USING ERRCODE='23514'; END IF;
 END IF;
 IF NEW.lot_id IS NOT NULL THEN
 SELECT expires_on INTO expiry FROM inventory.inventory_lots WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id AND lot_id=NEW.lot_id;
 IF NOT FOUND OR (pol.expiry_required AND expiry IS NULL) THEN RAISE EXCEPTION 'Lot or expiry unavailable' USING ERRCODE='23514'; END IF;
 IF NEW.quantity_delta>0 AND expiry<=(clock_timestamp() AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'Expired stock admission denied' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END $$;

-- A receipt can split one purchase line into several canonical ledger movements.
ALTER TABLE procurement.purchase_items ADD UNIQUE(tenant_id,purchase_id,item_id,warehouse_id,variant_id);
DO $$ DECLARE c record; BEGIN
 FOR c IN SELECT conname FROM pg_constraint WHERE conrelid='procurement.receipt_items'::regclass
 AND (contype='p' OR (contype='u' AND pg_get_constraintdef(oid)='UNIQUE (tenant_id, item_id)')
 OR (contype='f' AND confrelid='procurement.purchase_items'::regclass)) LOOP
 EXECUTE format('ALTER TABLE procurement.receipt_items DROP CONSTRAINT %I',c.conname);
 END LOOP;
END $$;
ALTER TABLE procurement.receipt_items ADD PRIMARY KEY(tenant_id,receipt_id,movement_id);
ALTER TABLE procurement.receipt_items ADD FOREIGN KEY(tenant_id,purchase_id,item_id,warehouse_id,variant_id)
 REFERENCES procurement.purchase_items(tenant_id,purchase_id,item_id,warehouse_id,variant_id);
CREATE INDEX receipt_item_purchase_idx ON procurement.receipt_items(tenant_id,purchase_id,item_id);
ALTER TABLE inventory.transfer_lines DROP CONSTRAINT transfer_lines_pkey;
ALTER TABLE inventory.transfer_lines ADD PRIMARY KEY(tenant_id,transfer_id,outgoing_movement_id);
-- Canonical allocation payload, one row per variant/lot/serial; ordinary rows have both null.
CREATE FUNCTION inventory.normalize_allocations(p_lines jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE result jsonb;
BEGIN
 IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION 'Invalid allocations' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid allocation count' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) x(variant_id uuid,lot_id uuid,serial_id uuid,quantity bigint)
 WHERE variant_id IS NULL OR quantity IS NULL OR quantity<=0 OR (serial_id IS NOT NULL AND quantity<>1))
 OR EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) x(variant_id uuid,lot_id uuid,serial_id uuid)
 GROUP BY variant_id,lot_id,serial_id HAVING count(*)>1)
 THEN RAISE EXCEPTION 'Invalid or duplicate allocation' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_object('variant_id',variant_id,'lot_id',lot_id,'serial_id',serial_id,'quantity',quantity)
 ORDER BY variant_id,lot_id NULLS FIRST,serial_id NULLS FIRST) INTO result
 FROM jsonb_to_recordset(p_lines) x(variant_id uuid,lot_id uuid,serial_id uuid,quantity bigint);
 RETURN result;
END $$;
ALTER FUNCTION inventory.normalize_allocations(jsonb) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.normalize_allocations(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.normalize_allocations(jsonb) TO upc_procurement_executor;
CREATE POLICY receipt_trace_read ON inventory.stock_ledger FOR SELECT TO upc_procurement_executor USING(tenant_id=iam.current_tenant_id());
GRANT SELECT ON inventory.stock_ledger TO upc_procurement_executor;
-- Only private procurement writer can post receipt movements; trace guard checks exact metadata.
CREATE FUNCTION inventory.post_allocated_receipt(p_warehouse uuid,p_variant uuid,p_lot uuid,p_serial uuid,p_qty bigint,p_key text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.receive'); mid uuid;
BEGIN
 IF p_qty IS NULL OR p_qty<=0 OR p_key IS NULL OR p_key NOT LIKE 'purchase-receipt:%' THEN RAISE EXCEPTION 'Invalid receipt allocation' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_pair(t,p_warehouse,p_variant);
 PERFORM inventory.assert_pair(t,p_warehouse,p_variant,false);
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_warehouse,p_variant,p_lot,p_serial,p_qty,p_key,'purchase receipt',iam.current_user_id()) RETURNING movement_id INTO mid;
 RETURN mid;
END $$;
ALTER FUNCTION inventory.post_allocated_receipt(uuid,uuid,uuid,uuid,bigint,text) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.post_allocated_receipt(uuid,uuid,uuid,uuid,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.post_allocated_receipt(uuid,uuid,uuid,uuid,bigint,text) TO upc_procurement_executor;
-- A single canonical receipt API; old three-argument API delegates with ordinary allocations.
CREATE FUNCTION procurement.receive_purchase_allocated(p_purchase uuid,p_key text,p_delivery text,p_allocations jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=procurement.require_access('procurement.receive'); o procurement.purchase_orders%ROWTYPE;
 prior procurement.goods_receipts%ROWTYPE; rid uuid; mid uuid; norm jsonb; existing jsonb; x record; seq integer:=0;
BEGIN
 IF NOT platform.module_enabled('inventory') OR NOT iam.has_permission('inventory.receive') THEN RAISE EXCEPTION 'Inventory receipt permission required' USING ERRCODE='42501'; END IF;
 IF p_purchase IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_delivery IS NULL OR btrim(p_delivery)<>p_delivery OR length(p_delivery) NOT BETWEEN 1 AND 200
 THEN RAISE EXCEPTION 'Invalid receipt' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('procurement-receipt-key',t,p_key)::text,0));
 PERFORM procurement.lock_order(t,p_purchase);
 IF p_allocations IS NULL THEN
 SELECT jsonb_agg(jsonb_build_object('variant_id',variant_id,'quantity',quantity)) INTO p_allocations
 FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=p_purchase;
 END IF;
 norm:=inventory.normalize_allocations(p_allocations);
 SELECT * INTO prior FROM procurement.goods_receipts WHERE tenant_id=t AND receipt_key=p_key;
 IF FOUND THEN
 SELECT inventory.normalize_allocations(jsonb_agg(jsonb_build_object('variant_id',i.variant_id,'lot_id',l.lot_id,'serial_id',l.serial_id,'quantity',i.quantity))) INTO existing
 FROM procurement.receipt_items i JOIN inventory.stock_ledger l USING(tenant_id,movement_id)
 WHERE i.tenant_id=t AND i.receipt_id=prior.receipt_id;
 IF prior.purchase_id<>p_purchase OR prior.delivery_ref<>p_delivery OR existing IS DISTINCT FROM norm THEN RAISE EXCEPTION 'Receipt idempotency conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.receipt_id;
 END IF;
 SELECT * INTO o FROM procurement.purchase_orders WHERE tenant_id=t AND purchase_id=p_purchase;
 IF NOT FOUND THEN RAISE EXCEPTION 'Purchase unavailable' USING ERRCODE='23503'; END IF;
 IF o.cancelled_at IS NOT NULL OR EXISTS(SELECT 1 FROM procurement.goods_receipts WHERE tenant_id=t AND purchase_id=p_purchase)
 THEN RAISE EXCEPTION 'Purchase cancelled or already received' USING ERRCODE='23514'; END IF;
 IF EXISTS(
 SELECT 1 FROM (SELECT variant_id,quantity FROM procurement.purchase_items WHERE tenant_id=t AND purchase_id=p_purchase) i
 FULL JOIN (SELECT variant_id,sum(quantity) quantity FROM jsonb_to_recordset(norm) a(variant_id uuid,quantity bigint) GROUP BY variant_id) a USING(variant_id)
 WHERE i.quantity IS DISTINCT FROM a.quantity
 ) THEN RAISE EXCEPTION 'Receipt allocations must exactly match purchased quantities' USING ERRCODE='23514'; END IF;
 INSERT INTO procurement.goods_receipts(tenant_id,purchase_id,warehouse_id,receipt_key,delivery_ref,received_by)
 VALUES(t,p_purchase,o.warehouse_id,p_key,p_delivery,iam.current_user_id()) RETURNING receipt_id INTO rid;
 FOR x IN SELECT a.*,i.item_id FROM jsonb_to_recordset(norm) a(variant_id uuid,lot_id uuid,serial_id uuid,quantity bigint)
 JOIN procurement.purchase_items i ON i.tenant_id=t AND i.purchase_id=p_purchase AND i.variant_id=a.variant_id
 ORDER BY a.variant_id,a.lot_id NULLS FIRST,a.serial_id NULLS FIRST LOOP
 seq:=seq+1;
 mid:=inventory.post_allocated_receipt(o.warehouse_id,x.variant_id,x.lot_id,x.serial_id,x.quantity,'purchase-receipt:'||rid::text||':'||seq::text);
 INSERT INTO procurement.receipt_items(tenant_id,receipt_id,purchase_id,item_id,warehouse_id,variant_id,quantity,movement_id)
 VALUES(t,rid,p_purchase,x.item_id,o.warehouse_id,x.variant_id,x.quantity,mid);
 END LOOP;
 RETURN rid;
END $$;
ALTER FUNCTION procurement.receive_purchase_allocated(uuid,text,text,jsonb) OWNER TO upc_procurement_executor;
REVOKE ALL ON FUNCTION procurement.receive_purchase_allocated(uuid,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION procurement.receive_purchase_allocated(uuid,text,text,jsonb) TO upc_runtime;
CREATE OR REPLACE FUNCTION procurement.receive_purchase(p_purchase uuid,p_key text,p_delivery text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT procurement.receive_purchase_allocated(p_purchase,p_key,p_delivery,NULL)
$$;
-- Retire the earlier single-movement private entry point.
REVOKE EXECUTE ON FUNCTION inventory.post_purchase_movement(uuid,uuid,bigint,text) FROM upc_procurement_executor;
CREATE FUNCTION inventory.transfer_allocated(p_key text,p_source uuid,p_destination uuid,p_reason text,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.transfer'); prior inventory.warehouse_transfers%ROWTYPE;
 tid uuid; norm jsonb; existing jsonb; x record; mout uuid; min_ uuid; seq integer:=0;
BEGIN
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_source IS NULL OR p_destination IS NULL OR p_source=p_destination OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 500
 THEN RAISE EXCEPTION 'Invalid transfer' USING ERRCODE='22023'; END IF;
 norm:=inventory.normalize_allocations(p_lines);
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-transfer-key',t,p_key)::text,0));
 SELECT * INTO prior FROM inventory.warehouse_transfers WHERE tenant_id=t AND request_key=p_key;
 IF FOUND THEN
 SELECT inventory.normalize_allocations(jsonb_agg(jsonb_build_object('variant_id',i.variant_id,'lot_id',l.lot_id,'serial_id',l.serial_id,'quantity',i.quantity))) INTO existing
 FROM inventory.transfer_lines i JOIN inventory.stock_ledger l ON l.tenant_id=i.tenant_id AND l.movement_id=i.outgoing_movement_id
 WHERE i.tenant_id=t AND i.transfer_id=prior.transfer_id;
 IF prior.source_warehouse_id<>p_source OR prior.destination_warehouse_id<>p_destination OR prior.reason<>p_reason OR existing IS DISTINCT FROM norm
 THEN RAISE EXCEPTION 'Transfer idempotency conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.transfer_id;
 END IF;
 FOR x IN SELECT DISTINCT a.variant_id,w.warehouse_id FROM jsonb_to_recordset(norm) a(variant_id uuid)
 CROSS JOIN unnest(ARRAY[p_source,p_destination]) w(warehouse_id) ORDER BY a.variant_id,w.warehouse_id LOOP
 PERFORM inventory.lock_pair(t,x.warehouse_id,x.variant_id);
 PERFORM inventory.assert_pair(t,x.warehouse_id,x.variant_id,false);
 END LOOP;
 FOR x IN SELECT variant_id,sum(quantity) quantity FROM jsonb_to_recordset(norm) a(variant_id uuid,quantity bigint) GROUP BY variant_id LOOP
 IF inventory.available_units(t,p_source,x.variant_id,clock_timestamp())<x.quantity THEN RAISE EXCEPTION 'Insufficient unreserved stock for transfer' USING ERRCODE='23514'; END IF;
 END LOOP;
 INSERT INTO inventory.warehouse_transfers(tenant_id,source_warehouse_id,destination_warehouse_id,request_key,reason,transferred_by)
 VALUES(t,p_source,p_destination,p_key,p_reason,iam.current_user_id()) RETURNING transfer_id INTO tid;
 FOR x IN SELECT * FROM jsonb_to_recordset(norm) a(variant_id uuid,lot_id uuid,serial_id uuid,quantity bigint)
 ORDER BY variant_id,lot_id NULLS FIRST,serial_id NULLS FIRST LOOP
 seq:=seq+1;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_source,x.variant_id,x.lot_id,x.serial_id,-x.quantity,'transfer:'||tid::text||':'||seq::text||':out','warehouse transfer',iam.current_user_id()) RETURNING movement_id INTO mout;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_destination,x.variant_id,x.lot_id,x.serial_id,x.quantity,'transfer:'||tid::text||':'||seq::text||':in','warehouse transfer',iam.current_user_id()) RETURNING movement_id INTO min_;
 INSERT INTO inventory.transfer_lines(tenant_id,transfer_id,variant_id,source_warehouse_id,destination_warehouse_id,quantity,outgoing_movement_id,incoming_movement_id)
 VALUES(t,tid,x.variant_id,p_source,p_destination,x.quantity,mout,min_);
 END LOOP;
 RETURN tid;
END $$;
ALTER FUNCTION inventory.transfer_allocated(text,uuid,uuid,text,jsonb) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.transfer_allocated(text,uuid,uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.transfer_allocated(text,uuid,uuid,text,jsonb) TO upc_runtime;
CREATE OR REPLACE FUNCTION inventory.transfer_stock(p_key text,p_source uuid,p_destination uuid,p_reason text,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION 'Invalid transfer lines' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_lines) a WHERE a ? 'lot_id' OR a ? 'serial_id') THEN RAISE EXCEPTION 'Use allocated transfer API' USING ERRCODE='22023'; END IF;
 RETURN inventory.transfer_allocated(p_key,p_source,p_destination,p_reason,p_lines);
END $$;
COMMIT;

-- 0024: FEFO allocation and canonical sale fulfillment/return.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE TABLE inventory.reservation_allocations(
 tenant_id uuid NOT NULL, reservation_id uuid NOT NULL, allocation_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL, variant_id uuid NOT NULL, lot_id uuid, serial_id uuid, quantity bigint NOT NULL CHECK(quantity>0),
 PRIMARY KEY(tenant_id,reservation_id,allocation_id),
 UNIQUE NULLS NOT DISTINCT(tenant_id,reservation_id,lot_id,serial_id),
 FOREIGN KEY(tenant_id,reservation_id,warehouse_id,variant_id) REFERENCES inventory.reservations(tenant_id,reservation_id,warehouse_id,variant_id),
 FOREIGN KEY(tenant_id,variant_id,lot_id) REFERENCES inventory.inventory_lots(tenant_id,variant_id,lot_id),
 FOREIGN KEY(tenant_id,variant_id,serial_id) REFERENCES inventory.serial_numbers(tenant_id,variant_id,serial_id),
 CHECK(lot_id IS NOT NULL OR serial_id IS NOT NULL), CHECK(serial_id IS NULL OR quantity=1)
);
CREATE INDEX reservation_trace_pair_idx ON inventory.reservation_allocations(tenant_id,warehouse_id,variant_id,lot_id,serial_id);
ALTER TABLE inventory.reservation_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory.reservation_allocations FORCE ROW LEVEL SECURITY;
CREATE POLICY reservation_alloc_read ON inventory.reservation_allocations FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory'));
CREATE POLICY reservation_alloc_private ON inventory.reservation_allocations FOR ALL TO upc_inventory_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY reservation_alloc_sales ON inventory.reservation_allocations FOR SELECT TO upc_sales_executor USING(tenant_id=iam.current_tenant_id());
GRANT SELECT ON inventory.reservation_allocations TO upc_runtime,upc_inventory_executor,upc_sales_executor;
GRANT INSERT ON inventory.reservation_allocations TO upc_inventory_executor;
ALTER TABLE inventory.stock_ledger ADD COLUMN allocation_id uuid;
DO $$ DECLARE n name; BEGIN
 SELECT conname INTO STRICT n FROM pg_constraint WHERE conrelid='inventory.stock_ledger'::regclass AND contype='u' AND pg_get_constraintdef(oid)='UNIQUE (tenant_id, reservation_id)';
 EXECUTE format('ALTER TABLE inventory.stock_ledger DROP CONSTRAINT %I',n);
END $$;
CREATE UNIQUE INDEX stock_ordinary_reservation_unique ON inventory.stock_ledger(tenant_id,reservation_id) WHERE allocation_id IS NULL;
ALTER TABLE inventory.stock_ledger ADD UNIQUE(tenant_id,reservation_id,allocation_id);
ALTER TABLE inventory.stock_ledger ADD FOREIGN KEY(tenant_id,reservation_id,allocation_id) REFERENCES inventory.reservation_allocations(tenant_id,reservation_id,allocation_id);
ALTER TABLE inventory.stock_ledger ADD CHECK(allocation_id IS NULL OR reservation_id IS NOT NULL);
CREATE FUNCTION inventory.trace_held(p_t uuid,p_w uuid,p_v uuid,p_l uuid,p_s uuid,p_at timestamptz) RETURNS numeric
LANGUAGE sql VOLATILE SET search_path=pg_catalog AS $$
 SELECT COALESCE(sum(a.quantity),0) FROM inventory.reservation_allocations a JOIN inventory.reservations r USING(tenant_id,reservation_id)
 WHERE a.tenant_id=p_t AND a.warehouse_id=p_w AND a.variant_id=p_v AND a.lot_id IS NOT DISTINCT FROM p_l
 AND a.serial_id IS NOT DISTINCT FROM p_s AND r.state='active' AND r.expires_at>p_at
$$;
ALTER FUNCTION inventory.trace_held(uuid,uuid,uuid,uuid,uuid,timestamptz) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.trace_held(uuid,uuid,uuid,uuid,uuid,timestamptz) FROM PUBLIC;
DROP TRIGGER trace_reservation_guard ON inventory.reservations;
CREATE OR REPLACE FUNCTION inventory.guard_trace_movement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE pol inventory.tracking_policies%ROWTYPE; s inventory.serial_numbers%ROWTYPE; qty numeric; total numeric; expiry date; a inventory.reservation_allocations%ROWTYPE;
BEGIN
 IF NEW.tenant_id IS DISTINCT FROM iam.current_tenant_id() THEN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=session_user AND rolsuper) AND NEW.lot_id IS NULL AND NEW.serial_id IS NULL THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Movement scope mismatch' USING ERRCODE='42501';
 END IF;
 PERFORM inventory.lock_trace_variant(NEW.tenant_id,NEW.variant_id);
 SELECT * INTO pol FROM inventory.tracking_policies WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id;
 IF NOT FOUND THEN
 IF NEW.lot_id IS NOT NULL OR NEW.serial_id IS NOT NULL OR NEW.allocation_id IS NOT NULL THEN RAISE EXCEPTION 'Untracked variant' USING ERRCODE='23514'; END IF;
 RETURN NEW;
 END IF;
 IF NEW.reservation_id IS NOT NULL THEN
 SELECT * INTO a FROM inventory.reservation_allocations WHERE tenant_id=NEW.tenant_id AND reservation_id=NEW.reservation_id AND allocation_id=NEW.allocation_id;
 IF NOT FOUND OR a.lot_id IS DISTINCT FROM NEW.lot_id OR a.serial_id IS DISTINCT FROM NEW.serial_id OR a.quantity<>-NEW.quantity_delta
 OR NOT EXISTS(SELECT 1 FROM inventory.reservations r WHERE r.tenant_id=NEW.tenant_id AND r.reservation_id=NEW.reservation_id AND r.state='consumed')
 THEN RAISE EXCEPTION 'Exact consumed allocation required' USING ERRCODE='23514'; END IF;
 ELSIF NEW.adjustment_key IS NULL OR (NEW.adjustment_key NOT LIKE 'trace:%' AND NEW.adjustment_key NOT LIKE 'purchase-receipt:%' AND NEW.adjustment_key NOT LIKE 'transfer:%' AND NEW.adjustment_key NOT LIKE 'sales-return:%')
 THEN RAISE EXCEPTION 'Tracked variant requires trace-aware movement' USING ERRCODE='23514'; END IF;
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
 IF (NEW.quantity_delta>0 OR NEW.reservation_id IS NOT NULL) AND expiry<=(clock_timestamp() AT TIME ZONE 'UTC')::date THEN RAISE EXCEPTION 'Expired stock admission denied' USING ERRCODE='23514'; END IF;
 END IF;
 IF NEW.quantity_delta<0 AND qty+NEW.quantity_delta<inventory.trace_held(NEW.tenant_id,NEW.warehouse_id,NEW.variant_id,NEW.lot_id,NEW.serial_id,clock_timestamp())
 THEN RAISE EXCEPTION 'Insufficient unreserved traced stock' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION inventory.reserve_stock_internal(p_warehouse uuid,p_variant uuid,p_quantity bigint,p_key text,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.reserve'); existing inventory.reservations%ROWTYPE; result_id uuid; at_time timestamptz; remaining bigint; take_qty bigint; x record; tracked boolean; seq integer:=0;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_expires_at IS NULL OR NOT isfinite(p_expires_at) THEN RAISE EXCEPTION 'Invalid reservation' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-reserve-key',t,p_key)::text,0));
 SELECT * INTO existing FROM inventory.reservations WHERE tenant_id=t AND request_key=p_key;
 IF FOUND THEN
  IF existing.warehouse_id IS DISTINCT FROM p_warehouse OR existing.variant_id IS DISTINCT FROM p_variant
  OR existing.quantity<>p_quantity OR existing.expires_at<>p_expires_at THEN
   RAISE EXCEPTION 'Reservation idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN existing.reservation_id;
 END IF;
 PERFORM inventory.lock_pair(t,p_warehouse,p_variant);
 PERFORM inventory.assert_pair(t,p_warehouse,p_variant,true);
 at_time:=clock_timestamp();
 IF p_expires_at<=at_time THEN RAISE EXCEPTION 'Reservation expiry must be future' USING ERRCODE='22023'; END IF;
 SELECT EXISTS(SELECT 1 FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant) INTO tracked;
 IF inventory.available_units(t,p_warehouse,p_variant,at_time)<p_quantity THEN
  RAISE EXCEPTION 'Insufficient unreserved stock' USING ERRCODE='23514';
 END IF;
 INSERT INTO inventory.reservations(tenant_id,warehouse_id,variant_id,request_key,quantity,created_at,expires_at,created_by)
 VALUES(t,p_warehouse,p_variant,p_key,p_quantity,at_time,p_expires_at,iam.current_user_id())
 RETURNING reservation_id INTO result_id;
 IF tracked THEN
  remaining:=p_quantity;
  FOR x IN SELECT m.lot_id,m.serial_id,b.expires_on,
   sum(m.quantity_delta)-inventory.trace_held(t,p_warehouse,p_variant,m.lot_id,m.serial_id,at_time) AS free
   FROM inventory.stock_ledger m LEFT JOIN inventory.inventory_lots b USING(tenant_id,variant_id,lot_id)
   WHERE m.tenant_id=t AND m.warehouse_id=p_warehouse AND m.variant_id=p_variant
   AND (b.expires_on IS NULL OR (b.expires_on>(at_time AT TIME ZONE 'UTC')::date AND p_expires_at<=(b.expires_on::timestamp AT TIME ZONE 'UTC')))
   GROUP BY m.lot_id,m.serial_id,b.expires_on
   ORDER BY b.expires_on NULLS LAST,m.lot_id NULLS LAST,m.serial_id NULLS LAST LOOP
   IF x.free<=0 THEN CONTINUE; END IF;
   take_qty:=least(remaining::numeric,x.free)::bigint;
   seq:=seq+1;
   IF seq>1000 THEN RAISE EXCEPTION 'Too many reservation allocations' USING ERRCODE='23514'; END IF;
   INSERT INTO inventory.reservation_allocations(tenant_id,reservation_id,warehouse_id,variant_id,lot_id,serial_id,quantity)
   VALUES(t,result_id,p_warehouse,p_variant,x.lot_id,x.serial_id,take_qty);
   remaining:=remaining-take_qty;
   EXIT WHEN remaining=0;
  END LOOP;
  IF remaining<>0 THEN RAISE EXCEPTION 'Insufficient eligible traced stock' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN result_id;
END $$;


CREATE OR REPLACE FUNCTION inventory.consume_reservation_internal(p_reservation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.fulfill'); row_data inventory.reservations%ROWTYPE; result_id uuid; at_time timestamptz; x record; mid uuid;
BEGIN
 SELECT * INTO row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reservation unavailable' USING ERRCODE='23503'; END IF;
 PERFORM inventory.lock_pair(t,row_data.warehouse_id,row_data.variant_id);
 SELECT * INTO STRICT row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF row_data.state='consumed' THEN
  SELECT movement_id INTO STRICT result_id FROM inventory.stock_ledger WHERE tenant_id=t AND reservation_id=p_reservation ORDER BY movement_id LIMIT 1;
  RETURN result_id;
 END IF;
 at_time:=clock_timestamp();
 IF row_data.state<>'active' OR row_data.expires_at<=at_time THEN
  RAISE EXCEPTION 'Reservation not active' USING ERRCODE='23514';
 END IF;
 IF inventory.available_units(t,row_data.warehouse_id,row_data.variant_id,at_time)<0 THEN
  RAISE EXCEPTION 'Stock invariant violated' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=row_data.variant_id) THEN
 IF (SELECT sum(quantity) FROM inventory.reservation_allocations WHERE tenant_id=t AND reservation_id=p_reservation) IS DISTINCT FROM row_data.quantity::numeric
 THEN RAISE EXCEPTION 'Incomplete tracked reservation' USING ERRCODE='23514'; END IF;
 UPDATE inventory.reservations SET state='consumed',closed_at=at_time,closed_by=iam.current_user_id()
 WHERE tenant_id=t AND reservation_id=p_reservation;
 FOR x IN SELECT * FROM inventory.reservation_allocations WHERE tenant_id=t AND reservation_id=p_reservation ORDER BY allocation_id LOOP
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,reservation_id,allocation_id,reason,recorded_by)
 VALUES(t,row_data.warehouse_id,row_data.variant_id,x.lot_id,x.serial_id,-x.quantity,p_reservation,x.allocation_id,'reservation fulfillment',iam.current_user_id()) RETURNING movement_id INTO mid;
 END LOOP;
 SELECT movement_id INTO STRICT result_id FROM inventory.stock_ledger WHERE tenant_id=t AND reservation_id=p_reservation ORDER BY movement_id LIMIT 1;
 RETURN result_id;
 END IF;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,reservation_id,reason,recorded_by)
 VALUES(t,row_data.warehouse_id,row_data.variant_id,-row_data.quantity,p_reservation,'reservation fulfillment',iam.current_user_id())
 RETURNING movement_id INTO result_id;
 UPDATE inventory.reservations SET state='consumed',closed_at=at_time,closed_by=iam.current_user_id()
 WHERE tenant_id=t AND reservation_id=p_reservation;
 RETURN result_id;
END $$;


CREATE FUNCTION inventory.return_fulfilled_reservation(p_reservation uuid,p_key text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.adjust'); r inventory.reservations%ROWTYPE; a inventory.reservation_allocations%ROWTYPE;
BEGIN
 IF p_key NOT LIKE 'sales-return:%' THEN RAISE EXCEPTION 'Invalid return namespace' USING ERRCODE='22023'; END IF;
 SELECT * INTO r FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF NOT FOUND OR r.state<>'consumed' THEN RAISE EXCEPTION 'Consumed reservation required' USING ERRCODE='23514'; END IF;
 PERFORM inventory.lock_pair(t,r.warehouse_id,r.variant_id);
 IF NOT EXISTS(SELECT 1 FROM inventory.reservation_allocations WHERE tenant_id=t AND reservation_id=p_reservation) THEN
 PERFORM inventory.adjust_stock_internal(r.warehouse_id,r.variant_id,r.quantity,p_key,'full order return');
 ELSE
 FOR a IN SELECT * FROM inventory.reservation_allocations WHERE tenant_id=t AND reservation_id=p_reservation ORDER BY allocation_id LOOP
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,r.warehouse_id,r.variant_id,a.lot_id,a.serial_id,a.quantity,p_key||':'||a.allocation_id::text,'full order return',iam.current_user_id());
 END LOOP;
 END IF;
END $$;
ALTER FUNCTION inventory.return_fulfilled_reservation(uuid,text) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.return_fulfilled_reservation(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.return_fulfilled_reservation(uuid,text) TO upc_sales_executor;
GRANT EXECUTE ON FUNCTION inventory.normalize_allocations(jsonb) TO upc_sales_executor;
CREATE FUNCTION sales.receive_full_return_allocated(p_order uuid,p_key text,p_reason text,p_allocations jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=sales.require_access('sales.return.receive'); o sales.orders%ROWTYPE; prior sales.returns%ROWTYPE; rid uuid; i record; expected jsonb; norm jsonb;
BEGIN
 IF p_order IS NULL OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_reason IS NULL OR btrim(p_reason)='' THEN RAISE EXCEPTION 'Invalid return' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('sales-return-key',t,p_key)::text,0));
 PERFORM sales.lock_order(t,p_order);
 SELECT inventory.normalize_allocations(jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity))) INTO expected
 FROM sales.order_items oi JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id)
 WHERE oi.tenant_id=t AND oi.order_id=p_order HAVING count(*)>0;
 IF expected IS NOT NULL THEN
 IF p_allocations IS NULL THEN RAISE EXCEPTION 'Return must confirm original traced units' USING ERRCODE='23514'; END IF;
 norm:=inventory.normalize_allocations(p_allocations);
 IF norm IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Return allocation does not match fulfilled units' USING ERRCODE='23514'; END IF;
 ELSIF p_allocations IS NOT NULL THEN RAISE EXCEPTION 'Unexpected traced return allocations' USING ERRCODE='22023'; END IF;
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
 FOR i IN SELECT item_id,warehouse_id,variant_id,quantity,reservation_id FROM sales.order_items
  WHERE tenant_id=t AND order_id=p_order ORDER BY warehouse_id,variant_id LOOP
  PERFORM inventory.return_fulfilled_reservation(i.reservation_id,'sales-return:'||rid::text||':'||i.item_id::text);
 END LOOP;
 UPDATE sales.orders SET state='returned' WHERE tenant_id=t AND order_id=p_order;
 RETURN rid;
END $$;


ALTER FUNCTION sales.receive_full_return_allocated(uuid,text,text,jsonb) OWNER TO upc_sales_executor;
REVOKE ALL ON FUNCTION sales.receive_full_return_allocated(uuid,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION sales.receive_full_return_allocated(uuid,text,text,jsonb) TO upc_runtime;
CREATE OR REPLACE FUNCTION sales.receive_full_return(p_order uuid,p_key text,p_reason text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT sales.receive_full_return_allocated(p_order,p_key,p_reason,NULL)
$$;
CREATE OR REPLACE VIEW inventory.stock_balances WITH(security_invoker=true) AS
 WITH moved AS (SELECT m.tenant_id,m.warehouse_id,m.variant_id,sum(m.quantity_delta) AS on_hand,
 sum(m.quantity_delta) FILTER(WHERE b.expires_on IS NULL OR b.expires_on>(statement_timestamp() AT TIME ZONE 'UTC')::date) AS usable
 FROM inventory.stock_ledger m LEFT JOIN inventory.inventory_lots b USING(tenant_id,variant_id,lot_id)
 GROUP BY m.tenant_id,m.warehouse_id,m.variant_id),
 held AS (SELECT tenant_id,warehouse_id,variant_id,sum(quantity) FILTER(WHERE state='active' AND expires_at>statement_timestamp()) AS reserved
 FROM inventory.reservations GROUP BY tenant_id,warehouse_id,variant_id)
 SELECT tenant_id,warehouse_id,variant_id,COALESCE(on_hand,0) AS on_hand,COALESCE(reserved,0) AS reserved,
 COALESCE(usable,0)-COALESCE(reserved,0) AS available
 FROM moved FULL JOIN held USING(tenant_id,warehouse_id,variant_id);
COMMIT;

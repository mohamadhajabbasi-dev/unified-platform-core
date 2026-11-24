-- 0005: inventory ledger, reservations and derived balances; test database only.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
CREATE SCHEMA inventory;
REVOKE ALL ON SCHEMA inventory FROM PUBLIC;
CREATE ROLE upc_inventory_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('inventory.read','Read inventory'),('inventory.warehouse.write','Maintain warehouses'),
 ('inventory.adjust','Post stock adjustment'),('inventory.reserve','Reserve and release inventory'),
 ('inventory.fulfill','Consume reserved inventory');
INSERT INTO platform.modules(module_key,version_label) VALUES ('inventory','0.1');

CREATE TABLE inventory.warehouses (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 warehouse_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_key text NOT NULL CHECK (warehouse_key ~ '^[a-z0-9][a-z0-9_.-]*$'),
 name text NOT NULL CHECK (btrim(name)<>''),
 PRIMARY KEY(tenant_id,warehouse_id),
 UNIQUE(tenant_id,warehouse_key)
);
-- Whole units for the initial prototype; unit conversion/decimal quantity policy pending.
CREATE TABLE inventory.reservations (
 tenant_id uuid NOT NULL,
 reservation_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 request_key text NOT NULL CHECK (btrim(request_key)=request_key AND length(request_key) BETWEEN 1 AND 200),
 quantity bigint NOT NULL CHECK (quantity>0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL CHECK (isfinite(expires_at)),
 created_by uuid NOT NULL REFERENCES core.users(user_id),
 state text NOT NULL DEFAULT 'active' CHECK (state IN ('active','released','consumed')),
 closed_at timestamptz,
 closed_by uuid REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,reservation_id),
 UNIQUE(tenant_id,request_key),
 UNIQUE(tenant_id,reservation_id,warehouse_id,variant_id),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id),
 CHECK (expires_at>created_at),
 CHECK ((state='active' AND closed_at IS NULL AND closed_by IS NULL) OR
        (state<>'active' AND closed_at IS NOT NULL AND closed_by IS NOT NULL AND closed_at>=created_at))
);
CREATE INDEX reservation_active_pair_idx ON inventory.reservations(tenant_id,warehouse_id,variant_id,expires_at) WHERE state='active';
CREATE TABLE inventory.stock_ledger (
 tenant_id uuid NOT NULL,
 movement_id uuid NOT NULL DEFAULT gen_random_uuid(),
 warehouse_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 quantity_delta bigint NOT NULL CHECK (quantity_delta<>0),
 adjustment_key text CHECK (adjustment_key=btrim(adjustment_key) AND length(adjustment_key) BETWEEN 1 AND 200),
 reservation_id uuid,
 reason text NOT NULL CHECK (btrim(reason)<>''),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,movement_id),
 UNIQUE(tenant_id,adjustment_key),
 UNIQUE(tenant_id,reservation_id),
 FOREIGN KEY(tenant_id,warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,reservation_id,warehouse_id,variant_id)
   REFERENCES inventory.reservations(tenant_id,reservation_id,warehouse_id,variant_id),
 CHECK ((adjustment_key IS NOT NULL AND reservation_id IS NULL) OR
        (adjustment_key IS NULL AND reservation_id IS NOT NULL AND quantity_delta<0))
);
CREATE INDEX stock_ledger_pair_idx ON inventory.stock_ledger(tenant_id,warehouse_id,variant_id);

GRANT USAGE ON SCHEMA inventory,iam,platform,catalog TO upc_inventory_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_inventory_executor;
GRANT SELECT ON catalog.products,catalog.variants TO upc_inventory_executor;
CREATE POLICY inventory_product_dependency ON catalog.products FOR SELECT TO upc_inventory_executor
 USING(tenant_id=iam.current_tenant_id());
CREATE POLICY inventory_variant_dependency ON catalog.variants FOR SELECT TO upc_inventory_executor
 USING(tenant_id=iam.current_tenant_id());
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['inventory.warehouses'::regclass,'inventory.reservations'::regclass,'inventory.stock_ledger'::regclass]
 LOOP
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY inventory_read ON %s FOR SELECT TO upc_runtime USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''inventory.read'') AND platform.module_enabled(''inventory''))',rel);
  EXECUTE format('CREATE POLICY inventory_executor ON %s FOR ALL TO upc_inventory_executor USING (tenant_id=iam.current_tenant_id()) WITH CHECK (tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
CREATE POLICY warehouse_insert ON inventory.warehouses FOR INSERT TO upc_runtime
 WITH CHECK (tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.warehouse.write') AND platform.module_enabled('inventory'));
CREATE POLICY warehouse_update ON inventory.warehouses FOR UPDATE TO upc_runtime
 USING (tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.warehouse.write') AND platform.module_enabled('inventory'))
 WITH CHECK (tenant_id=iam.current_tenant_id() AND iam.has_permission('inventory.read') AND iam.has_permission('inventory.warehouse.write') AND platform.module_enabled('inventory'));
GRANT USAGE ON SCHEMA inventory TO upc_runtime;
GRANT SELECT ON inventory.warehouses,inventory.reservations,inventory.stock_ledger TO upc_runtime;
GRANT INSERT ON inventory.warehouses TO upc_runtime;
GRANT UPDATE(name) ON inventory.warehouses TO upc_runtime;
GRANT SELECT ON inventory.warehouses TO upc_inventory_executor;
GRANT SELECT,INSERT ON inventory.reservations,inventory.stock_ledger TO upc_inventory_executor;
GRANT UPDATE(state,closed_at,closed_by) ON inventory.reservations TO upc_inventory_executor;

-- Helpers callable only by the non-login executor. Reject stale transaction snapshots.
CREATE FUNCTION inventory.require_access(p_permission text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR NOT platform.module_enabled('inventory') THEN
  RAISE EXCEPTION 'Inventory access denied' USING ERRCODE='42501';
 END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Inventory mutations require READ COMMITTED' USING ERRCODE='25000';
 END IF;
 RETURN t;
END $$;
CREATE FUNCTION inventory.lock_pair(p_tenant uuid,p_warehouse uuid,p_variant uuid) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF p_warehouse IS NULL OR p_variant IS NULL THEN RAISE EXCEPTION 'Warehouse and variant required' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-pair',p_tenant,p_warehouse,p_variant)::text,0));
END $$;
CREATE FUNCTION inventory.available_units(p_tenant uuid,p_warehouse uuid,p_variant uuid,p_at timestamptz) RETURNS numeric
LANGUAGE sql VOLATILE SET search_path=pg_catalog AS $$
 SELECT COALESCE((SELECT sum(quantity_delta) FROM inventory.stock_ledger
  WHERE tenant_id=p_tenant AND warehouse_id=p_warehouse AND variant_id=p_variant),0)
 - COALESCE((SELECT sum(quantity) FROM inventory.reservations
  WHERE tenant_id=p_tenant AND warehouse_id=p_warehouse AND variant_id=p_variant
  AND state='active' AND expires_at>p_at),0)
$$;
CREATE FUNCTION inventory.assert_pair(p_tenant uuid,p_warehouse uuid,p_variant uuid,p_active boolean) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM inventory.warehouses w WHERE w.tenant_id=p_tenant AND w.warehouse_id=p_warehouse)
 OR NOT EXISTS(SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
   WHERE v.tenant_id=p_tenant AND v.variant_id=p_variant AND p.kind='physical'
   AND (NOT p_active OR (p.is_active AND v.is_active))) THEN
   RAISE EXCEPTION 'Warehouse or physical variant unavailable' USING ERRCODE='23503';
 END IF;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['inventory.require_access(text)'::regprocedure,
  'inventory.lock_pair(uuid,uuid,uuid)'::regprocedure,
  'inventory.available_units(uuid,uuid,uuid,timestamptz)'::regprocedure,
  'inventory.assert_pair(uuid,uuid,uuid,boolean)'::regprocedure]
 LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_inventory_executor',f);
 END LOOP;
END $$;

CREATE FUNCTION inventory.adjust_stock(p_warehouse uuid,p_variant uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.adjust'); existing inventory.stock_ledger%ROWTYPE; result_id uuid;
BEGIN
 IF p_delta IS NULL OR p_delta=0 OR p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_reason IS NULL OR btrim(p_reason)='' THEN RAISE EXCEPTION 'Invalid adjustment' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-adjust-key',t,p_key)::text,0));
 SELECT * INTO existing FROM inventory.stock_ledger WHERE tenant_id=t AND adjustment_key=p_key;
 IF FOUND THEN
  IF existing.warehouse_id IS DISTINCT FROM p_warehouse OR existing.variant_id IS DISTINCT FROM p_variant
  OR existing.quantity_delta<>p_delta OR existing.reason<>p_reason THEN
   RAISE EXCEPTION 'Adjustment idempotency conflict' USING ERRCODE='23505';
  END IF;
  RETURN existing.movement_id;
 END IF;
 PERFORM inventory.lock_pair(t,p_warehouse,p_variant);
 PERFORM inventory.assert_pair(t,p_warehouse,p_variant,false);
 IF inventory.available_units(t,p_warehouse,p_variant,clock_timestamp())+p_delta<0 THEN
  RAISE EXCEPTION 'Insufficient unreserved stock' USING ERRCODE='23514';
 END IF;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_warehouse,p_variant,p_delta,p_key,p_reason,iam.current_user_id()) RETURNING movement_id INTO result_id;
 RETURN result_id;
END $$;

CREATE FUNCTION inventory.reserve_stock(p_warehouse uuid,p_variant uuid,p_quantity bigint,p_key text,p_expires_at timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.reserve'); existing inventory.reservations%ROWTYPE; result_id uuid; at_time timestamptz;
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
 IF inventory.available_units(t,p_warehouse,p_variant,at_time)<p_quantity THEN
  RAISE EXCEPTION 'Insufficient unreserved stock' USING ERRCODE='23514';
 END IF;
 INSERT INTO inventory.reservations(tenant_id,warehouse_id,variant_id,request_key,quantity,created_at,expires_at,created_by)
 VALUES(t,p_warehouse,p_variant,p_key,p_quantity,at_time,p_expires_at,iam.current_user_id())
 RETURNING reservation_id INTO result_id;
 RETURN result_id;
END $$;

CREATE FUNCTION inventory.release_reservation(p_reservation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.reserve'); row_data inventory.reservations%ROWTYPE;
BEGIN
 SELECT * INTO row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reservation unavailable' USING ERRCODE='23503'; END IF;
 PERFORM inventory.lock_pair(t,row_data.warehouse_id,row_data.variant_id);
 SELECT * INTO STRICT row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF row_data.state='released' THEN RETURN p_reservation; END IF;
 IF row_data.state<>'active' THEN RAISE EXCEPTION 'Consumed reservation cannot be released' USING ERRCODE='23514'; END IF;
 UPDATE inventory.reservations SET state='released',closed_at=clock_timestamp(),closed_by=iam.current_user_id()
 WHERE tenant_id=t AND reservation_id=p_reservation;
 RETURN p_reservation;
END $$;

CREATE FUNCTION inventory.consume_reservation(p_reservation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.fulfill'); row_data inventory.reservations%ROWTYPE; result_id uuid; at_time timestamptz;
BEGIN
 SELECT * INTO row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF NOT FOUND THEN RAISE EXCEPTION 'Reservation unavailable' USING ERRCODE='23503'; END IF;
 PERFORM inventory.lock_pair(t,row_data.warehouse_id,row_data.variant_id);
 SELECT * INTO STRICT row_data FROM inventory.reservations WHERE tenant_id=t AND reservation_id=p_reservation;
 IF row_data.state='consumed' THEN
  SELECT movement_id INTO STRICT result_id FROM inventory.stock_ledger WHERE tenant_id=t AND reservation_id=p_reservation;
  RETURN result_id;
 END IF;
 at_time:=clock_timestamp();
 IF row_data.state<>'active' OR row_data.expires_at<=at_time THEN
  RAISE EXCEPTION 'Reservation not active' USING ERRCODE='23514';
 END IF;
 IF inventory.available_units(t,row_data.warehouse_id,row_data.variant_id,at_time)<0 THEN
  RAISE EXCEPTION 'Stock invariant violated' USING ERRCODE='23514';
 END IF;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,reservation_id,reason,recorded_by)
 VALUES(t,row_data.warehouse_id,row_data.variant_id,-row_data.quantity,p_reservation,'reservation fulfillment',iam.current_user_id())
 RETURNING movement_id INTO result_id;
 UPDATE inventory.reservations SET state='consumed',closed_at=at_time,closed_by=iam.current_user_id()
 WHERE tenant_id=t AND reservation_id=p_reservation;
 RETURN result_id;
END $$;

DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['inventory.adjust_stock(uuid,uuid,bigint,text,text)'::regprocedure,
  'inventory.reserve_stock(uuid,uuid,bigint,text,timestamptz)'::regprocedure,
  'inventory.release_reservation(uuid)'::regprocedure,'inventory.consume_reservation(uuid)'::regprocedure]
 LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO upc_inventory_executor',f);
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
-- Derived only: no independently writable stock quantity.
CREATE VIEW inventory.stock_balances WITH (security_invoker=true) AS
 WITH moved AS (SELECT tenant_id,warehouse_id,variant_id,sum(quantity_delta) AS on_hand
   FROM inventory.stock_ledger GROUP BY tenant_id,warehouse_id,variant_id),
 held AS (SELECT tenant_id,warehouse_id,variant_id,sum(quantity) FILTER
   (WHERE state='active' AND expires_at>statement_timestamp()) AS reserved
   FROM inventory.reservations GROUP BY tenant_id,warehouse_id,variant_id)
 SELECT tenant_id,warehouse_id,variant_id,COALESCE(on_hand,0) AS on_hand,
 COALESCE(reserved,0) AS reserved,COALESCE(on_hand,0)-COALESCE(reserved,0) AS available
 FROM moved FULL JOIN held USING(tenant_id,warehouse_id,variant_id);
GRANT SELECT ON inventory.stock_balances TO upc_runtime;
COMMIT;

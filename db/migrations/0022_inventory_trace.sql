-- 0022: traceability foundation; tracked variants fail closed on unadapted paths.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('inventory.trace.configure','Enroll unused physical variants for tracking'),
 ('inventory.trace.adjust','Post trace-aware stock adjustments');
CREATE TABLE inventory.tracking_policies(
 tenant_id uuid NOT NULL, variant_id uuid NOT NULL,
 tracking_mode text NOT NULL CHECK(tracking_mode IN ('lot','serial')),
 expiry_required boolean NOT NULL DEFAULT false,
 configured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 configured_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id)
);
CREATE TABLE inventory.inventory_lots(
 tenant_id uuid NOT NULL, variant_id uuid NOT NULL, lot_id uuid NOT NULL DEFAULT gen_random_uuid(),
 lot_code text NOT NULL CHECK(btrim(lot_code)=lot_code AND length(lot_code) BETWEEN 1 AND 200),
 manufactured_on date CHECK(isfinite(manufactured_on)),
 expires_on date CHECK(isfinite(expires_on)),
 registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 registered_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,variant_id,lot_id), UNIQUE(tenant_id,variant_id,lot_code),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES inventory.tracking_policies(tenant_id,variant_id),
 CHECK(manufactured_on IS NULL OR expires_on IS NULL OR manufactured_on<=expires_on)
);
CREATE TABLE inventory.serial_numbers(
 tenant_id uuid NOT NULL, variant_id uuid NOT NULL, serial_id uuid NOT NULL DEFAULT gen_random_uuid(),
 serial_code text NOT NULL CHECK(btrim(serial_code)=serial_code AND length(serial_code) BETWEEN 1 AND 200),
 lot_id uuid,
 registered_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 registered_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,variant_id,serial_id), UNIQUE(tenant_id,variant_id,serial_code),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES inventory.tracking_policies(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,variant_id,lot_id) REFERENCES inventory.inventory_lots(tenant_id,variant_id,lot_id)
);
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['inventory.tracking_policies'::regclass,'inventory.inventory_lots'::regclass,'inventory.serial_numbers'::regclass] LOOP
 EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
 EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
 EXECUTE format('CREATE POLICY trace_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''inventory.read'') AND platform.module_enabled(''inventory''))',rel);
 EXECUTE format('CREATE POLICY trace_private ON %s FOR ALL TO upc_inventory_executor USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT ON inventory.tracking_policies,inventory.inventory_lots,inventory.serial_numbers TO upc_runtime,upc_inventory_executor;
GRANT INSERT ON inventory.tracking_policies,inventory.inventory_lots,inventory.serial_numbers TO upc_inventory_executor;
ALTER TABLE inventory.stock_ledger ADD COLUMN lot_id uuid, ADD COLUMN serial_id uuid;
ALTER TABLE inventory.stock_ledger ADD FOREIGN KEY(tenant_id,variant_id,lot_id) REFERENCES inventory.inventory_lots(tenant_id,variant_id,lot_id);
ALTER TABLE inventory.stock_ledger ADD FOREIGN KEY(tenant_id,variant_id,serial_id) REFERENCES inventory.serial_numbers(tenant_id,variant_id,serial_id);
CREATE INDEX stock_trace_lot_idx ON inventory.stock_ledger(tenant_id,variant_id,lot_id,warehouse_id) WHERE lot_id IS NOT NULL;
CREATE INDEX stock_trace_serial_idx ON inventory.stock_ledger(tenant_id,variant_id,serial_id,warehouse_id) WHERE serial_id IS NOT NULL;
-- Serialize policy enrollment and writes for a variant; stock pair locks are acquired first
-- by all movement APIs. Enrollment never acquires a pair lock.
CREATE FUNCTION inventory.lock_trace_variant(p_tenant uuid,p_variant uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-trace-variant',p_tenant,p_variant)::text,0))
$$;
ALTER FUNCTION inventory.lock_trace_variant(uuid,uuid) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.lock_trace_variant(uuid,uuid) FROM PUBLIC;
CREATE FUNCTION inventory.configure_tracking(p_variant uuid,p_mode text,p_expiry boolean DEFAULT false) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.trace.configure'); prior inventory.tracking_policies%ROWTYPE;
BEGIN
 IF p_variant IS NULL OR p_mode IS NULL OR p_mode NOT IN ('lot','serial') OR p_expiry IS NULL
 THEN RAISE EXCEPTION 'Invalid tracking policy' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO prior FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF FOUND THEN
 IF prior.tracking_mode<>p_mode OR prior.expiry_required<>p_expiry THEN RAISE EXCEPTION 'Tracking policy immutable' USING ERRCODE='23505'; END IF;
 RETURN p_variant;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM catalog.variants v JOIN catalog.products p USING(tenant_id,product_id)
 WHERE v.tenant_id=t AND v.variant_id=p_variant AND p.kind='physical' AND p.is_active AND v.is_active)
 THEN RAISE EXCEPTION 'Physical variant unavailable' USING ERRCODE='23503'; END IF;
 IF EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id=t AND variant_id=p_variant)
 OR EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id=t AND variant_id=p_variant)
 THEN RAISE EXCEPTION 'Tracking requires a new unused variant; migration workflow pending' USING ERRCODE='23514'; END IF;
 INSERT INTO inventory.tracking_policies(tenant_id,variant_id,tracking_mode,expiry_required,configured_by)
 VALUES(t,p_variant,p_mode,p_expiry,iam.current_user_id());
 RETURN p_variant;
END $$;
CREATE FUNCTION inventory.register_lot(p_variant uuid,p_code text,p_manufactured date,p_expires date) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.trace.configure'); pol inventory.tracking_policies%ROWTYPE; prior inventory.inventory_lots%ROWTYPE; lid uuid;
BEGIN
 IF p_code IS NULL OR btrim(p_code)<>p_code OR length(p_code) NOT BETWEEN 1 AND 200
 OR (p_manufactured IS NOT NULL AND (NOT isfinite(p_manufactured) OR p_manufactured>(clock_timestamp() AT TIME ZONE 'UTC')::date))
 OR (p_expires IS NOT NULL AND NOT isfinite(p_expires)) OR p_expires<p_manufactured
 THEN RAISE EXCEPTION 'Invalid lot metadata' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO pol FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF NOT FOUND OR (pol.expiry_required AND p_expires IS NULL) THEN RAISE EXCEPTION 'Tracking policy or expiry required' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM inventory.inventory_lots WHERE tenant_id=t AND variant_id=p_variant AND lot_code=p_code;
 IF FOUND THEN
 IF prior.manufactured_on IS DISTINCT FROM p_manufactured OR prior.expires_on IS DISTINCT FROM p_expires THEN RAISE EXCEPTION 'Lot metadata conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.lot_id;
 END IF;
 INSERT INTO inventory.inventory_lots(tenant_id,variant_id,lot_code,manufactured_on,expires_on,registered_by)
 VALUES(t,p_variant,p_code,p_manufactured,p_expires,iam.current_user_id()) RETURNING lot_id INTO lid;
 RETURN lid;
END $$;
CREATE FUNCTION inventory.register_serial(p_variant uuid,p_code text,p_lot uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.trace.configure'); pol inventory.tracking_policies%ROWTYPE; prior inventory.serial_numbers%ROWTYPE; sid uuid;
BEGIN
 IF p_code IS NULL OR btrim(p_code)<>p_code OR length(p_code) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Invalid serial' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO pol FROM inventory.tracking_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF NOT FOUND OR pol.tracking_mode<>'serial' OR (pol.expiry_required AND p_lot IS NULL) THEN RAISE EXCEPTION 'Serial policy or lot required' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM inventory.serial_numbers WHERE tenant_id=t AND variant_id=p_variant AND serial_code=p_code;
 IF FOUND THEN
 IF prior.lot_id IS DISTINCT FROM p_lot THEN RAISE EXCEPTION 'Serial lot conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.serial_id;
 END IF;
 INSERT INTO inventory.serial_numbers(tenant_id,variant_id,serial_code,lot_id,registered_by)
 VALUES(t,p_variant,p_code,p_lot,iam.current_user_id()) RETURNING serial_id INTO sid;
 RETURN sid;
END $$;
-- All current application ledger inserts go through the inventory executor.
-- A mapped session must be scoped; disposable superuser fixture rows are untracked.
CREATE FUNCTION inventory.guard_trace_movement() RETURNS trigger
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
 IF NEW.adjustment_key IS NULL OR NEW.adjustment_key NOT LIKE 'trace:%' THEN RAISE EXCEPTION 'Tracked variant requires trace-aware movement' USING ERRCODE='23514'; END IF;
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
ALTER FUNCTION inventory.guard_trace_movement() OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.guard_trace_movement() FROM PUBLIC;
CREATE TRIGGER trace_movement_guard BEFORE INSERT ON inventory.stock_ledger FOR EACH ROW EXECUTE FUNCTION inventory.guard_trace_movement();
CREATE FUNCTION inventory.guard_trace_reservation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.tenant_id IS DISTINCT FROM iam.current_tenant_id() THEN
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=session_user AND rolsuper) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Reservation scope mismatch' USING ERRCODE='42501'; END IF;
 PERFORM inventory.lock_trace_variant(NEW.tenant_id,NEW.variant_id);
 IF EXISTS(SELECT 1 FROM inventory.tracking_policies WHERE tenant_id=NEW.tenant_id AND variant_id=NEW.variant_id)
 THEN RAISE EXCEPTION 'Tracked reservation allocation not yet enabled' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
ALTER FUNCTION inventory.guard_trace_reservation() OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.guard_trace_reservation() FROM PUBLIC;
CREATE TRIGGER trace_reservation_guard BEFORE INSERT ON inventory.reservations FOR EACH ROW EXECUTE FUNCTION inventory.guard_trace_reservation();
CREATE OR REPLACE FUNCTION inventory.adjust_stock(p_warehouse uuid,p_variant uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM inventory.require_access('inventory.adjust');
 IF p_key LIKE 'sales-return:%' OR p_key LIKE 'purchase-receipt:%' OR p_key LIKE 'transfer:%' OR p_key LIKE 'trace:%' THEN
 RAISE EXCEPTION 'Reserved movement namespace' USING ERRCODE='42501'; END IF;
 RETURN inventory.adjust_stock_internal(p_warehouse,p_variant,p_delta,p_key,p_reason);
END $$;

CREATE FUNCTION inventory.adjust_traced(p_warehouse uuid,p_variant uuid,p_lot uuid,p_serial uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.trace.adjust'); k text; prior inventory.stock_ledger%ROWTYPE; mid uuid;
BEGIN
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 190 OR p_delta IS NULL OR p_delta=0
 OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 500 OR (p_lot IS NULL AND p_serial IS NULL)
 THEN RAISE EXCEPTION 'Invalid trace adjustment' USING ERRCODE='22023'; END IF;
 k:='trace:'||p_key;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-adjust-key',t,k)::text,0));
 SELECT * INTO prior FROM inventory.stock_ledger WHERE tenant_id=t AND adjustment_key=k;
 IF FOUND THEN
 IF prior.warehouse_id IS DISTINCT FROM p_warehouse OR prior.variant_id IS DISTINCT FROM p_variant OR prior.lot_id IS DISTINCT FROM p_lot
 OR prior.serial_id IS DISTINCT FROM p_serial OR prior.quantity_delta<>p_delta OR prior.reason<>p_reason
 THEN RAISE EXCEPTION 'Trace adjustment conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.movement_id;
 END IF;
 PERFORM inventory.lock_pair(t,p_warehouse,p_variant);
 PERFORM inventory.assert_pair(t,p_warehouse,p_variant,false);
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,lot_id,serial_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_warehouse,p_variant,p_lot,p_serial,p_delta,k,p_reason,iam.current_user_id()) RETURNING movement_id INTO mid;
 RETURN mid;
END $$;
DO $$ DECLARE f regprocedure; BEGIN
 FOREACH f IN ARRAY ARRAY['inventory.configure_tracking(uuid,text,boolean)'::regprocedure,'inventory.register_lot(uuid,text,date,date)'::regprocedure,
 'inventory.register_serial(uuid,text,uuid)'::regprocedure,'inventory.adjust_traced(uuid,uuid,uuid,uuid,bigint,text,text)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_inventory_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_runtime',f);
 END LOOP;
END $$;
-- Physical balances remain authoritative. Tracked variants are not available to the
-- unadapted sales reservation API; show zero ordinary availability until allocation exists.
CREATE OR REPLACE VIEW inventory.stock_balances WITH(security_invoker=true) AS
 WITH moved AS (SELECT tenant_id,warehouse_id,variant_id,sum(quantity_delta) AS on_hand FROM inventory.stock_ledger GROUP BY tenant_id,warehouse_id,variant_id),
 held AS (SELECT tenant_id,warehouse_id,variant_id,sum(quantity) FILTER(WHERE state='active' AND expires_at>statement_timestamp()) AS reserved
 FROM inventory.reservations GROUP BY tenant_id,warehouse_id,variant_id)
 SELECT b.tenant_id,b.warehouse_id,b.variant_id,COALESCE(b.on_hand,0) AS on_hand,COALESCE(b.reserved,0) AS reserved,
 CASE WHEN p.variant_id IS NOT NULL THEN 0::numeric ELSE COALESCE(b.on_hand,0)-COALESCE(b.reserved,0) END AS available
 FROM (SELECT tenant_id,warehouse_id,variant_id,on_hand,reserved FROM moved FULL JOIN held USING(tenant_id,warehouse_id,variant_id)) b
 LEFT JOIN inventory.tracking_policies p USING(tenant_id,variant_id);
CREATE VIEW inventory.trace_balances WITH(security_invoker=true) AS
 SELECT l.tenant_id,l.warehouse_id,l.variant_id,l.lot_id,l.serial_id,sum(l.quantity_delta) AS on_hand,
 b.expires_on,CASE WHEN b.expires_on IS NULL THEN 'no_expiry' WHEN b.expires_on<=(statement_timestamp() AT TIME ZONE 'UTC')::date THEN 'expired' ELSE 'valid' END AS expiry_state
 FROM inventory.stock_ledger l LEFT JOIN inventory.inventory_lots b USING(tenant_id,variant_id,lot_id)
 WHERE l.lot_id IS NOT NULL OR l.serial_id IS NOT NULL
 GROUP BY l.tenant_id,l.warehouse_id,l.variant_id,l.lot_id,l.serial_id,b.expires_on HAVING sum(l.quantity_delta)<>0;
GRANT SELECT ON inventory.trace_balances TO upc_runtime;
COMMIT;

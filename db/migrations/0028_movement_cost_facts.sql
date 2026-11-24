-- 0028: confirmed movement cost facts; capture is explicit, not a journal posting.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.replay_valuation_movements(p_warehouse uuid,p_variant uuid,p_currency text,p_method text)
RETURNS TABLE(step_no bigint,movement_id uuid,quantity_delta bigint,value_delta numeric,on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE m record; t uuid:=iam.current_tenant_id(); q numeric:=0; val numeric:=0; spent numeric:=0;
 take_qty numeric; cost numeric; remaining numeric; idx integer:=1;
 layer_qty numeric[]:=ARRAY[]::numeric[]; layer_cost numeric[]:=ARRAY[]::numeric[];
 confirmed boolean:=true; seq bigint:=0;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Valuation access denied' USING ERRCODE='42501'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
 OR p_method IS NULL OR p_method NOT IN ('fifo','moving_average') THEN
 RAISE EXCEPTION 'Invalid valuation arguments' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.warehouses w WHERE w.tenant_id=t AND w.warehouse_id=p_warehouse)
 THEN RAISE EXCEPTION 'Warehouse unavailable' USING ERRCODE='23503'; END IF;
 -- No partial results for unsupported movements or absent stock history.
 FOR m IN SELECT l.movement_id,l.quantity_delta,l.reservation_id,l.lot_id,l.serial_id,
 b.movement_id AS receipt_movement,b.quantity AS receipt_qty,b.agreed_cost,b.currency,b.invoice_id
 FROM inventory.stock_ledger l LEFT JOIN finance.receipt_cost_basis b
 ON b.tenant_id=l.tenant_id AND b.movement_id=l.movement_id
 WHERE l.tenant_id=t AND l.warehouse_id=p_warehouse AND l.variant_id=p_variant
 ORDER BY l.recorded_at,l.movement_id
 LOOP
 IF m.lot_id IS NOT NULL OR m.serial_id IS NOT NULL THEN
 RAISE EXCEPTION 'Tracked valuation not supported in preview' USING ERRCODE='23514'; END IF;
 IF m.quantity_delta>0 THEN
 IF m.receipt_movement IS NULL OR m.receipt_qty IS DISTINCT FROM m.quantity_delta OR m.currency IS DISTINCT FROM p_currency
 OR m.agreed_cost IS NULL OR m.agreed_cost<0 OR m.agreed_cost='NaN'::numeric THEN
 RAISE EXCEPTION 'Unknown or incompatible receipt cost' USING ERRCODE='23514'; END IF;
 confirmed:=confirmed AND m.invoice_id IS NOT NULL;
 q:=q+m.quantity_delta; val:=val+m.agreed_cost; cost:=m.agreed_cost;
 IF p_method='fifo' THEN
 layer_qty:=array_append(layer_qty,m.quantity_delta::numeric);
 layer_cost:=array_append(layer_cost,m.agreed_cost);
 END IF;
 ELSE
 IF m.reservation_id IS NULL OR q< -m.quantity_delta THEN
 RAISE EXCEPTION 'Unsupported or uncosted stock outflow' USING ERRCODE='23514'; END IF;
 remaining:= -m.quantity_delta; cost:=0;
 IF p_method='moving_average' THEN
 cost:=CASE WHEN remaining=q THEN val ELSE round(val*remaining/q,4) END;
 ELSE
 WHILE remaining>0 LOOP
 take_qty:=least(remaining,layer_qty[idx]);
 IF take_qty IS NULL OR take_qty<=0 THEN RAISE EXCEPTION 'Missing cost layer' USING ERRCODE='23514'; END IF;
 DECLARE part numeric; BEGIN
 part:=CASE WHEN take_qty=layer_qty[idx] THEN layer_cost[idx] ELSE round(layer_cost[idx]*take_qty/layer_qty[idx],4) END;
 cost:=cost+part; layer_qty[idx]:=layer_qty[idx]-take_qty; layer_cost[idx]:=layer_cost[idx]-part;
 END;
 remaining:=remaining-take_qty;
 IF layer_qty[idx]=0 THEN idx:=idx+1; END IF;
 END LOOP;
 END IF;
 q:=q+m.quantity_delta; val:=val-cost; spent:=spent+cost;
 END IF;
 seq:=seq+1;
 RETURN QUERY SELECT seq,m.movement_id,m.quantity_delta,CASE WHEN m.quantity_delta>0 THEN cost ELSE -cost END,q,val,spent,confirmed;
 END LOOP;
 IF NOT FOUND THEN RAISE EXCEPTION 'No visible stock history' USING ERRCODE='23503'; END IF;
END $$;

REVOKE ALL ON FUNCTION finance.replay_valuation_movements(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.replay_valuation_movements(uuid,uuid,text,text) TO upc_runtime,upc_finance_executor;
CREATE OR REPLACE FUNCTION finance.preview_inventory_valuation(p_warehouse uuid,p_variant uuid,p_currency text,p_method text)
RETURNS TABLE(on_hand numeric,remaining_value numeric,consumed_cost numeric,all_receipts_invoiced boolean)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT x.on_hand,x.remaining_value,x.consumed_cost,x.all_receipts_invoiced
 FROM finance.replay_valuation_movements(p_warehouse,p_variant,p_currency,p_method) x ORDER BY x.step_no DESC LIMIT 1
$$;
INSERT INTO iam.permissions VALUES ('finance.valuation.capture','Capture confirmed experimental movement costs');
CREATE TABLE finance.movement_cost_facts(
 tenant_id uuid NOT NULL, movement_id uuid NOT NULL, warehouse_id uuid NOT NULL, variant_id uuid NOT NULL,
 quantity_delta bigint NOT NULL CHECK(quantity_delta<>0),
 sequence_no bigint NOT NULL CHECK(sequence_no>0),
 value_delta numeric(40,4) NOT NULL CHECK(value_delta<>'NaN'::numeric),
 captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 captured_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,movement_id),
 UNIQUE(tenant_id,warehouse_id,variant_id,sequence_no),
 FOREIGN KEY(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta)
 REFERENCES inventory.stock_ledger(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES finance.valuation_policies(tenant_id,variant_id),
 CHECK((quantity_delta>0 AND value_delta>=0) OR (quantity_delta<0 AND value_delta<=0))
);
ALTER TABLE finance.movement_cost_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE finance.movement_cost_facts FORCE ROW LEVEL SECURITY;
CREATE POLICY cost_read ON finance.movement_cost_facts FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('finance.read') AND platform.module_enabled('finance')
 AND iam.has_permission('inventory.read') AND platform.module_enabled('inventory')
 AND iam.has_permission('procurement.read') AND platform.module_enabled('procurement'));
CREATE POLICY cost_writer ON finance.movement_cost_facts FOR ALL TO upc_finance_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT SELECT ON finance.movement_cost_facts TO upc_runtime,upc_finance_executor;
GRANT INSERT ON finance.movement_cost_facts TO upc_finance_executor;
GRANT USAGE ON SCHEMA inventory TO upc_finance_executor;
GRANT EXECUTE ON FUNCTION inventory.lock_trace_variant(uuid,uuid) TO upc_finance_executor;
GRANT SELECT ON inventory.stock_ledger,inventory.warehouses,procurement.receipt_items,finance.valuation_policies,finance.receipt_cost_basis TO upc_finance_executor;
CREATE POLICY cost_stock_dependency ON inventory.stock_ledger FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY cost_warehouse_dependency ON inventory.warehouses FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY cost_receipt_dependency ON procurement.receipt_items FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY cost_policy_dependency ON finance.valuation_policies FOR SELECT TO upc_finance_executor USING(tenant_id=iam.current_tenant_id());
CREATE FUNCTION finance.capture_movement_costs(p_warehouse uuid,p_variant uuid) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.valuation.capture'); pol finance.valuation_policies%ROWTYPE;
 m record; prior finance.movement_cost_facts%ROWTYPE; n bigint:=0;
BEGIN
 IF NOT iam.has_permission('finance.read') OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 THEN RAISE EXCEPTION 'Valuation access denied' USING ERRCODE='42501'; END IF;
 IF p_warehouse IS NULL OR p_variant IS NULL THEN RAISE EXCEPTION 'Invalid valuation scope' USING ERRCODE='22023'; END IF;
 PERFORM inventory.lock_trace_variant(t,p_variant);
 SELECT * INTO pol FROM finance.valuation_policies WHERE tenant_id=t AND variant_id=p_variant;
 IF NOT FOUND THEN RAISE EXCEPTION 'Valuation policy unavailable' USING ERRCODE='23503'; END IF;
 FOR m IN SELECT * FROM finance.replay_valuation_movements(p_warehouse,p_variant,pol.currency,pol.method) ORDER BY step_no LOOP
 IF NOT m.all_receipts_invoiced THEN RAISE EXCEPTION 'Confirmed receipt invoices required' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM finance.movement_cost_facts WHERE tenant_id=t AND movement_id=m.movement_id;
 IF FOUND THEN
 IF prior.sequence_no<>m.step_no OR prior.value_delta<>m.value_delta OR prior.quantity_delta<>m.quantity_delta
 THEN RAISE EXCEPTION 'Previously captured cost differs from replay' USING ERRCODE='23514'; END IF;
 ELSE
 INSERT INTO finance.movement_cost_facts(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta,sequence_no,value_delta,captured_by)
 VALUES(t,m.movement_id,p_warehouse,p_variant,m.quantity_delta,m.step_no,m.value_delta,iam.current_user_id());
 n:=n+1;
 END IF;
 END LOOP;
 RETURN n;
END $$;
ALTER FUNCTION finance.capture_movement_costs(uuid,uuid) OWNER TO upc_finance_executor;
REVOKE ALL ON FUNCTION finance.capture_movement_costs(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.capture_movement_costs(uuid,uuid) TO upc_runtime;
COMMIT;

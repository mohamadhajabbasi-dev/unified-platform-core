-- 0021: atomic interwarehouse transfer using the canonical ledger; supplier settlement hardening.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE OR REPLACE FUNCTION finance.record_supplier_settlement(p_invoice uuid,p_channel text,p_account_ref text,p_payment_ref text,
 p_amount numeric,p_currency text,p_paid_at timestamptz,p_digest bytea,p_cash uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=finance.require_access('finance.post.supplier_settlement'); inv finance.supplier_invoices%ROWTYPE;
 prior finance.supplier_settlements%ROWTYPE; sid uuid; payable uuid; posted uuid; paid numeric;
BEGIN
 IF p_invoice IS NULL OR p_channel IS NULL OR p_channel NOT IN ('bank','cash','other')
 OR p_account_ref IS NULL OR btrim(p_account_ref)<>p_account_ref OR length(p_account_ref) NOT BETWEEN 1 AND 200
 OR p_payment_ref IS NULL OR btrim(p_payment_ref)<>p_payment_ref OR length(p_payment_ref) NOT BETWEEN 1 AND 200
 OR p_amount IS NULL OR p_amount<=0 OR p_amount='NaN'::numeric OR p_amount>=1e36::numeric OR p_amount<>round(p_amount,4)
 OR p_currency IS NULL OR p_paid_at IS NULL OR NOT isfinite(p_paid_at) OR p_paid_at>clock_timestamp()
 OR p_digest IS NULL OR octet_length(p_digest)<>32 THEN RAISE EXCEPTION 'Invalid verified settlement' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('supplier-payment-ref',t,p_channel,p_account_ref,p_payment_ref)::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('supplier-invoice',t,p_invoice)::text,0));
 SELECT * INTO inv FROM finance.supplier_invoices WHERE tenant_id=t AND invoice_id=p_invoice;
 IF NOT FOUND THEN RAISE EXCEPTION 'Supplier invoice unavailable' USING ERRCODE='23503'; END IF;
 IF p_currency<>inv.currency OR (p_paid_at AT TIME ZONE 'UTC')::date<inv.invoice_date THEN RAISE EXCEPTION 'Settlement currency or date mismatch' USING ERRCODE='23514'; END IF;
 SELECT entry_id INTO posted FROM finance.journal_entries WHERE tenant_id=t AND supplier_invoice_id=p_invoice;
 IF NOT FOUND THEN RAISE EXCEPTION 'Recognized invoice required' USING ERRCODE='23514'; END IF;
 SELECT account_id INTO STRICT payable FROM finance.journal_lines WHERE tenant_id=t AND entry_id=posted AND amount=-inv.amount;
 IF EXISTS(SELECT 1 FROM finance.journal_lines WHERE tenant_id=t AND entry_id=posted AND account_id=p_cash AND amount>0)
 THEN RAISE EXCEPTION 'Inventory asset cannot serve as disbursement account' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.accounts WHERE tenant_id=t AND account_id=p_cash AND currency=p_currency AND account_type='asset')
 THEN RAISE EXCEPTION 'Matching disbursement asset account required' USING ERRCODE='23503'; END IF;
 SELECT * INTO prior FROM finance.supplier_settlements WHERE tenant_id=t AND payment_channel=p_channel AND account_ref=p_account_ref AND payment_ref=p_payment_ref;
 IF FOUND THEN
 IF prior.invoice_id<>p_invoice OR prior.amount<>p_amount OR prior.currency<>p_currency OR prior.paid_at<>p_paid_at OR prior.evidence_digest<>p_digest
 THEN RAISE EXCEPTION 'Settlement idempotency conflict' USING ERRCODE='23505'; END IF;
 sid:=prior.settlement_id;
 ELSE
 SELECT COALESCE(sum(amount),0) INTO paid FROM finance.supplier_settlements WHERE tenant_id=t AND invoice_id=p_invoice;
 IF paid+p_amount>inv.amount THEN RAISE EXCEPTION 'Settlement exceeds payable' USING ERRCODE='23514'; END IF;
 INSERT INTO finance.supplier_settlements(tenant_id,invoice_id,currency,payment_channel,account_ref,payment_ref,amount,paid_at,evidence_digest,recorded_by)
 VALUES(t,p_invoice,p_currency,p_channel,p_account_ref,p_payment_ref,p_amount,p_paid_at,p_digest,iam.current_user_id()) RETURNING settlement_id INTO sid;
 END IF;
 PERFORM finance.write_entry(t,'supplier-settlement:'||sid::text,p_currency,'Verified supplier settlement',
 jsonb_build_array(jsonb_build_object('account_id',payable,'amount',p_amount),jsonb_build_object('account_id',p_cash,'amount',-p_amount)),NULL,NULL);
 RETURN sid;
END $$;

INSERT INTO iam.permissions VALUES ('inventory.transfer','Post atomic interwarehouse transfers');
CREATE TABLE inventory.warehouse_transfers(
 tenant_id uuid NOT NULL,
 transfer_id uuid NOT NULL DEFAULT gen_random_uuid(),
 source_warehouse_id uuid NOT NULL,
 destination_warehouse_id uuid NOT NULL,
 request_key text NOT NULL CHECK(btrim(request_key)=request_key AND length(request_key) BETWEEN 1 AND 200),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 500),
 transferred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 transferred_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,transfer_id), UNIQUE(tenant_id,request_key),
 UNIQUE(tenant_id,transfer_id,source_warehouse_id,destination_warehouse_id),
 FOREIGN KEY(tenant_id,source_warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 FOREIGN KEY(tenant_id,destination_warehouse_id) REFERENCES inventory.warehouses(tenant_id,warehouse_id),
 CHECK(source_warehouse_id<>destination_warehouse_id)
);
CREATE TABLE inventory.transfer_lines(
 tenant_id uuid NOT NULL,
 transfer_id uuid NOT NULL,
 variant_id uuid NOT NULL,
 source_warehouse_id uuid NOT NULL,
 destination_warehouse_id uuid NOT NULL,
 quantity bigint NOT NULL CHECK(quantity>0),
 outgoing_delta bigint GENERATED ALWAYS AS (-quantity) STORED,
 outgoing_movement_id uuid NOT NULL,
 incoming_movement_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,transfer_id,variant_id),
 UNIQUE(tenant_id,outgoing_movement_id), UNIQUE(tenant_id,incoming_movement_id),
 FOREIGN KEY(tenant_id,transfer_id,source_warehouse_id,destination_warehouse_id)
 REFERENCES inventory.warehouse_transfers(tenant_id,transfer_id,source_warehouse_id,destination_warehouse_id),
 FOREIGN KEY(tenant_id,outgoing_movement_id,source_warehouse_id,variant_id,outgoing_delta)
 REFERENCES inventory.stock_ledger(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta),
 FOREIGN KEY(tenant_id,incoming_movement_id,destination_warehouse_id,variant_id,quantity)
 REFERENCES inventory.stock_ledger(tenant_id,movement_id,warehouse_id,variant_id,quantity_delta),
 CHECK(outgoing_movement_id<>incoming_movement_id)
);
CREATE INDEX warehouse_transfer_source_idx ON inventory.warehouse_transfers(tenant_id,source_warehouse_id,transferred_at);
CREATE INDEX warehouse_transfer_destination_idx ON inventory.warehouse_transfers(tenant_id,destination_warehouse_id,transferred_at);
DO $$ DECLARE rel regclass; BEGIN
 FOREACH rel IN ARRAY ARRAY['inventory.warehouse_transfers'::regclass,'inventory.transfer_lines'::regclass] LOOP
 EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
 EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
 EXECUTE format('CREATE POLICY transfer_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''inventory.read'') AND platform.module_enabled(''inventory''))',rel);
 EXECUTE format('CREATE POLICY transfer_private ON %s FOR ALL TO upc_inventory_executor USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT ON inventory.warehouse_transfers,inventory.transfer_lines TO upc_runtime,upc_inventory_executor;
GRANT INSERT ON inventory.warehouse_transfers,inventory.transfer_lines TO upc_inventory_executor;
CREATE OR REPLACE FUNCTION inventory.adjust_stock(p_warehouse uuid,p_variant uuid,p_delta bigint,p_key text,p_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM inventory.require_access('inventory.adjust');
 IF p_key LIKE 'sales-return:%' OR p_key LIKE 'purchase-receipt:%' OR p_key LIKE 'transfer:%' THEN
 RAISE EXCEPTION 'Reserved movement namespace' USING ERRCODE='42501'; END IF;
 RETURN inventory.adjust_stock_internal(p_warehouse,p_variant,p_delta,p_key,p_reason);
END $$;
-- Immediate physical handover only. Transit shipments require a separate lifecycle.
-- Lock every warehouse/variant pair in consistent global order before any movement.
CREATE FUNCTION inventory.transfer_stock(p_key text,p_source uuid,p_destination uuid,p_reason text,p_lines jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=inventory.require_access('inventory.transfer'); prior inventory.warehouse_transfers%ROWTYPE;
 tid uuid; norm jsonb; existing jsonb; x record; mid_out uuid; mid_in uuid;
BEGIN
 IF p_key IS NULL OR btrim(p_key)<>p_key OR length(p_key) NOT BETWEEN 1 AND 200
 OR p_source IS NULL OR p_destination IS NULL OR p_source=p_destination
 OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 1 AND 500
 OR p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' THEN RAISE EXCEPTION 'Invalid transfer' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Invalid transfer line count' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_to_recordset(p_lines) a(variant_id uuid,quantity bigint) WHERE variant_id IS NULL OR quantity IS NULL OR quantity<=0)
 OR (SELECT count(DISTINCT variant_id) FROM jsonb_to_recordset(p_lines) a(variant_id uuid))<>jsonb_array_length(p_lines)
 THEN RAISE EXCEPTION 'Invalid or duplicate transfer line' USING ERRCODE='22023'; END IF;
 SELECT jsonb_agg(jsonb_build_array(variant_id,quantity) ORDER BY variant_id) INTO norm
 FROM jsonb_to_recordset(p_lines) a(variant_id uuid,quantity bigint);
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('inventory-transfer-key',t,p_key)::text,0));
 SELECT * INTO prior FROM inventory.warehouse_transfers WHERE tenant_id=t AND request_key=p_key;
 IF FOUND THEN
 SELECT jsonb_agg(jsonb_build_array(variant_id,quantity) ORDER BY variant_id) INTO existing FROM inventory.transfer_lines WHERE tenant_id=t AND transfer_id=prior.transfer_id;
 IF prior.source_warehouse_id<>p_source OR prior.destination_warehouse_id<>p_destination OR prior.reason<>p_reason OR existing IS DISTINCT FROM norm
 THEN RAISE EXCEPTION 'Transfer idempotency conflict' USING ERRCODE='23505'; END IF;
 RETURN prior.transfer_id;
 END IF;
 FOR x IN SELECT w.warehouse_id,a.variant_id FROM unnest(ARRAY[p_source,p_destination]) w(warehouse_id)
 CROSS JOIN jsonb_to_recordset(p_lines) a(variant_id uuid) ORDER BY w.warehouse_id,a.variant_id LOOP
 PERFORM inventory.lock_pair(t,x.warehouse_id,x.variant_id);
 PERFORM inventory.assert_pair(t,x.warehouse_id,x.variant_id,false);
 END LOOP;
 FOR x IN SELECT * FROM jsonb_to_recordset(p_lines) a(variant_id uuid,quantity bigint) LOOP
 IF inventory.available_units(t,p_source,x.variant_id,clock_timestamp())<x.quantity
 THEN RAISE EXCEPTION 'Insufficient unreserved stock for transfer' USING ERRCODE='23514'; END IF;
 END LOOP;
 INSERT INTO inventory.warehouse_transfers(tenant_id,source_warehouse_id,destination_warehouse_id,request_key,reason,transferred_by)
 VALUES(t,p_source,p_destination,p_key,p_reason,iam.current_user_id()) RETURNING transfer_id INTO tid;
 FOR x IN SELECT * FROM jsonb_to_recordset(p_lines) a(variant_id uuid,quantity bigint) ORDER BY variant_id LOOP
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_source,x.variant_id,-x.quantity,'transfer:'||tid::text||':'||x.variant_id::text||':out','warehouse transfer',iam.current_user_id()) RETURNING movement_id INTO mid_out;
 INSERT INTO inventory.stock_ledger(tenant_id,warehouse_id,variant_id,quantity_delta,adjustment_key,reason,recorded_by)
 VALUES(t,p_destination,x.variant_id,x.quantity,'transfer:'||tid::text||':'||x.variant_id::text||':in','warehouse transfer',iam.current_user_id()) RETURNING movement_id INTO mid_in;
 INSERT INTO inventory.transfer_lines(tenant_id,transfer_id,variant_id,source_warehouse_id,destination_warehouse_id,quantity,outgoing_movement_id,incoming_movement_id)
 VALUES(t,tid,x.variant_id,p_source,p_destination,x.quantity,mid_out,mid_in);
 END LOOP;
 RETURN tid;
END $$;
ALTER FUNCTION inventory.transfer_stock(text,uuid,uuid,text,jsonb) OWNER TO upc_inventory_executor;
REVOKE ALL ON FUNCTION inventory.transfer_stock(text,uuid,uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION inventory.transfer_stock(text,uuid,uuid,text,jsonb) TO upc_runtime;
COMMIT;

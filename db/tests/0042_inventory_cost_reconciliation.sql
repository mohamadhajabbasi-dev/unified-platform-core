\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_inv_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_inv_a,upc_inv_b,upc_inv_reader;
GRANT upc_checkout_offline TO upc_inv_a,upc_inv_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('90000000-0000-0000-0000-000000000001','inv-a','Synthetic A'),
 ('90000000-0000-0000-0000-000000000002','inv-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('91000000-0000-0000-0000-000000000001','test','inv-a'),
 ('91000000-0000-0000-0000-000000000002','test','inv-b'),
 ('91000000-0000-0000-0000-000000000003','test','inv-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001'),
 ('90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002'),
 ('90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_inv_a','90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001'),
 ('upc_inv_b','90000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002'),
 ('upc_inv_reader','90000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('90000000-0000-0000-0000-000000000001','inventory-editor'),
 ('90000000-0000-0000-0000-000000000002','inventory-editor'),
 ('90000000-0000-0000-0000-000000000001','inventory-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND p.permission_key LIKE 'inventory.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'inventory.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='91000000-0000-0000-0000-000000000003' AND r.role_key='inventory-reader')
 OR (m.user_id<>'91000000-0000-0000-0000-000000000003' AND r.role_key='inventory-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='inventory';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','A','physical'),
 ('90000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','B','physical'),
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000003','Digital','digital');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000001','stock-a','A'),
 ('90000000-0000-0000-0000-000000000002','93000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000002','stock-b','B'),
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000003','92000000-0000-0000-0000-000000000003','digital-a','Digital');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','main','A'),
 ('90000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000002','main','B');

GRANT upc_payment_recorder TO upc_inv_a;
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='inventory-editor' AND (p.permission_key LIKE 'sales.%' OR p.permission_key IN ('crm.read','catalog.read'));
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'sales.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic sales test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key IN ('sales','crm','catalog');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('90000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('90000000-0000-0000-0000-000000000002','95000000-0000-0000-0000-000000000002','Synthetic customer B');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('90000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-000000000004','No stock','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000004','92000000-0000-0000-0000-000000000004','no-stock','No stock');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('90000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','original','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT '90000000-0000-0000-0000-000000000001',v.variant_id,'96000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='90000000-0000-0000-0000-000000000001';

INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'procurement.%';
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'procurement.read' FROM iam.roles WHERE role_key='inventory-reader';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic procurement'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='procurement';
GRANT upc_supplier_document_verifier,upc_supplier_payment_verifier TO upc_inv_a;
INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key LIKE 'finance.%';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'91000000-0000-0000-0000-000000000001','Synthetic finance'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('inv-a','inv-b') AND m.module_key='finance';
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000003','second','Second warehouse');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; w2 uuid:='94000000-0000-0000-0000-000000000003';
 v uuid:='93000000-0000-0000-0000-000000000001'; c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); expense uuid:=gen_random_uuid(); other_asset uuid:=gen_random_uuid();
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 s uuid; po1 uuid; po2 uuid; oid uuid; oid2 uuid; oid3 uuid; mid uuid; mid2 uuid; mid3 uuid; tid uuid; tid2 uuid; n bigint; a record; b record; eid uuid; rev uuid;
BEGIN
 PERFORM finance.configure_valuation_preview(v,'fifo','IRR');
 s:=procurement.register_counterparty('fifo-transfer-supplier',NULL,'Synthetic');
 po1:=procurement.issue_purchase('fifo-transfer-1',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po1,'fifo-transfer-r1','delivery');
 po2:=procurement.issue_purchase('fifo-transfer-2',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',120)));
 PERFORM procurement.receive_purchase(po2,'fifo-transfer-r2','delivery');
 IF (SELECT count(*) FROM finance.inventory_cost_issues(w,v) WHERE issue_code='purchase_invoice_missing')<>2
 OR (SELECT count(*) FROM finance.inventory_cost_issues(w,v) WHERE issue_code='cost_not_captured')<>2
 THEN RAISE EXCEPTION 'FAIL missing invoice and cost issues'; END IF;
 BEGIN PERFORM finance.assert_inventory_cost_ready(w,v); RAISE EXCEPTION 'FAIL incomplete scope ready'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR'),(t,expense,'cogs','COGS','expense','IRR'),(t,other_asset,'other-asset','Other asset','asset','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 PERFORM finance.record_supplier_invoice(po1,'FIFO-1',d,d+7,1000,'IRR',digest,asset,ap);
 PERFORM finance.record_supplier_invoice(po2,'FIFO-2',d,d+7,1200,'IRR',digest,asset,ap);
 oid:=sales.create_checkout('fifo-transfer-sale',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',4,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','fifo-transfer-payment',4000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 n:=finance.capture_movement_costs(w,v);
 IF n IS DISTINCT FROM 3 THEN RAISE EXCEPTION 'FAIL initial FIFO capture'; END IF;
 SELECT movement_id INTO STRICT mid FROM finance.movement_cost_facts WHERE quantity_delta=-4;
 IF (SELECT count(*) FROM finance.inventory_cost_issues(w,v) WHERE issue_code='sale_cogs_missing' AND movement_id=mid)<>1
 THEN RAISE EXCEPTION 'FAIL unposted sale issue'; END IF;
 BEGIN PERFORM finance.assert_inventory_cost_ready(w,v); RAISE EXCEPTION 'FAIL unposted sale ready'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM finance.post_fifo_cogs(mid,asset,expense);
 PERFORM finance.assert_inventory_cost_ready(w,v);
 PERFORM finance.assert_inventory_cost_ready(w2,v);
 tid:=inventory.transfer_stock('fifo-transfer',w,w2,'Synthetic transfer',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',8)));
 IF (SELECT count(*) FROM finance.inventory_cost_issues(w,v) WHERE issue_code='transfer_cost_unpaired')<>1
 OR (SELECT count(*) FROM finance.inventory_cost_issues(w2,v) WHERE issue_code='transfer_cost_unpaired')<>1
 THEN RAISE EXCEPTION 'FAIL unpaired transfer issues'; END IF;
 BEGIN PERFORM finance.assert_inventory_cost_ready(w2,v); RAISE EXCEPTION 'FAIL unpaired destination ready'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL isolated FIFO transfer'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.capture_movement_costs(w2,v); RAISE EXCEPTION 'FAIL FIFO source missing'; EXCEPTION WHEN check_violation THEN NULL; END;
 n:=finance.capture_transfer_costs(tid,v);
 IF n IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'FAIL FIFO paired capture: %',n; END IF;
 n:=finance.capture_transfer_costs(tid,v);
 IF n IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL FIFO paired retry'; END IF;
 PERFORM finance.assert_inventory_cost_ready(w,v);
 PERFORM finance.assert_inventory_cost_ready(w2,v);
 IF NOT EXISTS(SELECT 1 FROM inventory.transfer_lines tl JOIN finance.movement_cost_facts fo ON fo.tenant_id=tl.tenant_id AND fo.movement_id=tl.outgoing_movement_id
 JOIN finance.movement_cost_facts fi ON fi.tenant_id=tl.tenant_id AND fi.movement_id=tl.incoming_movement_id WHERE tl.transfer_id=tid AND fo.value_delta=-840 AND fi.value_delta=840)
 THEN RAISE EXCEPTION 'FAIL FIFO transfer amount'; END IF;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(w2,v);
 IF a.on_hand<>8 OR a.remaining_value<>960 OR a.consumed_cost<>400 OR b.on_hand<>8 OR b.remaining_value<>840 OR b.consumed_cost<>0
 THEN RAISE EXCEPTION 'FAIL FIFO warehouse conservation'; END IF;
 tid2:=inventory.transfer_stock('fifo-transfer-back',w2,w,'Synthetic reverse transfer',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1)));
 n:=finance.capture_transfer_costs(tid2,v);
 IF n IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'FAIL FIFO roundtrip'; END IF;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(w2,v);
 IF a.on_hand<>9 OR a.remaining_value<>1060 OR b.on_hand<>7 OR b.remaining_value<>740
 OR (SELECT count(*) FROM finance.journal_entries)<>3 THEN RAISE EXCEPTION 'FAIL roundtrip value or spurious journal'; END IF;
 oid2:=sales.create_checkout('fifo-destination-sale',c,w2,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',7,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid2,'synthetic','acct','fifo-destination-payment',7000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid2);
 n:=finance.capture_movement_costs(w2,v);
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL FIFO destination capture'; END IF;
 SELECT movement_id INTO STRICT mid2 FROM finance.movement_cost_facts WHERE quantity_delta=-7;
 IF (SELECT count(*) FROM finance.fifo_cost_allocations WHERE outgoing_movement_id=mid2)<>2
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id WHERE fa.outgoing_movement_id=mid2 AND fa.warehouse_id=w2 AND rb.warehouse_id=w AND rb.purchase_id=po1 AND fa.quantity=5 AND fa.cost=500)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id WHERE fa.outgoing_movement_id=mid2 AND fa.warehouse_id=w2 AND rb.warehouse_id=w AND rb.purchase_id=po2 AND fa.quantity=2 AND fa.cost=240)
 THEN RAISE EXCEPTION 'FAIL original cross-warehouse receipt provenance'; END IF;
 BEGIN PERFORM finance.post_fifo_cogs(mid2,other_asset,expense); RAISE EXCEPTION 'FAIL FIFO remote asset bypass'; EXCEPTION WHEN check_violation THEN NULL; END;
 eid:=finance.post_fifo_cogs(mid2,asset,expense);
 IF finance.post_fifo_cogs(mid2,asset,expense)<>eid OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>1060 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=expense)<>1140 THEN RAISE EXCEPTION 'FAIL FIFO destination journal'; END IF;
 PERFORM sales.receive_full_return(oid2,'fifo-transfer-return','Inspected sellable');
 IF (SELECT count(*) FROM finance.inventory_cost_issues(w2,v) WHERE issue_code='return_reversal_missing')<>1
 OR (SELECT count(*) FROM finance.inventory_cost_issues(w2,v) WHERE issue_code='cost_not_captured')<>1
 THEN RAISE EXCEPTION 'FAIL missing return reversal'; END IF;
 BEGIN PERFORM finance.assert_inventory_cost_ready(w2,v); RAISE EXCEPTION 'FAIL unreversed return ready'; EXCEPTION WHEN check_violation THEN NULL; END;
 rev:=finance.reverse_fifo_cogs(mid2);
 IF EXISTS(SELECT 1 FROM finance.inventory_cost_issues(w2,v) WHERE issue_code='return_reversal_missing')
 OR NOT EXISTS(SELECT 1 FROM finance.inventory_cost_issues(w2,v) WHERE issue_code='cost_not_captured')
 THEN RAISE EXCEPTION 'FAIL reversal without cost readiness'; END IF;
 n:=finance.capture_movement_costs(w2,v);
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL FIFO destination return capture'; END IF;
 PERFORM finance.assert_inventory_cost_ready(w2,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(w2,v);
 IF b.on_hand<>7 OR b.remaining_value<>740 OR b.consumed_cost<>0 THEN RAISE EXCEPTION 'FAIL FIFO destination return value'; END IF;
 oid3:=sales.create_checkout('fifo-destination-resale',c,w2,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',7,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid3,'synthetic','acct','fifo-destination-resale-payment',7000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid3);
 n:=finance.capture_movement_costs(w2,v);
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL FIFO destination resale capture'; END IF;
 SELECT cf.movement_id INTO STRICT mid3 FROM finance.movement_cost_facts cf JOIN inventory.stock_ledger sl ON sl.tenant_id=cf.tenant_id AND sl.movement_id=cf.movement_id
 JOIN sales.order_items si ON si.tenant_id=sl.tenant_id AND si.reservation_id=sl.reservation_id WHERE si.order_id=oid3;
 PERFORM finance.post_fifo_cogs(mid3,asset,expense);
 IF (SELECT sum(value_delta) FROM finance.movement_cost_facts)<>1060
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>1060
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=expense)<>1140
 OR (SELECT count(*) FROM finance.journal_entries)<>6
 THEN RAISE EXCEPTION 'FAIL FIFO roundtrip return resale conservation'; END IF;
 PERFORM finance.assert_inventory_cost_ready(w,v);
 PERFORM finance.assert_inventory_cost_ready(w2,v);

END $$;
RESET SESSION AUTHORIZATION;
-- Privileged synthetic-only fault injection, always rolled back. Runtime cannot mutate these facts.
SAVEPOINT bad_sale_fact;
UPDATE finance.movement_cost_facts SET value_delta=value_delta-1
 WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND quantity_delta=-4;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_cost_issues('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001') WHERE issue_code='sale_journal_mismatch')
 THEN RAISE EXCEPTION 'FAIL sale amount fault undetected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK TO SAVEPOINT bad_sale_fact;
SAVEPOINT bad_fifo;
UPDATE finance.fifo_cost_allocations SET cost=cost+1 WHERE tenant_id='90000000-0000-0000-0000-000000000001'
 AND outgoing_movement_id IN (SELECT movement_id FROM finance.movement_cost_facts WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND quantity_delta=-4);
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_cost_issues('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001') WHERE issue_code='fifo_allocation_replay_mismatch')
 THEN RAISE EXCEPTION 'FAIL FIFO allocation fault undetected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK TO SAVEPOINT bad_fifo;
SAVEPOINT bad_sequence;
UPDATE finance.movement_cost_facts SET sequence_no=sequence_no+100
 WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND quantity_delta=-4;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_cost_issues('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001') WHERE issue_code='cost_replay_mismatch')
 THEN RAISE EXCEPTION 'FAIL sequence fault undetected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK TO SAVEPOINT bad_sequence;
-- A balanced but wrong invoice is still a mismatch. Disable only the immutable-line
-- trigger in a disposable transaction, after draining deferred insert checks.
SET CONSTRAINTS ALL IMMEDIATE;
SAVEPOINT bad_invoice;
ALTER TABLE finance.journal_lines DISABLE TRIGGER posted_lines_immutable;
UPDATE finance.journal_lines SET amount=amount*2
 WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND entry_id IN (
 SELECT entry_id FROM finance.journal_entries WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND supplier_invoice_id IS NOT NULL);
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF (SELECT count(*) FROM finance.inventory_cost_issues('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001') WHERE issue_code='purchase_journal_mismatch')<>2
 THEN RAISE EXCEPTION 'FAIL balanced wrong invoice undetected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK TO SAVEPOINT bad_invoice;
SAVEPOINT bad_return;
ALTER TABLE finance.journal_lines DISABLE TRIGGER posted_lines_immutable;
UPDATE finance.journal_lines SET amount=amount*2
 WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND entry_id IN (
 SELECT entry_id FROM finance.journal_entries WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND cogs_return_movement_id IS NOT NULL);
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM finance.inventory_cost_issues('94000000-0000-0000-0000-000000000003','93000000-0000-0000-0000-000000000001') WHERE issue_code='return_journal_mismatch')
 THEN RAISE EXCEPTION 'FAIL balanced wrong return undetected'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK TO SAVEPOINT bad_return;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 PERFORM finance.assert_inventory_cost_ready('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001');
 PERFORM finance.assert_inventory_cost_ready('94000000-0000-0000-0000-000000000003','93000000-0000-0000-0000-000000000001');
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.assert_inventory_cost_ready('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unauthorized readiness'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.capture_transfer_costs(gen_random_uuid(),'93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unauthorized capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 BEGIN PERFORM finance.assert_inventory_cost_ready('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL cross tenant readiness'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS inventory cost reconciliation: exact replay, allocation and sequence mismatch, balanced incorrect invoice and reversal, restored clean scope

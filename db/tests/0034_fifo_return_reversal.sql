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
-- 0053: rollback-only fixture privilege for simulating a closed posting period.
-- Real close permission and cutoff are tested separately; no migration grants this.
GRANT UPDATE(closed_at,closed_by) ON finance.fiscal_periods TO upc_inv_a;
CREATE POLICY test_closed_period_fixture ON finance.fiscal_periods FOR UPDATE TO upc_inv_a
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; v uuid:='93000000-0000-0000-0000-000000000001';
 c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 s uuid; po uuid; po1 uuid; oid uuid; a record; b record;
 mid uuid; mid2 uuid; eid uuid; period uuid; oid2 uuid; rev uuid; rid uuid; return_mid uuid; captured_count bigint; expense uuid:=gen_random_uuid(); other_asset uuid:=gen_random_uuid();
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
BEGIN
 IF finance.configure_valuation_preview(v,'fifo','IRR')<>v OR finance.configure_valuation_preview(v,'fifo','IRR')<>v THEN RAISE EXCEPTION 'FAIL policy retry'; END IF;
 BEGIN PERFORM finance.configure_valuation_preview(v,'moving_average','IRR'); RAISE EXCEPTION 'FAIL method change'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview(v,'fifo','USD'); RAISE EXCEPTION 'FAIL currency change'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM finance.configure_valuation_preview('93000000-0000-0000-0000-000000000003','fifo','IRR'); RAISE EXCEPTION 'FAIL digital policy'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE finance.valuation_policies SET method='moving_average'; RAISE EXCEPTION 'FAIL direct policy update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 s:=procurement.register_counterparty('valuation-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('valuation-1',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'valuation-r1','delivery'); po1:=po;
 po:=procurement.issue_purchase('valuation-2',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',120)));
 PERFORM procurement.receive_purchase(po,'valuation-r2','delivery');
 oid:=sales.create_checkout('valuation-sale',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',12,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','valuation-payment',12000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.preview_inventory_valuation(w,v,'IRR','moving_average');
 IF a.on_hand<>8 OR a.remaining_value<>960 OR a.consumed_cost<>1240 OR a.all_receipts_invoiced
 OR b.on_hand<>8 OR b.remaining_value<>880 OR b.consumed_cost<>1320 OR b.all_receipts_invoiced
 THEN RAISE EXCEPTION 'FAIL valuation example'; END IF;
 IF EXISTS(SELECT 1 FROM finance.journal_entries) THEN RAISE EXCEPTION 'FAIL preview posted journal'; END IF;
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL unconfirmed cost'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) THEN RAISE EXCEPTION 'FAIL unconfirmed partial capture'; END IF;
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR'),(t,expense,'cogs','COGS','expense','IRR'),(t,other_asset,'other-asset','Other asset','asset','IRR');
 period:=finance.open_period('Synthetic period',d,d+30);
 PERFORM finance.record_supplier_invoice(po1,'COST-1',d,d+7,1000,'IRR',digest,asset,ap);
 PERFORM finance.record_supplier_invoice(po,'COST-2',d,d+7,1200,'IRR',digest,asset,ap);
 IF finance.capture_movement_costs(w,v)<>3 THEN RAISE EXCEPTION 'FAIL initial capture'; END IF;
 IF finance.capture_movement_costs(w,v)<>0 THEN RAISE EXCEPTION 'FAIL retry'; END IF;
 IF (SELECT count(*) FROM finance.fifo_cost_allocations)<>2
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id WHERE rb.purchase_id=po1 AND fa.quantity=10 AND fa.cost=1000)
 OR NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id WHERE rb.purchase_id=po AND fa.quantity=2 AND fa.cost=240)
 THEN RAISE EXCEPTION 'FAIL exact FIFO receipt provenance'; END IF;
 BEGIN DELETE FROM finance.fifo_cost_allocations; RAISE EXCEPTION 'FAIL allocation delete'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE finance.fifo_cost_allocations SET cost=0; RAISE EXCEPTION 'FAIL allocation update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF (SELECT count(*) FROM finance.movement_cost_facts)<>3
 OR (SELECT sum(value_delta) FROM finance.movement_cost_facts)<>960
 OR NOT EXISTS(SELECT 1 FROM finance.movement_cost_facts WHERE quantity_delta=-12 AND value_delta=-1240)
 OR (SELECT count(*) FROM finance.journal_entries)<>2 THEN RAISE EXCEPTION 'FAIL immutable cost facts or duplicate posting'; END IF;
 BEGIN UPDATE finance.movement_cost_facts SET value_delta=1; RAISE EXCEPTION 'FAIL direct update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM finance.movement_cost_facts; RAISE EXCEPTION 'FAIL direct delete'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.preview_inventory_valuation(w,v,'USD','fifo'); RAISE EXCEPTION 'FAIL wrong currency'; EXCEPTION WHEN check_violation THEN NULL; END;
 SELECT movement_id INTO STRICT mid FROM finance.movement_cost_facts WHERE quantity_delta=-12;
 BEGIN PERFORM finance.post_fifo_cogs(mid,other_asset,expense); RAISE EXCEPTION 'FAIL wrong inventory account'; EXCEPTION WHEN check_violation THEN NULL; END;
 eid:=finance.post_fifo_cogs(mid,asset,expense);
 IF finance.post_fifo_cogs(mid,asset,expense)<>eid OR (SELECT count(*) FROM finance.journal_entries)<>3
 OR NOT EXISTS(SELECT 1 FROM finance.journal_entries WHERE entry_id=eid AND cogs_movement_id=mid)
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>960
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=expense)<>1240
 THEN RAISE EXCEPTION 'FAIL COGS journal'; END IF;
 BEGIN PERFORM finance.reverse_fifo_cogs(mid); RAISE EXCEPTION 'FAIL reverse before return'; EXCEPTION WHEN check_violation THEN NULL; END;
 oid2:=sales.create_checkout('valuation-sale-2',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid2,'synthetic','acct','valuation-payment-2',1000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid2);
 IF finance.capture_movement_costs(w,v)<>1 THEN RAISE EXCEPTION 'FAIL second capture'; END IF;
 SELECT movement_id INTO STRICT mid2 FROM finance.movement_cost_facts WHERE quantity_delta=-1;
 PERFORM finance.post_fifo_cogs(mid2,asset,expense);
 rid:=sales.receive_full_return(oid,'valuation-return','All units inspected and sellable');
 SELECT l.movement_id INTO STRICT return_mid FROM inventory.stock_ledger l JOIN sales.order_items i ON i.tenant_id=l.tenant_id
 AND l.adjustment_key='sales-return:'||rid::text||':'||i.item_id::text WHERE i.order_id=oid;
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL capture before return reversal'; EXCEPTION WHEN check_violation THEN NULL; END;
 rev:=finance.reverse_fifo_cogs(mid);
 IF finance.reverse_fifo_cogs(mid)<>rev OR (SELECT count(*) FROM finance.journal_entries)<>5
 OR NOT EXISTS(SELECT 1 FROM finance.journal_entries WHERE entry_id=rev AND cogs_return_movement_id=return_mid)
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>2080
 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=expense)<>120
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger WHERE variant_id=v)<>19
 THEN RAISE EXCEPTION 'FAIL historical return reversal and conservation'; END IF;
 -- Separate write, exact retry and read into separate statements (fresh command snapshots).
 captured_count:=finance.capture_movement_costs(w,v);
 IF captured_count IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL confirmed return capture count: %',captured_count; END IF;
 captured_count:=finance.capture_movement_costs(w,v);
 IF captured_count IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL confirmed return retry count: %',captured_count; END IF;
 IF NOT EXISTS(SELECT 1 FROM finance.movement_cost_facts WHERE movement_id=return_mid AND quantity_delta=12 AND value_delta=1240)
 THEN RAISE EXCEPTION 'FAIL confirmed return cost fact'; END IF;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 IF a.on_hand<>19 OR a.remaining_value<>2080 OR a.consumed_cost<>120 THEN RAISE EXCEPTION 'FAIL restored value'; END IF;
 BEGIN PERFORM finance.close_period(period); RAISE EXCEPTION 'FAIL unsafe actual period close'; EXCEPTION WHEN check_violation THEN NULL; END;
 -- Simulate closed state only inside this rolled-back test fixture.
 UPDATE finance.fiscal_periods SET closed_at=clock_timestamp(),closed_by=iam.current_user_id()
 WHERE period_id=period;
 PERFORM sales.receive_full_return(oid2,'valuation-return-2','All units inspected and sellable');
 BEGIN PERFORM finance.reverse_fifo_cogs(mid2); RAISE EXCEPTION 'FAIL closed period reversal'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.capture_movement_costs(w,v); RAISE EXCEPTION 'FAIL unreversed return capture'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF finance.reverse_fifo_cogs(mid)<>rev OR (SELECT count(*) FROM finance.journal_entries)<>5
 THEN RAISE EXCEPTION 'FAIL closed-period reversal retry/rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.valuation_policies) OR EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) THEN RAISE EXCEPTION 'FAIL policy visibility'; END IF;
 BEGIN PERFORM finance.configure_valuation_preview('93000000-0000-0000-0000-000000000001','fifo','IRR'); RAISE EXCEPTION 'FAIL unauthorized configuration'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.configured_inventory_preview('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001');
 RAISE EXCEPTION 'FAIL missing finance permission'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM finance.valuation_policies) OR EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) THEN RAISE EXCEPTION 'FAIL cross tenant policy visibility'; END IF;
 BEGIN PERFORM finance.configured_inventory_preview('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001');
 RAISE EXCEPTION 'FAIL cross tenant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS explicit full sellable FIFO return reversal, original accounts and amount, exact retry, closed period and fail-closed unreversed return

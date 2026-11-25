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
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('90000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000004','third','Third warehouse');
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; w2 uuid:='94000000-0000-0000-0000-000000000003'; w3 uuid:='94000000-0000-0000-0000-000000000004';
 v uuid; method text; c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid(); expense uuid:=gen_random_uuid();
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 s uuid; po uuid; tid1 uuid; tid2 uuid; tid3 uuid; oid uuid; mid uuid; n bigint;
 exp_a numeric; exp_b numeric; exp_c numeric; exp_sale numeric; exp_transfer numeric; exp_total numeric:=0; a record; b record; cc record;
BEGIN
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR'),(t,expense,'cogs','COGS','expense','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 s:=procurement.register_counterparty('chain-supplier',NULL,'Synthetic');
 FOREACH method IN ARRAY ARRAY['fifo','moving_average'] LOOP
 v:=CASE WHEN method='fifo' THEN '93000000-0000-0000-0000-000000000001'::uuid ELSE '93000000-0000-0000-0000-000000000004'::uuid END;
 PERFORM finance.configure_valuation_preview(v,method,'IRR');
 po:=procurement.issue_purchase('chain-1-'||method,s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',100)));
 PERFORM procurement.receive_purchase(po,'chain-r1-'||method,'delivery');
 PERFORM finance.record_supplier_invoice(po,'CHAIN-1-'||method,d,d+7,1000,'IRR',digest,asset,ap);
 po:=procurement.issue_purchase('chain-2-'||method,s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'unit_cost',120)));
 PERFORM procurement.receive_purchase(po,'chain-r2-'||method,'delivery');
 PERFORM finance.record_supplier_invoice(po,'CHAIN-2-'||method,d,d+7,1200,'IRR',digest,asset,ap);
 tid1:=inventory.transfer_stock('chain-ab-'||method,w,w2,'A to B',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',12)));
 tid2:=inventory.transfer_stock('chain-bc-'||method,w2,w3,'B to C',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5)));
 tid3:=inventory.transfer_stock('chain-ca-'||method,w3,w,'C to A',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',2)));
 po:=procurement.issue_purchase('chain-3-'||method,s,w3,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',1,'unit_cost',150)));
 PERFORM procurement.receive_purchase(po,'chain-r3-'||method,'delivery');
 BEGIN PERFORM finance.capture_transfer_costs(tid2,v); RAISE EXCEPTION 'FAIL unconfirmed final receipt accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts cf WHERE cf.variant_id=v)
 OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa WHERE fa.variant_id=v)
 THEN RAISE EXCEPTION 'FAIL partial chain committed'; END IF;
 PERFORM finance.record_supplier_invoice(po,'CHAIN-3-'||method,d,d+7,150,'IRR',digest,asset,ap);
 n:=finance.capture_transfer_costs(tid2,v);
 IF n IS DISTINCT FROM 9 THEN RAISE EXCEPTION 'FAIL chain capture count % for %',n,method; END IF;
 n:=finance.capture_transfer_costs(tid1,v);
 IF n IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL chain retry'; END IF;
 n:=finance.capture_transfer_costs(tid3,v);
 IF n IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL chain reverse retry'; END IF;
 exp_a:=CASE WHEN method='fifo' THEN 1160 ELSE 1100 END;
 exp_b:=CASE WHEN method='fifo' THEN 740 ELSE 770 END;
 exp_c:=CASE WHEN method='fifo' THEN 450 ELSE 480 END;
 exp_transfer:=CASE WHEN method='fifo' THEN 1240 ELSE 1320 END;
 exp_sale:=CASE WHEN method='fifo' THEN 300 ELSE 360 END;
 SELECT * INTO a FROM finance.configured_inventory_preview(w,v);
 SELECT * INTO b FROM finance.configured_inventory_preview(w2,v);
 SELECT * INTO cc FROM finance.configured_inventory_preview(w3,v);
 IF a.on_hand<>10 OR a.remaining_value<>exp_a OR a.consumed_cost<>0 OR b.on_hand<>7 OR b.remaining_value<>exp_b OR b.consumed_cost<>0
 OR cc.on_hand<>4 OR cc.remaining_value<>exp_c OR cc.consumed_cost<>0
 OR (SELECT sum(cf.value_delta) FROM finance.movement_cost_facts cf WHERE cf.variant_id=v)<>2350
 THEN RAISE EXCEPTION 'FAIL chain quantity/value conservation for %',method; END IF;
 IF NOT EXISTS(SELECT 1 FROM inventory.transfer_lines tr JOIN finance.movement_cost_facts fo ON fo.tenant_id=tr.tenant_id AND fo.movement_id=tr.outgoing_movement_id
 JOIN finance.movement_cost_facts fi ON fi.tenant_id=tr.tenant_id AND fi.movement_id=tr.incoming_movement_id
 WHERE tr.transfer_id=tid1 AND fo.value_delta=-exp_transfer AND fi.value_delta=exp_transfer)
 THEN RAISE EXCEPTION 'FAIL first transfer amount'; END IF;
 PERFORM finance.assert_inventory_cost_ready(w,v);
 PERFORM finance.assert_inventory_cost_ready(w2,v);
 PERFORM finance.assert_inventory_cost_ready(w3,v);
 oid:=sales.create_checkout('chain-sale-'||method,c,w3,pl,'in_person',clock_timestamp()+interval '1 hour',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','chain-pay-'||method,3000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 n:=finance.capture_movement_costs(w3,v);
 IF n IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL chain destination sale capture'; END IF;
 SELECT cf.movement_id INTO STRICT mid FROM finance.movement_cost_facts cf JOIN inventory.stock_ledger sl ON sl.tenant_id=cf.tenant_id AND sl.movement_id=cf.movement_id
 JOIN sales.order_items si ON si.tenant_id=sl.tenant_id AND si.reservation_id=sl.reservation_id WHERE si.order_id=oid AND cf.value_delta=-exp_sale;
 PERFORM finance.post_inventory_cogs(mid,asset,expense,method);
 IF method='fifo' THEN
 IF NOT EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa JOIN finance.receipt_cost_basis rb ON rb.tenant_id=fa.tenant_id AND rb.movement_id=fa.receipt_movement_id
 WHERE fa.outgoing_movement_id=mid AND fa.quantity=3 AND fa.cost=300 AND rb.warehouse_id=w)
 THEN RAISE EXCEPTION 'FAIL multi-hop original receipt'; END IF;
 ELSIF EXISTS(SELECT 1 FROM finance.fifo_cost_allocations fa WHERE fa.variant_id=v)
 THEN RAISE EXCEPTION 'FAIL fictitious average FIFO allocations'; END IF;
 exp_total:=exp_total+2350-exp_sale;
 IF (SELECT net_debit FROM finance.trial_balance WHERE account_id=asset)<>exp_total THEN RAISE EXCEPTION 'FAIL chain accounting conservation'; END IF;
 PERFORM finance.assert_tenant_inventory_cost_ready();
 END LOOP;
 IF exp_total<>4040 OR (SELECT net_debit FROM finance.trial_balance WHERE account_id=expense)<>660 OR (SELECT count(*) FROM finance.journal_entries)<>8
 THEN RAISE EXCEPTION 'FAIL combined chain accounting'; END IF;
 BEGIN PERFORM finance.capture_movement_cost_prefix(w,v,NULL); RAISE EXCEPTION 'FAIL prefix writer accessible'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.replay_valuation_prefix(w,v,'IRR','moving_average',gen_random_uuid()); RAISE EXCEPTION 'FAIL invalid replay cutoff'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.capture_transfer_costs(gen_random_uuid(),'93000000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unauthorized capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS chronological FIFO and moving-average connected transfer chains, atomic rollback, remote sale lineage and tenant conservation

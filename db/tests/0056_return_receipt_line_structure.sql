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
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('90000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000005','92000000-0000-0000-0000-000000000004','ordinary-capacity','Ordinary capacity');
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
DECLARE w uuid:='94000000-0000-0000-0000-000000000001'; dst uuid:='94000000-0000-0000-0000-000000000003';
 v uuid:='93000000-0000-0000-0000-000000000001'; sv uuid:='93000000-0000-0000-0000-000000000004';
 c uuid:='95000000-0000-0000-0000-000000000001'; pl uuid:='96000000-0000-0000-0000-000000000001';
 t uuid:=iam.current_tenant_id(); asset uuid:=gen_random_uuid(); ap uuid:=gen_random_uuid();
 d date:=(clock_timestamp() AT TIME ZONE 'UTC')::date; digest bytea:=decode(repeat('ab',32),'hex');
 l1 uuid; l2 uuid; s1 uuid; s2 uuid; supplier uuid; po uuid; rid uuid; tid uuid; oid uuid; ret uuid; inv uuid;
 alloc jsonb; mid uuid; x record;
BEGIN
 PERFORM inventory.configure_tracking(v,'lot',true);
 PERFORM inventory.configure_tracking(sv,'serial',false);
 l1:=inventory.register_lot(v,'L1',d-1,d+10); l2:=inventory.register_lot(v,'L2',d-2,d+20);
 s1:=inventory.register_serial(sv,'S1'); s2:=inventory.register_serial(sv,'S2');
 supplier:=procurement.register_counterparty('trace-evidence-supplier',NULL,'Synthetic');
 po:=procurement.issue_purchase('trace-evidence-po',supplier,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5,'unit_cost',100),jsonb_build_object('variant_id',sv,'quantity',2,'unit_cost',200)));
 alloc:=jsonb_build_array(jsonb_build_object('variant_id',v,'lot_id',l1,'quantity',2),jsonb_build_object('variant_id',v,'lot_id',l2,'quantity',3),
 jsonb_build_object('variant_id',sv,'serial_id',s1,'quantity',1),jsonb_build_object('variant_id',sv,'serial_id',s2,'quantity',1));
 rid:=procurement.receive_purchase_allocated(po,'trace-evidence-receipt','Synthetic',alloc);
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.evidence_kind='receipt' AND e.receipt_id=rid AND e.invoice_id IS NULL)<>4
 OR (SELECT sum(e.receipt_agreed_cost) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e)<>900
 THEN RAISE EXCEPTION 'FAIL split receipt evidence'; END IF;
 INSERT INTO finance.accounts(tenant_id,account_id,account_code,name,account_type,currency) VALUES
 (t,asset,'inventory','Inventory','asset','IRR'),(t,ap,'payable','Payable','liability','IRR');
 PERFORM finance.open_period('Synthetic period',d,d+30);
 PERFORM finance.record_supplier_invoice(po,'TRACE-EVIDENCE',d,d+7,900,'IRR',digest,asset,ap);
 SELECT invoice_id INTO STRICT inv FROM finance.supplier_invoices WHERE purchase_id=po;
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.invoice_id=inv AND e.receipt_currency='IRR')<>4
 OR (SELECT count(*) FROM finance.journal_entries)<>1
 THEN RAISE EXCEPTION 'FAIL invoice evidence'; END IF;
 tid:=inventory.transfer_allocated('trace-evidence-transfer',w,dst,'Synthetic',alloc);
 IF (SELECT count(*) FROM inventory.transfer_lines WHERE transfer_id=tid)<>4
 OR (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.transfer_id=tid AND e.evidence_kind IN ('transfer_in','transfer_out') AND e.related_movement_id IS NOT NULL)<>8
 THEN RAISE EXCEPTION 'FAIL multiline transfer evidence'; END IF;
 oid:=sales.create_checkout('trace-evidence-sale',c,dst,pl,'in_person',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',3,'expected_unit_price',1000),jsonb_build_object('variant_id',sv,'quantity',2,'expected_unit_price',1000)));
 PERFORM sales.record_capture(oid,'synthetic','acct','trace-evidence-payment',5000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.order_id=oid AND e.evidence_kind='sale' AND e.allocation_id IS NOT NULL)<>4
 OR NOT EXISTS(SELECT 1 FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.order_id=oid AND e.lot_id=l1 AND e.quantity_delta=-2)
 THEN RAISE EXCEPTION 'FAIL sale allocation evidence'; END IF;
 SELECT jsonb_agg(jsonb_build_object('variant_id',a.variant_id,'lot_id',a.lot_id,'serial_id',a.serial_id,'quantity',a.quantity)) INTO alloc
 FROM sales.order_items i JOIN inventory.reservation_allocations a USING(tenant_id,reservation_id) WHERE i.order_id=oid;
 IF (SELECT count(*) FROM finance.order_return_capacity(oid))<>4
 OR (SELECT sum(remaining_quantity) FROM finance.order_return_capacity(oid))<>5
 OR EXISTS(SELECT 1 FROM finance.order_return_capacity(oid) e WHERE e.returned_quantity<>0 OR e.return_id IS NOT NULL OR e.return_movement_id IS NOT NULL OR e.allocation_id IS NULL)
 THEN RAISE EXCEPTION 'FAIL traced unreturned capacity'; END IF;
 ret:=sales.receive_full_return_allocated(oid,'trace-evidence-return','Inspected sellable',alloc);
 IF (SELECT count(*) FROM finance.order_return_capacity(oid))<>4
 OR (SELECT sum(returned_quantity) FROM finance.order_return_capacity(oid))<>5
 OR EXISTS(SELECT 1 FROM finance.order_return_capacity(oid) e WHERE e.remaining_quantity<>0 OR e.return_id IS DISTINCT FROM ret OR e.return_movement_id IS NULL)
 THEN RAISE EXCEPTION 'FAIL traced full return capacity'; END IF;
 IF (SELECT count(*) FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.return_id=ret AND e.evidence_kind='return' AND e.order_id=oid AND e.related_movement_id IS NOT NULL AND e.allocation_id IS NOT NULL)<>4
 THEN RAISE EXCEPTION 'FAIL exact return evidence'; END IF;
 FOR x IN SELECT e.* FROM inventory.stock_ledger l CROSS JOIN LATERAL finance.tracked_movement_evidence(l.movement_id) e WHERE e.return_id=ret LOOP
 IF NOT EXISTS(SELECT 1 FROM finance.tracked_movement_evidence(x.related_movement_id) orig WHERE orig.evidence_kind='sale' AND orig.allocation_id=x.allocation_id AND orig.lot_id IS NOT DISTINCT FROM x.lot_id AND orig.serial_id IS NOT DISTINCT FROM x.serial_id AND orig.quantity_delta=-x.quantity_delta)
 THEN RAISE EXCEPTION 'FAIL exact original return match'; END IF;
 END LOOP;
 mid:=inventory.adjust_traced(dst,v,l2,NULL,1,'unsupported-evidence','Synthetic adjustment');
 BEGIN PERFORM finance.tracked_movement_evidence(mid); RAISE EXCEPTION 'FAIL unsupported evidence accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM finance.tracked_movement_evidence(gen_random_uuid()); RAISE EXCEPTION 'FAIL missing movement accepted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 -- Independent ordinary variant in the same synthetic order domain.
 PERFORM inventory.adjust_stock(w,'93000000-0000-0000-0000-000000000005',4,'capacity-ordinary-receipt','Synthetic ordinary receipt');
 oid:=sales.create_checkout('capacity-ordinary-order',c,w,pl,'in_person',clock_timestamp()+interval '1 hour',
 jsonb_build_array(jsonb_build_object('variant_id','93000000-0000-0000-0000-000000000005','quantity',2,'expected_unit_price',1000)));
 BEGIN PERFORM finance.order_return_capacity(oid); RAISE EXCEPTION 'FAIL pending order accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM sales.record_capture(oid,'synthetic','acct','capacity-ordinary-payment',2000,'IRR',clock_timestamp());
 PERFORM sales.fulfill_order(oid);
 IF (SELECT count(*) FROM finance.order_return_capacity(oid))<>1
 OR NOT EXISTS(SELECT 1 FROM finance.order_return_capacity(oid) e WHERE e.sold_quantity=2 AND e.remaining_quantity=2 AND e.returned_quantity=0 AND e.allocation_id IS NULL)
 THEN RAISE EXCEPTION 'FAIL ordinary capacity'; END IF;
 ret:=sales.receive_full_return(oid,'capacity-ordinary-return','Inspected');
 IF NOT EXISTS(SELECT 1 FROM finance.order_return_capacity(oid) e WHERE e.sold_quantity=2 AND e.remaining_quantity=0 AND e.returned_quantity=2 AND e.return_id=ret AND e.return_movement_id IS NOT NULL)
 THEN RAISE EXCEPTION 'FAIL ordinary returned capacity'; END IF;
 BEGIN PERFORM finance.order_return_capacity(NULL); RAISE EXCEPTION 'FAIL null order'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM finance.order_return_capacity(gen_random_uuid()); RAISE EXCEPTION 'FAIL missing order'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM finance.movement_cost_facts) OR EXISTS(SELECT 1 FROM finance.fifo_cost_allocations) OR (SELECT count(*) FROM finance.journal_entries)<>1
 THEN RAISE EXCEPTION 'FAIL evidence wrote valuation facts'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 BEGIN PERFORM finance.order_return_capacity(gen_random_uuid()); RAISE EXCEPTION 'FAIL unauthorized capacity'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM finance.tracked_movement_evidence(gen_random_uuid()); RAISE EXCEPTION 'FAIL unauthorized evidence'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Use a real foreign movement ID without granting cross-tenant table access.
SELECT movement_id AS foreign_mid FROM inventory.stock_ledger WHERE tenant_id='90000000-0000-0000-0000-000000000001' LIMIT 1 \gset
SELECT order_id AS foreign_order FROM sales.orders WHERE tenant_id='90000000-0000-0000-0000-000000000001' LIMIT 1 \gset
SET SESSION AUTHORIZATION upc_inv_b;
SELECT set_config('upc.test_foreign_order', :'foreign_order',true);
SELECT set_config('upc.test_foreign_mid', :'foreign_mid',true);
DO $$ BEGIN
 BEGIN PERFORM finance.order_return_capacity(current_setting('upc.test_foreign_order')::uuid); RAISE EXCEPTION 'FAIL cross tenant capacity'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM finance.tracked_movement_evidence(current_setting('upc.test_foreign_mid')::uuid); RAISE EXCEPTION 'FAIL cross tenant evidence'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- 0056: legacy writers deliberately do not populate the dormant relation.
-- Use superuser ONLY for rollback-only structural examples; no runtime DML.
DO $$
DECLARE a constant uuid:='90000000-0000-0000-0000-000000000001';
 b constant uuid:='90000000-0000-0000-0000-000000000002';
 h sales.returns%ROWTYPE; h2 sales.returns%ROWTYPE;
 m inventory.stock_ledger%ROWTYPE; m2 inventory.stock_ledger%ROWTYPE;
 other_m inventory.stock_ledger%ROWTYPE; adjust_m inventory.stock_ledger%ROWTYPE;
 role_name text; n bigint; js bigint; qs numeric;
BEGIN
 IF EXISTS(SELECT 1 FROM sales.return_items) THEN RAISE EXCEPTION 'FAIL legacy writer activated dormant relation'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='sales.return_items'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='sales.return_items'::regclass AND tgname='inventory_period_mutation_barrier'
 AND NOT tgisinternal AND tgenabled='O' AND tgfoid='finance.guard_inventory_period_mutation()'::regprocedure)
 THEN RAISE EXCEPTION 'FAIL return line RLS/barrier'; END IF;
 FOR role_name IN SELECT rolname FROM pg_roles WHERE rolname LIKE 'upc_%' LOOP
  IF has_table_privilege(role_name,'sales.return_items','INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER,REFERENCES')
  OR has_any_column_privilege(role_name,'sales.return_items','INSERT,UPDATE,REFERENCES')
  THEN RAISE EXCEPTION 'FAIL dormant return line mutable by %',role_name; END IF;
 END LOOP;
 SELECT * INTO STRICT h FROM sales.returns WHERE tenant_id=a AND request_key='capacity-ordinary-return';
 SELECT * INTO STRICT h2 FROM sales.returns WHERE tenant_id=a AND request_key='trace-evidence-return';
 SELECT l.* INTO STRICT m FROM inventory.stock_ledger l JOIN sales.order_items i USING(tenant_id,reservation_id)
 WHERE i.tenant_id=a AND i.order_id=h.order_id;
 SELECT l.* INTO m2 FROM inventory.stock_ledger l JOIN sales.order_items i USING(tenant_id,reservation_id)
 WHERE i.tenant_id=a AND i.order_id=h2.order_id ORDER BY l.movement_id LIMIT 1;
 IF m2.movement_id IS NULL OR m2.allocation_id IS NULL THEN RAISE EXCEPTION 'FAIL traced fixture'; END IF;
 SELECT l.* INTO other_m FROM inventory.stock_ledger l JOIN sales.order_items i USING(tenant_id,reservation_id)
 WHERE i.tenant_id=a AND i.order_id=h2.order_id AND l.reservation_id<>m2.reservation_id LIMIT 1;
 IF other_m.movement_id IS NULL THEN RAISE EXCEPTION 'FAIL second traced reservation fixture'; END IF;
 SELECT * INTO STRICT adjust_m FROM inventory.stock_ledger WHERE tenant_id=a AND adjustment_key='capacity-ordinary-receipt';
 SELECT count(*),sum(quantity_delta) INTO n,qs FROM inventory.stock_ledger;
 SELECT count(*) INTO js FROM finance.journal_entries;
 INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
 VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,1,'sellable'),
       (a,h2.return_id,h2.order_id,m2.reservation_id,m2.movement_id,1,'sellable');
 -- Actual wrong relationships, rather than nonexistent random-only FKs.
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(b,h.return_id,h.order_id,m.reservation_id,m.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL cross-tenant line'; EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h2.return_id,h.order_id,m.reservation_id,m.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL wrong return header order'; EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m2.reservation_id,m2.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL wrong reservation order'; EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h2.return_id,h2.order_id,m2.reservation_id,other_m.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL wrong original movement reservation'; EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,adjust_m.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL adjustment accepted as sale'; EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,NULL,adjust_m.movement_id,1,'damaged');
  RAISE EXCEPTION 'FAIL null reservation bypass'; EXCEPTION WHEN not_null_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,0,'damaged');
  RAISE EXCEPTION 'FAIL zero receipt'; EXCEPTION WHEN check_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,-1,'damaged');
  RAISE EXCEPTION 'FAIL negative receipt'; EXCEPTION WHEN check_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,1,'unknown');
  RAISE EXCEPTION 'FAIL unknown disposition'; EXCEPTION WHEN check_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,1,'sellable');
  RAISE EXCEPTION 'FAIL duplicate disposition'; EXCEPTION WHEN unique_violation THEN NULL;
 END;
 -- Only test enumerated physical classifications in rolled-back
 -- privileged subtransaction, not a live quantity/disposition policy.
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  VALUES(a,h.return_id,h.order_id,m.reservation_id,m.movement_id,1,'damaged'),
        (a,h2.return_id,h2.order_id,other_m.reservation_id,other_m.movement_id,1,'expired');
  IF (SELECT count(*) FROM sales.return_items WHERE disposition IN ('damaged','expired'))<>2
  THEN RAISE EXCEPTION 'FAIL dormant inspection classifications'; END IF;
  RAISE EXCEPTION USING ERRCODE='Z0056',MESSAGE='Rollback-only classification example';
 EXCEPTION WHEN SQLSTATE 'Z0056' THEN NULL;
 END;
 IF (SELECT count(*) FROM sales.return_items)<>2 OR (SELECT count(*) FROM inventory.stock_ledger)<>n
 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger) IS DISTINCT FROM qs
 OR (SELECT count(*) FROM finance.journal_entries)<>js
 OR EXISTS(SELECT 1 FROM sales.refunds) OR EXISTS(SELECT 1 FROM finance.movement_cost_facts)
 THEN RAISE EXCEPTION 'FAIL structural fixtures changed inventory or finance'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.return_items)<>2 THEN RAISE EXCEPTION 'FAIL authorized return line read'; END IF;
 BEGIN
  INSERT INTO sales.return_items(tenant_id,return_id,order_id,reservation_id,sale_movement_id,received_quantity,disposition)
  SELECT tenant_id,return_id,order_id,reservation_id,sale_movement_id,1,'damaged' FROM sales.return_items LIMIT 1;
  RAISE EXCEPTION 'FAIL runtime insert'; EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN UPDATE sales.return_items SET received_quantity=1; RAISE EXCEPTION 'FAIL runtime update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM sales.return_items; RAISE EXCEPTION 'FAIL runtime delete'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.return_items) THEN RAISE EXCEPTION 'FAIL cross-tenant return line read'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM sales.return_items)<>2 THEN RAISE EXCEPTION 'FAIL sales read-only role'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants g USING iam.roles r
 WHERE g.tenant_id=r.tenant_id AND g.role_id=r.role_id AND r.tenant_id='90000000-0000-0000-0000-000000000001'
 AND r.role_key='inventory-reader' AND g.permission_key='sales.read';
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.return_items) THEN RAISE EXCEPTION 'FAIL missing sales permission'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT '90000000-0000-0000-0000-000000000001',module_id,false,'91000000-0000-0000-0000-000000000001','Synthetic disabled sales'
 FROM platform.modules WHERE module_key='sales';
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM sales.return_items) THEN RAISE EXCEPTION 'FAIL disabled sales module read'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS dormant return line identity, composite FK, RLS/ACL/barrier, legacy compatibility and no inventory/financial changes


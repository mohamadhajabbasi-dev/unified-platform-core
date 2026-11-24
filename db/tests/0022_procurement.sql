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
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); c uuid:='95000000-0000-0000-0000-000000000001'; w uuid:='94000000-0000-0000-0000-000000000001';
 v uuid:='93000000-0000-0000-0000-000000000001'; v2 uuid:='93000000-0000-0000-0000-000000000004';
 s uuid; p uuid; p2 uuid; r uuid; ln jsonb;
BEGIN
 s:=procurement.register_counterparty('supplier-a',c,NULL);
 IF procurement.register_counterparty('supplier-a',c,NULL)<>s OR NOT EXISTS(SELECT 1 FROM procurement.counterparties WHERE counterparty_id=s AND customer_id=c AND standalone_name IS NULL)
 THEN RAISE EXCEPTION 'FAIL canonical linked counterparty'; END IF;
 BEGIN PERFORM procurement.register_counterparty('second-link',c,NULL); RAISE EXCEPTION 'FAIL duplicated customer supplier'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM procurement.register_counterparty('foreign','95000000-0000-0000-0000-000000000002',NULL); RAISE EXCEPTION 'FAIL cross tenant customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 PERFORM procurement.register_counterparty('standalone',NULL,'Synthetic supplier');
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',5,'unit_cost',400),jsonb_build_object('variant_id',v2,'quantity',2,'unit_cost',300));
 p:=procurement.issue_purchase('po-1',s,w,'IRR',ln);
 IF procurement.issue_purchase('po-1',s,w,'IRR',ln)<>p OR EXISTS(SELECT 1 FROM inventory.stock_ledger)
 OR NOT EXISTS(SELECT 1 FROM procurement.purchase_summary WHERE purchase_id=p AND ordered_total=2600 AND state='issued') THEN RAISE EXCEPTION 'FAIL purchase commitment'; END IF;
 BEGIN PERFORM procurement.issue_purchase('po-1',s,w,'USD',ln); RAISE EXCEPTION 'FAIL purchase conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM procurement.issue_purchase('foreign-variant',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id','93000000-0000-0000-0000-000000000002','quantity',1,'unit_cost',10))); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM procurement.issue_purchase('digital',s,w,'IRR',jsonb_build_array(jsonb_build_object('variant_id','93000000-0000-0000-0000-000000000003','quantity',1,'unit_cost',10))); RAISE EXCEPTION 'FAIL digital'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM inventory.adjust_stock(w,v,1,'purchase-receipt:forged','Forbidden'); RAISE EXCEPTION 'FAIL forged movement'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM inventory.post_purchase_movement(w,v,1,'purchase-receipt:forged'); RAISE EXCEPTION 'FAIL internal movement grant'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 p2:=procurement.issue_purchase('po-2',s,w,'IRR',ln);
 PERFORM procurement.cancel_purchase(p2); PERFORM procurement.cancel_purchase(p2);
 BEGIN PERFORM procurement.receive_purchase(p2,'cancelled','delivery-cancelled'); RAISE EXCEPTION 'FAIL receive cancelled'; EXCEPTION WHEN check_violation THEN NULL; END;
 r:=procurement.receive_purchase(p,'receipt-1','delivery-1');
 IF procurement.receive_purchase(p,'receipt-1','delivery-1')<>r OR (SELECT count(*) FROM inventory.stock_ledger)<>2
 OR (SELECT count(*) FROM procurement.receipt_items)<>2 OR (SELECT sum(quantity_delta) FROM inventory.stock_ledger)<>7
 OR NOT EXISTS(SELECT 1 FROM procurement.purchase_summary WHERE purchase_id=p AND state='received') THEN RAISE EXCEPTION 'FAIL exactly once receipt'; END IF;
 BEGIN PERFORM procurement.receive_purchase(p,'receipt-1','different'); RAISE EXCEPTION 'FAIL receipt conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM procurement.receive_purchase(p,'receipt-2','delivery-2'); RAISE EXCEPTION 'FAIL second receipt'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM procurement.cancel_purchase(p); RAISE EXCEPTION 'FAIL cancel received'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE procurement.purchase_items SET unit_cost=1; RAISE EXCEPTION 'FAIL mutable cost'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM procurement.purchase_summary) OR EXISTS(SELECT 1 FROM procurement.counterparties) OR EXISTS(SELECT 1 FROM inventory.stock_ledger) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM procurement.purchase_summary)<>2 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM procurement.register_counterparty('forbidden',NULL,'Forbidden'); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DELETE FROM iam.role_grants WHERE tenant_id='90000000-0000-0000-0000-000000000001' AND permission_key='inventory.receive';
SET SESSION AUTHORIZATION upc_inv_a;
DO $$ BEGIN
 BEGIN PERFORM procurement.receive_purchase((SELECT purchase_id FROM procurement.purchase_orders WHERE request_key='po-1'),'receipt-1','delivery-1'); RAISE EXCEPTION 'FAIL receipt permission revoked'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS procurement: canonical counterparty, immutable cost, no stock until receipt, exact ledger links, idempotency, cancellation, tenant and permission gates

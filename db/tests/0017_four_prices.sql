\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_inv_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_inv_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_inv_a,upc_inv_b,upc_inv_reader;
GRANT upc_checkout_offline TO upc_inv_a;
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
 ('90000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','retail','IRR','Synthetic retail');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 SELECT '90000000-0000-0000-0000-000000000001',v.variant_id,'96000000-0000-0000-0000-000000000001',1000,tstzrange('2020-01-01 00:00+00',NULL,'[)')
 FROM catalog.variants v WHERE v.tenant_id='90000000-0000-0000-0000-000000000001';

INSERT INTO iam.role_grants SELECT tenant_id,role_id,p.permission_key FROM iam.roles CROSS JOIN iam.permissions p
 WHERE role_key='inventory-editor' AND p.permission_key IN ('catalog.price.write','catalog.price.eligibility.write','catalog.price.customer');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'catalog.read' FROM iam.roles WHERE role_key='inventory-reader';
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); v uuid:='93000000-0000-0000-0000-000000000001'; c uuid:='95000000-0000-0000-0000-000000000001';
 l uuid; d uuid; co uuid; wh uuid; wpid uuid;
BEGIN
 PERFORM catalog.initialize_standard_prices('IRR'); PERFORM catalog.initialize_standard_prices('IRR');
 IF (SELECT count(*) FROM catalog.price_lists WHERE list_key IN ('original','discounted','colleague','wholesale'))<>4 THEN RAISE EXCEPTION 'FAIL bootstrap'; END IF;
 SELECT price_list_id INTO l FROM catalog.price_lists WHERE list_key='original';
 SELECT price_list_id INTO d FROM catalog.price_lists WHERE list_key='discounted';
 SELECT price_list_id INTO co FROM catalog.price_lists WHERE list_key='colleague';
 SELECT price_list_id INTO wh FROM catalog.price_lists WHERE list_key='wholesale';
 BEGIN INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES(t,v,d,900,tstzrange('2020-01-01',NULL,'[)')); RAISE EXCEPTION 'FAIL missing original'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES(t,v,l,1000,tstzrange('2020-01-01',NULL,'[)'));
 BEGIN INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES(t,v,d,1100,tstzrange('2020-01-01',NULL,'[)')); RAISE EXCEPTION 'FAIL excessive discount'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES(t,v,d,900,tstzrange('2020-01-01',NULL,'[)')),(t,v,co,850,tstzrange('2020-01-01',NULL,'[)'));
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during,minimum_quantity) VALUES(t,v,wh,800,tstzrange('2020-01-01',NULL,'[)'),5) RETURNING price_id INTO wpid;
 INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(t,wpid,int8range(10,NULL,'[)'),750);
 PERFORM catalog.decide_customer_price(c,'colleague',true,NULL,'Synthetic approval');
 PERFORM catalog.decide_customer_price(c,'wholesale',true,NULL,'Synthetic approval');
 IF (SELECT amount FROM catalog.quote_price(v,c,10,'in_person')) IS DISTINCT FROM 900::numeric THEN RAISE EXCEPTION 'FAIL customer UUID alone'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SELECT price_list_id AS original_id FROM catalog.price_lists WHERE list_key='original' \gset
SELECT price_list_id AS private_id FROM catalog.price_lists WHERE list_key='wholesale' \gset
SET SESSION AUTHORIZATION upc_inv_reader;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.price_lists WHERE list_key IN ('colleague','wholesale')) OR EXISTS(SELECT 1 FROM catalog.price_entries WHERE amount IN (750,800,850))
 OR EXISTS(SELECT 1 FROM catalog.price_quantity_tiers) THEN RAISE EXCEPTION 'FAIL private raw access'; END IF;
 IF (SELECT amount FROM catalog.quote_price('93000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',10,'in_person')) IS DISTINCT FROM 900::numeric THEN RAISE EXCEPTION 'FAIL ordinary quote'; END IF;
END $$;
SELECT count(*)=0 AS no_private FROM catalog.price_for_quantity('93000000-0000-0000-0000-000000000001',:'private_id',10) \gset
\if :no_private
\else
\echo FAIL private function
\quit 1
\endif
RESET SESSION AUTHORIZATION;
GRANT upc_price_customer_verifier TO upc_inv_a;
SET SESSION AUTHORIZATION upc_inv_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); v uuid:='93000000-0000-0000-0000-000000000001'; c uuid:='95000000-0000-0000-0000-000000000001'; w uuid:='94000000-0000-0000-0000-000000000001';
 l uuid; wh uuid; oid uuid; dl timestamptz:=clock_timestamp()+interval '1 hour'; ln jsonb;
BEGIN
 SELECT price_list_id INTO l FROM catalog.price_lists WHERE list_key='original';
 SELECT price_list_id INTO wh FROM catalog.price_lists WHERE list_key='wholesale';
 IF (SELECT amount FROM catalog.quote_price(v,c,1,'in_person')) IS DISTINCT FROM 850::numeric OR
 (SELECT amount FROM catalog.quote_price(v,c,5,'in_person')) IS DISTINCT FROM 800::numeric OR
 (SELECT amount FROM catalog.quote_price(v,c,10,'in_person')) IS DISTINCT FROM 750::numeric THEN RAISE EXCEPTION 'FAIL authorized selection'; END IF;
 PERFORM inventory.adjust_stock(w,v,30,'four-receipt','Synthetic receipt');
 ln:=jsonb_build_array(jsonb_build_object('variant_id',v,'quantity',10,'expected_unit_price',750));
 BEGIN PERFORM sales.create_checkout('forged',c,w,wh,'in_person',dl,ln); RAISE EXCEPTION 'FAIL direct list selection'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 oid:=sales.create_checkout('four-checkout',c,w,l,'in_person',dl,ln);
 IF sales.create_checkout('four-checkout',c,w,l,'in_person',dl,ln)<>oid OR NOT EXISTS(SELECT 1 FROM sales.order_items WHERE order_id=oid AND unit_price=750 AND price_kind_snapshot='wholesale' AND price_tier_id IS NOT NULL AND original_unit_price=1000 AND price_list_id=wh) THEN RAISE EXCEPTION 'FAIL checkout snapshot'; END IF;
 PERFORM catalog.decide_customer_price(c,'wholesale',false,NULL,'Synthetic revoke');
 PERFORM catalog.decide_customer_price(c,'colleague',false,NULL,'Synthetic revoke');
 IF (SELECT amount FROM catalog.quote_price(v,c,10,'in_person')) IS DISTINCT FROM 900::numeric THEN RAISE EXCEPTION 'FAIL revoked eligibility'; END IF;
 BEGIN PERFORM sales.create_checkout('stale',c,w,l,'in_person',dl,ln); RAISE EXCEPTION 'FAIL stale private price'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM sales.order_items WHERE order_id=oid AND unit_price=750) THEN RAISE EXCEPTION 'FAIL historical snapshot'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_inv_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM catalog.quote_price('93000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',10,'in_person')) THEN RAISE EXCEPTION 'FAIL tenant leakage'; END IF; END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS four prices: bootstrap, discount coverage, private RLS, authenticated eligibility, quantity selection, checkout snapshot and revocation

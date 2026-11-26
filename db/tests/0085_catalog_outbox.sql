\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_catbox_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_catbox_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_catbox_a,upc_catbox_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0850000-0000-0000-0000-000000000001','catbox-price-a','Synthetic A'),
 ('a0850000-0000-0000-0000-000000000002','catbox-price-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0850000-0000-0000-0000-000000000001','test','catbox-price-a'),
 ('b0850000-0000-0000-0000-000000000002','test','catbox-price-b');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0850000-0000-0000-0000-000000000001','b0850000-0000-0000-0000-000000000001'),
 ('a0850000-0000-0000-0000-000000000002','b0850000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_catbox_a','a0850000-0000-0000-0000-000000000001','b0850000-0000-0000-0000-000000000001'),
 ('upc_catbox_b','a0850000-0000-0000-0000-000000000002','b0850000-0000-0000-0000-000000000002');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES
 ('a0850000-0000-0000-0000-000000000001','c0850000-0000-0000-0000-000000000001','catbox-price-editor'),
 ('a0850000-0000-0000-0000-000000000002','c0850000-0000-0000-0000-000000000002','catbox-price-editor');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0850000-0000-0000-0000-000000000001','a0850000-0000-0000-0000-000000000002') AND r.role_key='catbox-price-editor' AND (p.permission_key IN ('catalog.read','catalog.write','catalog.price.write','catalog.price.eligibility.write','crm.read') OR p.permission_key LIKE 'inventory.%');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE m.tenant_id IN ('a0850000-0000-0000-0000-000000000001','a0850000-0000-0000-0000-000000000002') AND r.role_key='catbox-price-editor';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0850000-0000-0000-0000-000000000001','Synthetic fixture'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('catbox-price-a','catbox-price-b') AND m.module_key IN ('catalog','inventory','crm');
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0850000-0000-0000-0000-000000000001','d0850000-0000-0000-0000-000000000021','Synthetic customer A'),
 ('a0850000-0000-0000-0000-000000000002','d0850000-0000-0000-0000-000000000022','Synthetic customer B');
CREATE ROLE upc_catbox_denied LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_catbox_denied;
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0850000-0000-0000-0000-000000000003','test','catbox-denied');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0850000-0000-0000-0000-000000000001','b0850000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_catbox_denied','a0850000-0000-0000-0000-000000000001','b0850000-0000-0000-0000-000000000003');
SET SESSION AUTHORIZATION upc_catbox_denied;
DO $$ BEGIN
 BEGIN
  PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000021','wholesale',true,NULL,'Denied');
  RAISE EXCEPTION 'FAIL unauthorized approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM catalog.customer_price_decisions) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0850000-0000-0000-0000-000000000001','d0850000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0850000-0000-0000-0000-000000000002','d0850000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0850000-0000-0000-0000-000000000001','e0850000-0000-0000-0000-000000000001','d0850000-0000-0000-0000-000000000001','outbox-1','Synthetic'),
 ('a0850000-0000-0000-0000-000000000001','e0850000-0000-0000-0000-000000000003','d0850000-0000-0000-0000-000000000001','outbox-3','Synthetic race'),
 ('a0850000-0000-0000-0000-000000000002','e0850000-0000-0000-0000-000000000002','d0850000-0000-0000-0000-000000000002','outbox-1','Synthetic');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('a0850000-0000-0000-0000-000000000001','f0850000-0000-0000-0000-000000000001','original','IRR','Synthetic'),
 ('a0850000-0000-0000-0000-000000000002','f0850000-0000-0000-0000-000000000002','original','IRR','Synthetic');

INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('a0850000-0000-0000-0000-000000000001','f0850000-0000-0000-0000-000000000011','wholesale','IRR','Synthetic wholesale A'),
 ('a0850000-0000-0000-0000-000000000002','f0850000-0000-0000-0000-000000000012','wholesale','IRR','Synthetic wholesale B');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('a0850000-0000-0000-0000-000000000001','c0850000-0000-0000-0000-000000000099','main','Synthetic');
SET SESSION AUTHORIZATION upc_catbox_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); l uuid:='f0850000-0000-0000-0000-000000000001'; v uuid:='e0850000-0000-0000-0000-000000000001'; w uuid:='c0850000-0000-0000-0000-000000000099'; movement uuid; res uuid; wp uuid:='d0850000-0000-0000-0000-000000000011'; expiry timestamptz:=clock_timestamp()+interval '1 hour';
BEGIN
 UPDATE catalog.price_lists SET name=name WHERE price_list_id=l;
 UPDATE catalog.price_lists SET is_active=false WHERE price_list_id=l;
 UPDATE catalog.price_lists SET is_active=false WHERE price_list_id=l;
 UPDATE catalog.price_lists SET is_active=true WHERE price_list_id=l;
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(t,v,l,100,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
 INSERT INTO catalog.price_entries(tenant_id,price_id,variant_id,price_list_id,amount,valid_during,minimum_quantity)
 VALUES(t,wp,v,'f0850000-0000-0000-0000-000000000011',80,tstzrange('2026-01-01 00:00+00',NULL,'[)'),5);
 INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(t,wp,int8range(5,10,'[)'),75);
 BEGIN
  INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(t,wp,int8range(7,12,'[)'),70);
  RAISE EXCEPTION 'FAIL overlapping tier';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(t,wp,int8range(10,15,'[)'),81);
  RAISE EXCEPTION 'FAIL excessive tier';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount) VALUES(t,wp,int8range(10,15,'[)'),70);
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  UPDATE catalog.price_quantity_tiers SET tier_amount=1 WHERE price_id=wp;
  RAISE EXCEPTION 'FAIL forbidden tier update';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount)
  VALUES('a0850000-0000-0000-0000-000000000002','d0850000-0000-0000-0000-000000000012',int8range(5,10,'[)'),70);
  RAISE EXCEPTION 'FAIL cross-tenant tier';
 EXCEPTION WHEN insufficient_privilege OR foreign_key_violation THEN NULL; END;
 PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000021','wholesale',true,NULL,'Synthetic approval');
 PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000021','wholesale',false,NULL,'Synthetic revoke');
 BEGIN
  PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000021','colleague',true,NULL,'Rolled back');
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000022','wholesale',true,NULL,'Foreign customer');
  RAISE EXCEPTION 'FAIL foreign customer decision';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN
  PERFORM catalog.decide_customer_price('d0850000-0000-0000-0000-000000000021','wholesale',false,clock_timestamp()+interval '1 hour','Invalid expiry');
  RAISE EXCEPTION 'FAIL invalid expiry';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.customer_price_decisions(tenant_id,customer_id,audience,approved,decided_by,reason)
   VALUES(t,'d0850000-0000-0000-0000-000000000021','wholesale',true,iam.current_user_id(),'Direct write');
  RAISE EXCEPTION 'FAIL direct decision write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 movement:=inventory.adjust_stock(w,v,10,'catbox-receipt','Synthetic');
 IF inventory.adjust_stock(w,v,10,'catbox-receipt','Synthetic') IS DISTINCT FROM movement THEN RAISE EXCEPTION 'FAIL movement retry'; END IF;
 res:=inventory.reserve_stock(w,v,3,'catbox-reserve',expiry);
 IF inventory.reserve_stock(w,v,3,'catbox-reserve',expiry) IS DISTINCT FROM res THEN RAISE EXCEPTION 'FAIL reservation retry'; END IF;
 IF (SELECT amount FROM catalog.quote_price(v,NULL,1,'in_person')) IS DISTINCT FROM 100::numeric THEN RAISE EXCEPTION 'FAIL initial active quote'; END IF;
 UPDATE catalog.products SET name=name WHERE product_id='d0850000-0000-0000-0000-000000000001';
 UPDATE catalog.variants SET name=name WHERE variant_id=v;
 UPDATE catalog.products SET is_active=false WHERE product_id='d0850000-0000-0000-0000-000000000001';
 IF EXISTS(SELECT 1 FROM catalog.quote_price(v,NULL,1,'in_person')) THEN RAISE EXCEPTION 'FAIL inactive product quote'; END IF;
 UPDATE catalog.products SET is_active=false WHERE product_id='d0850000-0000-0000-0000-000000000001';
 UPDATE catalog.products SET is_active=true WHERE product_id='d0850000-0000-0000-0000-000000000001';
 UPDATE catalog.variants SET is_active=false WHERE variant_id=v;
 IF EXISTS(SELECT 1 FROM catalog.quote_price(v,NULL,1,'in_person')) THEN RAISE EXCEPTION 'FAIL inactive variant quote'; END IF;
 UPDATE catalog.variants SET is_active=false WHERE variant_id=v;
 UPDATE catalog.variants SET is_active=true WHERE variant_id=v;
 IF (SELECT amount FROM catalog.quote_price(v,NULL,1,'in_person')) IS DISTINCT FROM 100::numeric THEN RAISE EXCEPTION 'FAIL restored active quote'; END IF;
 BEGIN
  UPDATE catalog.products SET name='Rollback product' WHERE product_id='d0850000-0000-0000-0000-000000000001';
  UPDATE catalog.variants SET name='Rollback variant' WHERE variant_id=v;
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  INSERT INTO catalog.variants(tenant_id,product_id,sku,name) VALUES(t,'d0850000-0000-0000-0000-000000000001','outbox-1','Duplicate SKU');
  RAISE EXCEPTION 'FAIL duplicate variant';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 UPDATE catalog.products SET name='Forbidden' WHERE product_id='d0850000-0000-0000-0000-000000000002';
 IF FOUND THEN RAISE EXCEPTION 'FAIL foreign product update'; END IF;
 UPDATE catalog.variants SET name='Forbidden' WHERE variant_id='e0850000-0000-0000-0000-000000000002';
 IF FOUND THEN RAISE EXCEPTION 'FAIL foreign variant update'; END IF;
 BEGIN
  UPDATE catalog.price_lists SET name='Rolled back' WHERE price_list_id=l;
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_lists(tenant_id,list_key,currency,name) VALUES(t,'original','IRR','Duplicate');
  RAISE EXCEPTION 'FAIL duplicate list';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM catalog.price_lists WHERE price_list_id='f0850000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL foreign read'; END IF;
 UPDATE catalog.price_lists SET name='Forbidden' WHERE price_list_id='f0850000-0000-0000-0000-000000000002';
 IF FOUND THEN RAISE EXCEPTION 'FAIL foreign update'; END IF;
 BEGIN PERFORM 1 FROM ops.outbox_events; RAISE EXCEPTION 'FAIL direct read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(t,'catalog.price_list.changed'); RAISE EXCEPTION 'FAIL direct insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_catbox_b;
UPDATE catalog.variants SET name='Tenant B variant' WHERE variant_id='e0850000-0000-0000-0000-000000000002';
UPDATE catalog.price_lists SET name='Tenant B' WHERE price_list_id='f0850000-0000-0000-0000-000000000002';
INSERT INTO catalog.price_entries(tenant_id,price_id,variant_id,price_list_id,amount,valid_during,minimum_quantity)
 VALUES(iam.current_tenant_id(),'d0850000-0000-0000-0000-000000000012','e0850000-0000-0000-0000-000000000002','f0850000-0000-0000-0000-000000000012',80,tstzrange('2026-01-01 00:00+00',NULL,'[)'),5);
INSERT INTO catalog.price_quantity_tiers(tenant_id,price_id,quantity_range,tier_amount)
 VALUES(iam.current_tenant_id(),'d0850000-0000-0000-0000-000000000012',int8range(5,10,'[)'),70);
SELECT catalog.decide_customer_price('d0850000-0000-0000-0000-000000000022','colleague',true,NULL,'Synthetic approval B');
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.customer_price_decisions WHERE customer_id='d0850000-0000-0000-0000-000000000021') THEN RAISE EXCEPTION 'FAIL foreign decision read'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
DECLARE a uuid:='a0850000-0000-0000-0000-000000000001'; b uuid:='a0850000-0000-0000-0000-000000000002';
BEGIN
 IF (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.price_list.changed')<>4
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.price_entry.changed')<>2
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='inventory.stock_ledger.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='inventory.reservation.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a)<>18
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.price_list.changed')<>3
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b)<>9
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.price_tier.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.price_tier.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.price_entry.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.price_eligibility.changed')<>2
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.price_eligibility.changed')<>1
 OR (SELECT count(*) FROM catalog.customer_price_decisions WHERE tenant_id=a)<>2
 OR (SELECT approved FROM catalog.customer_price_decisions WHERE tenant_id=a ORDER BY decision_id DESC LIMIT 1) IS DISTINCT FROM false
 OR (SELECT count(*) FROM catalog.customer_price_decisions WHERE tenant_id=b)<>1
 OR has_table_privilege('upc_outbox_capture','catalog.customer_price_decisions','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_runtime','catalog.customer_price_decisions','INSERT,UPDATE,DELETE')
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.product.changed')<>3
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=a AND event_kind='catalog.variant.changed')<>4
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.product.changed')<>1
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id=b AND event_kind='catalog.variant.changed')<>2
 OR NOT EXISTS(SELECT 1 FROM catalog.products WHERE tenant_id=a AND product_id='d0850000-0000-0000-0000-000000000001' AND name='Synthetic A' AND is_active)
 OR NOT EXISTS(SELECT 1 FROM catalog.variants WHERE tenant_id=a AND variant_id='e0850000-0000-0000-0000-000000000001' AND name='Synthetic' AND is_active)
 OR has_table_privilege('upc_outbox_capture','catalog.products','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_outbox_capture','catalog.variants','SELECT,INSERT,UPDATE,DELETE')
 OR (SELECT count(*) FROM catalog.price_quantity_tiers WHERE tenant_id=a)<>1
 OR NOT EXISTS(SELECT 1 FROM catalog.price_lists WHERE tenant_id=a AND name='Synthetic' AND is_active)
 OR (SELECT count(*) FROM pg_trigger WHERE tgfoid='ops.capture_price_entry_change()'::regprocedure AND NOT tgisinternal)<>8
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.outbox_events'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_auth_members WHERE roleid='upc_outbox_capture'::regrole)
 OR has_table_privilege('upc_outbox_capture','catalog.price_quantity_tiers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_outbox_capture','catalog.price_lists','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_runtime','ops.outbox_events','SELECT,INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'FAIL catalog capture or prior capture regression'; END IF;
END $$;
ROLLBACK;
\echo PASS catalog outbox: product and variant changes, active quote, no-op, rollback, duplicate SKU, tenant isolation and prior six event kinds

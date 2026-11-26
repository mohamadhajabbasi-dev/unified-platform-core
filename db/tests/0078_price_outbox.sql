\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_outbox_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_outbox_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_outbox_a,upc_outbox_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0780000-0000-0000-0000-000000000001','outbox-price-a','Synthetic A'),
 ('a0780000-0000-0000-0000-000000000002','outbox-price-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0780000-0000-0000-0000-000000000001','test','outbox-price-a'),
 ('b0780000-0000-0000-0000-000000000002','test','outbox-price-b');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0780000-0000-0000-0000-000000000001','b0780000-0000-0000-0000-000000000001'),
 ('a0780000-0000-0000-0000-000000000002','b0780000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_outbox_a','a0780000-0000-0000-0000-000000000001','b0780000-0000-0000-0000-000000000001'),
 ('upc_outbox_b','a0780000-0000-0000-0000-000000000002','b0780000-0000-0000-0000-000000000002');
INSERT INTO iam.roles(tenant_id,role_id,role_key) VALUES
 ('a0780000-0000-0000-0000-000000000001','c0780000-0000-0000-0000-000000000001','outbox-price-editor'),
 ('a0780000-0000-0000-0000-000000000002','c0780000-0000-0000-0000-000000000002','outbox-price-editor');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='outbox-price-editor' AND p.permission_key IN ('catalog.read','catalog.write','catalog.price.write');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE r.role_key='outbox-price-editor';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0780000-0000-0000-0000-000000000001','Synthetic fixture'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('outbox-price-a','outbox-price-b') AND m.module_key='catalog';
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0780000-0000-0000-0000-000000000001','d0780000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0780000-0000-0000-0000-000000000002','d0780000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0780000-0000-0000-0000-000000000001','e0780000-0000-0000-0000-000000000001','d0780000-0000-0000-0000-000000000001','outbox-1','Synthetic'),
 ('a0780000-0000-0000-0000-000000000001','e0780000-0000-0000-0000-000000000003','d0780000-0000-0000-0000-000000000001','outbox-3','Synthetic race'),
 ('a0780000-0000-0000-0000-000000000002','e0780000-0000-0000-0000-000000000002','d0780000-0000-0000-0000-000000000002','outbox-1','Synthetic');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES
 ('a0780000-0000-0000-0000-000000000001','f0780000-0000-0000-0000-000000000001','original','IRR','Synthetic'),
 ('a0780000-0000-0000-0000-000000000002','f0780000-0000-0000-0000-000000000002','original','IRR','Synthetic');
SET SESSION AUTHORIZATION upc_outbox_a;
DO $$
DECLARE t uuid:=iam.current_tenant_id(); v uuid:='e0780000-0000-0000-0000-000000000001'; l uuid:='f0780000-0000-0000-0000-000000000001'; p uuid; cmd text;
BEGIN
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(t,v,l,100,tstzrange('2026-01-01 00:00+00',NULL,'[)')) RETURNING price_id INTO p;
 UPDATE catalog.price_entries SET valid_during=valid_during WHERE price_id=p;
 UPDATE catalog.price_entries SET valid_during=tstzrange('2026-01-01 00:00+00','2026-02-01 00:00+00','[)') WHERE price_id=p;
 INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(t,v,l,200,tstzrange('2026-02-01 00:00+00',NULL,'[)'));
 BEGIN
  INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
  VALUES(t,v,l,999,tstzrange('2026-03-01 00:00+00',NULL,'[)'));
  RAISE EXCEPTION 'FAIL overlapping price admitted';
 EXCEPTION WHEN exclusion_violation THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
  VALUES(t,'e0780000-0000-0000-0000-000000000003',l,333,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
  RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 BEGIN
  INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
  VALUES('a0780000-0000-0000-0000-000000000002','e0780000-0000-0000-0000-000000000002','f0780000-0000-0000-0000-000000000002',200,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
  RAISE EXCEPTION 'FAIL cross tenant price insert';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['SELECT * FROM ops.outbox_events','INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(iam.current_tenant_id(),''catalog.price_entry.changed'')','UPDATE ops.outbox_events SET recorded_at=now()','DELETE FROM ops.outbox_events','TRUNCATE ops.outbox_events','SET ROLE upc_outbox_capture','SELECT ops.capture_price_entry_change()'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL outbox direct access: %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_outbox_b;
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during)
 VALUES(iam.current_tenant_id(),'e0780000-0000-0000-0000-000000000002','f0780000-0000-0000-0000-000000000002',400,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
RESET SESSION AUTHORIZATION;
DO $$
BEGIN
 IF (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0780000-0000-0000-0000-000000000001')<>3
 OR (SELECT count(*) FROM ops.outbox_events WHERE tenant_id='a0780000-0000-0000-0000-000000000002')<>1
 OR (SELECT count(*) FROM catalog.price_entries WHERE tenant_id='a0780000-0000-0000-0000-000000000001')<>2
 OR EXISTS(SELECT 1 FROM ops.outbox_events WHERE event_kind<>'catalog.price_entry.changed')
 THEN RAISE EXCEPTION 'FAIL exact price change capture or rollback'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='ops.outbox_events'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_auth_members WHERE roleid='upc_outbox_capture'::regrole)
 OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='upc_outbox_capture' AND NOT rolcanlogin AND NOT rolbypassrls AND NOT rolsuper)
 OR has_table_privilege('upc_outbox_capture','ops.outbox_events','SELECT')
 OR has_table_privilege('upc_outbox_capture','ops.outbox_events','UPDATE')
 OR has_table_privilege('upc_outbox_capture','ops.outbox_events','DELETE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='ops.capture_price_entry_change()'::regprocedure AND prosecdef AND proowner='upc_outbox_capture'::regrole AND proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL outbox security contract'; END IF;
END $$;
ROLLBACK;
\echo PASS transactional price outbox: exact tenant-scoped changes, no-op, conflicts, rollback and no direct runtime access

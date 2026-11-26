\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_stock_alert_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stock_alert_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stock_alert_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stock_alert_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stock_alert_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_stock_alert_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_stock_alert_a,upc_stock_alert_b,upc_stock_alert_reader,upc_stock_alert_nocrm,upc_stock_alert_unmapped,upc_stock_alert_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0730000-0000-0000-0000-000000000001','stock-alert-a','Synthetic A'),('a0730000-0000-0000-0000-000000000002','stock-alert-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0730000-0000-0000-0000-00000000000'||i)::uuid,'test','stock-alert-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0730000-0000-0000-0000-000000000002'::uuid ELSE 'a0730000-0000-0000-0000-000000000001'::uuid END,
 ('b0730000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_stock_alert_a','upc_stock_alert_b','upc_stock_alert_reader','upc_stock_alert_nocrm','upc_stock_alert_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0730000-0000-0000-0000-000000000002'::uuid ELSE 'a0730000-0000-0000-0000-000000000001'::uuid END,
 ('b0730000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0730000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'stock-alert-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='stock-alert-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('stock-alert-1','stock-alert-2') AND p.permission_key IN ('crm.read','catalog.read','inventory.read','catalog.stock_alerts.read','catalog.stock_alerts.write','ops.audit.read'))
 OR (r.role_key='stock-alert-3' AND p.permission_key IN ('crm.read','catalog.read','inventory.read','catalog.stock_alerts.read'))
 OR (r.role_key='stock-alert-4' AND p.permission_key IN ('catalog.stock_alerts.read','catalog.stock_alerts.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0730000-0000-0000-0000-000000000001','d0730000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0730000-0000-0000-0000-000000000001','d0730000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0730000-0000-0000-0000-000000000002','d0730000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0730000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('stock-alert-a','stock-alert-b') AND m.module_key IN ('crm','catalog','inventory');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES ('a0730000-0000-0000-0000-000000000001','f0730000-0000-0000-0000-000000000001','Synthetic A','physical'),('a0730000-0000-0000-0000-000000000002','f0730000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES ('a0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001','f0730000-0000-0000-0000-000000000001','a-1','Synthetic A1'),('a0730000-0000-0000-0000-000000000002','e0730000-0000-0000-0000-000000000002','f0730000-0000-0000-0000-000000000002','b-1','Synthetic B1'),('a0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000003','f0730000-0000-0000-0000-000000000001','a-2','Synthetic A2');
SET SESSION AUTHORIZATION upc_stock_alert_b;
SELECT catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000002','e0730000-0000-0000-0000-000000000002',true);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stock_alert_a;
DO $$
DECLARE fid uuid; replay uuid; before_row jsonb; cmd text;
BEGIN
 IF catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',false) IS NOT NULL THEN RAISE EXCEPTION 'FAIL absent remove'; END IF;
 fid:=catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true);
 SELECT to_jsonb(f) INTO before_row FROM catalog.stock_alert_subscriptions f WHERE subscription_id=fid;
 replay:=catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true);
 IF fid IS NULL OR replay IS DISTINCT FROM fid OR before_row IS NULL
 OR (SELECT to_jsonb(f) FROM catalog.stock_alert_subscriptions f WHERE subscription_id=fid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM catalog.stock_alert_subscriptions)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions' AND entity_id=fid AND event_type='insert' AND actor_user_id=iam.current_user_id())<>1
 THEN RAISE EXCEPTION 'FAIL add, scope, replay or audit'; END IF;
 replay:=catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions WHERE subscription_id=fid AND NOT is_requested) THEN RAISE EXCEPTION 'FAIL deactivate'; END IF;
 SELECT to_jsonb(f) INTO before_row FROM catalog.stock_alert_subscriptions f WHERE subscription_id=fid;
 replay:=catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR (SELECT to_jsonb(f) FROM catalog.stock_alert_subscriptions f WHERE subscription_id=fid) IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'FAIL remove replay'; END IF;
 replay:=catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions WHERE subscription_id=fid AND is_requested)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions' AND entity_id=fid AND event_type='update')<>2 THEN RAISE EXCEPTION 'FAIL reactivate/audit'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000002','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL foreign customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000002',false); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_stock_alert_request(NULL,'e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL null customer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001',NULL,true); RAISE EXCEPTION 'FAIL null variant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null state'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO catalog.stock_alert_subscriptions(tenant_id,customer_id,variant_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid())',
 'UPDATE catalog.stock_alert_subscriptions SET is_requested=false','DELETE FROM catalog.stock_alert_subscriptions','TRUNCATE catalog.stock_alert_subscriptions','SET ROLE upc_stock_alert_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000003',true); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM catalog.stock_alert_subscriptions)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions')<>3 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stock_alert_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.stock_alert_subscriptions)<>1 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stock_alert_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) THEN RAISE EXCEPTION 'FAIL missing base permissions'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL missing base permission write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stock_alert_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0730000-0000-0000-0000-000000000001',module_id,false,'b0730000-0000-0000-0000-000000000001','Synthetic disabled' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_stock_alert_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) THEN RAISE EXCEPTION 'FAIL disabled catalog read'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL disabled catalog write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
-- Re-enable catalog, then independently deny inventory module access.
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0730000-0000-0000-0000-000000000001',module_id,true,'b0730000-0000-0000-0000-000000000001','Synthetic reenable' FROM platform.modules WHERE module_key='catalog';
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0730000-0000-0000-0000-000000000001',module_id,false,'b0730000-0000-0000-0000-000000000001','Synthetic disabled' FROM platform.modules WHERE module_key='inventory';
SET SESSION AUTHORIZATION upc_stock_alert_a;
DO $ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) THEN RAISE EXCEPTION 'FAIL disabled inventory read'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL disabled inventory write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0730000-0000-0000-0000-000000000001',module_id,true,'b0730000-0000-0000-0000-000000000001','Synthetic reenable' FROM platform.modules WHERE module_key='inventory';
DELETE FROM iam.role_grants WHERE tenant_id='a0730000-0000-0000-0000-000000000001' AND permission_key='inventory.read';
SET SESSION AUTHORIZATION upc_stock_alert_a;
DO $ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions) THEN RAISE EXCEPTION 'FAIL missing inventory permission'; END IF;
 BEGIN PERFORM catalog.set_stock_alert_request('d0730000-0000-0000-0000-000000000001','e0730000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL missing inventory write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_stock_alert_b;
DO $ BEGIN
 IF (SELECT count(*) FROM catalog.stock_alert_subscriptions)<>1 OR NOT EXISTS(SELECT 1 FROM catalog.stock_alert_subscriptions WHERE variant_id='e0730000-0000-0000-0000-000000000002' AND customer_id='d0730000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.stock_alert_subscriptions)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.stock_alert_subscriptions')<>4
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='catalog.stock_alert_subscriptions'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','catalog.stock_alert_subscriptions','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_stock_alert_executor','MEMBER')
 OR has_column_privilege('upc_stock_alert_executor','crm.customers','display_name','SELECT')
 OR has_column_privilege('upc_stock_alert_executor','catalog.variants','name','SELECT')
 OR has_table_privilege('upc_stock_alert_executor','crm.customer_identifiers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_stock_alert_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_stock_alert_executor','inventory.stock_ledger','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_stock_alert_executor','crm.customer_consent_events','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_stock_alert_executor','catalog.product_favorites','SELECT,INSERT,UPDATE,DELETE')
 OR EXISTS(SELECT 1 FROM crm.customer_consent_events WHERE tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002'))
 OR EXISTS(SELECT 1 FROM catalog.product_favorites WHERE tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002'))
 OR EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id IN ('a0730000-0000-0000-0000-000000000001','a0730000-0000-0000-0000-000000000002'))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='catalog.set_stock_alert_request(uuid,uuid,boolean)'::regprocedure AND r.rolname='upc_stock_alert_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS stock alert requests: composite tenant FKs, read/write and module gates, add/remove/reactivate, idempotency, audit and rollback

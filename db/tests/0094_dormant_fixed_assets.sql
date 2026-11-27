\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_asset_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_asset_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_asset_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_asset_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_asset_a,upc_asset_b,upc_asset_unmapped;
GRANT upc_platform_approver TO upc_asset_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0940000-0000-0000-0000-000000000001','asset-a','Synthetic A'),
 ('a0940000-0000-0000-0000-000000000002','asset-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0940000-0000-0000-0000-000000000001','test','asset-a'),
 ('b0940000-0000-0000-0000-000000000002','test','asset-b'),
 ('b0940000-0000-0000-0000-000000000003','test','asset-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0940000-0000-0000-0000-000000000001','b0940000-0000-0000-0000-000000000001'),
 ('a0940000-0000-0000-0000-000000000002','b0940000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_asset_a','a0940000-0000-0000-0000-000000000001','b0940000-0000-0000-0000-000000000001'),
 ('upc_asset_b','a0940000-0000-0000-0000-000000000002','b0940000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_asset_platform','b0940000-0000-0000-0000-000000000003',true);
DO $$
DECLARE a uuid:='a0940000-0000-0000-0000-000000000001'; b uuid:='a0940000-0000-0000-0000-000000000002';
 id uuid:='d0940000-0000-0000-0000-000000000001'; rel regclass:='inventory.stock_assets';
 prior_audit jsonb; prior_events jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) INTO prior_audit FROM ops.audit_events x WHERE tenant_id IN(a,b);
 SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) INTO prior_events FROM ops.outbox_events x WHERE tenant_id IN(a,b);
 INSERT INTO inventory.stock_assets(tenant_id,asset_id,asset_key,display_name) VALUES(a,id,'equipment-01','Synthetic equipment A'),(b,id,'equipment-01','Synthetic equipment B');
 INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(a,'equipment-02','Synthetic equipment A');
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(a,'equipment-01','Conflicting identity');
  RAISE EXCEPTION 'FAIL duplicate asset key'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_id,asset_key,display_name) VALUES(a,id,'equipment-03','Conflicting ID');
  RAISE EXCEPTION 'FAIL duplicate asset ID'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(a,' equipment-03','Invalid key');
  RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(a,'equipment-03',' ');
  RAISE EXCEPTION 'FAIL blank name'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES('00000000-0000-0000-0000-000000000000','equipment-03','Unknown tenant');
  RAISE EXCEPTION 'FAIL missing tenant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(a,'equipment-03','Synthetic rollback');
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM inventory.stock_assets WHERE tenant_id IN(a,b))<>3
 OR (SELECT display_name FROM inventory.stock_assets WHERE tenant_id=a AND asset_id=id)<>'Synthetic equipment A'
 OR (SELECT display_name FROM inventory.stock_assets WHERE tenant_id=b AND asset_id=id)<>'Synthetic equipment B'
 OR EXISTS(SELECT 1 FROM catalog.products WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM catalog.variants WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM procurement.purchase_orders WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM finance.journal_entries WHERE tenant_id IN(a,b))
 OR prior_audit IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM ops.audit_events x WHERE tenant_id IN(a,b))
 OR prior_events IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(x) ORDER BY to_jsonb(x)::text) FROM ops.outbox_events x WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or automatic stock/finance effect'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
 OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
 OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_identity_writer','upc_platform_approver','upc_inventory_executor','upc_reorder_executor','upc_procurement_executor','upc_finance_executor','upc_finance_checker','upc_outbox_capture']) r(role_name)
 WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
 THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
END $$;
SET SESSION AUTHORIZATION upc_asset_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0940000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM inventory.stock_assets; RAISE EXCEPTION 'FAIL direct asset read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA inventory TO upc_asset_a,upc_asset_b,upc_asset_unmapped,upc_asset_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON inventory.stock_assets TO upc_asset_a,upc_asset_b,upc_asset_unmapped,upc_asset_platform;
SET SESSION AUTHORIZATION upc_asset_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM inventory.stock_assets) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO inventory.stock_assets(tenant_id,asset_key,display_name) VALUES(iam.current_tenant_id(),'equipment-03','Synthetic'); RAISE EXCEPTION 'FAIL RLS insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE inventory.stock_assets SET display_name='Modified'; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM inventory.stock_assets; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_asset_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.stock_assets) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_asset_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.stock_assets) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_asset_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM inventory.stock_assets) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant fixed asset identity: tenant scope, unique keys, input bounds, rollback, deny-all RLS and no catalog, stock or finance effect

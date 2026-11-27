\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_plan_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_plan_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_plan_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_plan_platform LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_plan_a,upc_plan_b,upc_plan_unmapped;
GRANT upc_platform_approver TO upc_plan_platform;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0920000-0000-0000-0000-000000000001','planning-a','Synthetic A'),
 ('a0920000-0000-0000-0000-000000000002','planning-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0920000-0000-0000-0000-000000000001','test','planning-a'),
 ('b0920000-0000-0000-0000-000000000002','test','planning-b'),
 ('b0920000-0000-0000-0000-000000000003','test','planning-platform');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0920000-0000-0000-0000-000000000001','b0920000-0000-0000-0000-000000000001'),
 ('a0920000-0000-0000-0000-000000000002','b0920000-0000-0000-0000-000000000002');
INSERT INTO iam.db_principals VALUES
 ('upc_plan_a','a0920000-0000-0000-0000-000000000001','b0920000-0000-0000-0000-000000000001'),
 ('upc_plan_b','a0920000-0000-0000-0000-000000000002','b0920000-0000-0000-0000-000000000002');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin) VALUES
 ('upc_plan_platform','b0920000-0000-0000-0000-000000000003',true);
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0920000-0000-0000-0000-000000000001','d0920000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0920000-0000-0000-0000-000000000002','d0920000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0920000-0000-0000-0000-000000000001','e0920000-0000-0000-0000-000000000001','d0920000-0000-0000-0000-000000000001','planning-1','Synthetic'),
 ('a0920000-0000-0000-0000-000000000001','e0920000-0000-0000-0000-000000000002','d0920000-0000-0000-0000-000000000001','planning-2','Synthetic'),
 ('a0920000-0000-0000-0000-000000000002','e0920000-0000-0000-0000-000000000003','d0920000-0000-0000-0000-000000000002','planning-1','Synthetic');
INSERT INTO inventory.warehouses(tenant_id,warehouse_id,warehouse_key,name) VALUES
 ('a0920000-0000-0000-0000-000000000001','c0920000-0000-0000-0000-000000000001','planning-a','Synthetic A'),
 ('a0920000-0000-0000-0000-000000000002','c0920000-0000-0000-0000-000000000002','planning-b','Synthetic B');
DO $$
DECLARE a uuid:='a0920000-0000-0000-0000-000000000001'; b uuid:='a0920000-0000-0000-0000-000000000002';
 wa uuid:='c0920000-0000-0000-0000-000000000001'; wb uuid:='c0920000-0000-0000-0000-000000000002';
 ra uuid:='f0920000-0000-0000-0000-000000000001'; rb uuid:='f0920000-0000-0000-0000-000000000002';
 k uuid:='f0920000-0000-0000-0000-000000000003';
 va uuid:='e0920000-0000-0000-0000-000000000001'; va2 uuid:='e0920000-0000-0000-0000-000000000002'; vb uuid:='e0920000-0000-0000-0000-000000000003';
 rel regclass; prior jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) INTO prior FROM ops.outbox_events AS e WHERE tenant_id IN(a,b);
 INSERT INTO procurement.procurement_requests(tenant_id,request_id,request_key,warehouse_id) VALUES(a,ra,k,wa),(b,rb,k,wb);
 INSERT INTO procurement.procurement_request_items VALUES(a,ra,va,5),(a,ra,va2,7),(b,rb,vb,5);
 BEGIN INSERT INTO procurement.procurement_requests(tenant_id,request_key,warehouse_id) VALUES(a,k,wa);
  RAISE EXCEPTION 'FAIL duplicate request key'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_requests(tenant_id,request_key,warehouse_id) VALUES(a,gen_random_uuid(),wb);
  RAISE EXCEPTION 'FAIL cross-tenant warehouse'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_request_items VALUES(a,ra,va,6);
  RAISE EXCEPTION 'FAIL duplicate variant line'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_request_items VALUES(a,rb,va,1);
  RAISE EXCEPTION 'FAIL cross-tenant request'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_request_items VALUES(a,ra,vb,1);
  RAISE EXCEPTION 'FAIL cross-tenant variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE procurement.procurement_request_items SET requested_units=0 WHERE tenant_id=a AND request_id=ra AND variant_id=va;
  RAISE EXCEPTION 'FAIL zero quantity'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_requests(tenant_id,request_key,warehouse_id) VALUES(a,gen_random_uuid(),wa);
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM procurement.procurement_requests WHERE tenant_id IN(a,b))<>2
 OR (SELECT count(*) FROM procurement.procurement_request_items WHERE tenant_id IN(a,b))<>3
 OR (SELECT requested_units FROM procurement.procurement_request_items WHERE tenant_id=a AND request_id=ra AND variant_id=va)<>5
 OR EXISTS(SELECT 1 FROM procurement.purchase_orders WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM procurement.purchase_items WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM procurement.goods_receipts WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM inventory.stock_ledger WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM inventory.reservations WHERE tenant_id IN(a,b))
 OR EXISTS(SELECT 1 FROM inventory.reorder_policies WHERE tenant_id IN(a,b))
 OR prior IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(e) ORDER BY tenant_id,event_id) FROM ops.outbox_events AS e WHERE tenant_id IN(a,b))
 THEN RAISE EXCEPTION 'FAIL rollback or automatic procurement/stock effect'; END IF;
 FOREACH rel IN ARRAY ARRAY['procurement.procurement_requests'::regclass,'procurement.procurement_request_items'::regclass] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rel AND relrowsecurity AND relforcerowsecurity)
  OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=rel)
  OR EXISTS(SELECT 1 FROM unnest(ARRAY['upc_runtime','upc_platform_approver','upc_identity_writer','upc_procurement_executor','upc_inventory_executor','upc_reorder_executor','upc_outbox_capture']) r(role_name)
   WHERE has_table_privilege(r.role_name,rel,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  THEN RAISE EXCEPTION 'FAIL dormant ACL/RLS'; END IF;
 END LOOP;
END $$;
SET SESSION AUTHORIZATION upc_plan_a;
DO $$ BEGIN
 IF iam.current_tenant_id() IS DISTINCT FROM 'a0920000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL existing IAM'; END IF;
 BEGIN PERFORM 1 FROM procurement.procurement_requests; RAISE EXCEPTION 'FAIL direct request read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM 1 FROM procurement.procurement_request_items; RAISE EXCEPTION 'FAIL direct item read'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
GRANT USAGE ON SCHEMA procurement TO upc_plan_a,upc_plan_b,upc_plan_unmapped,upc_plan_platform;
GRANT SELECT,INSERT,UPDATE,DELETE ON procurement.procurement_requests,procurement.procurement_request_items TO upc_plan_a,upc_plan_b,upc_plan_unmapped,upc_plan_platform;
SET SESSION AUTHORIZATION upc_plan_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM procurement.procurement_requests) OR EXISTS(SELECT 1 FROM procurement.procurement_request_items) THEN RAISE EXCEPTION 'FAIL RLS read'; END IF;
 BEGIN INSERT INTO procurement.procurement_requests(tenant_id,request_key,warehouse_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),'c0920000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL RLS request insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN INSERT INTO procurement.procurement_request_items VALUES(iam.current_tenant_id(),'f0920000-0000-0000-0000-000000000001','e0920000-0000-0000-0000-000000000001',1); RAISE EXCEPTION 'FAIL RLS item insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE procurement.procurement_request_items SET requested_units=99; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS update'; END IF;
 DELETE FROM procurement.procurement_requests; IF FOUND THEN RAISE EXCEPTION 'FAIL RLS delete'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_plan_b;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM procurement.procurement_requests) OR EXISTS(SELECT 1 FROM procurement.procurement_request_items) THEN RAISE EXCEPTION 'FAIL other tenant RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_plan_unmapped;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM procurement.procurement_requests) OR EXISTS(SELECT 1 FROM procurement.procurement_request_items) THEN RAISE EXCEPTION 'FAIL unmapped RLS'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_plan_platform;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM procurement.procurement_requests) OR EXISTS(SELECT 1 FROM procurement.procurement_request_items) THEN RAISE EXCEPTION 'FAIL platform RLS bypass'; END IF; END $$;
RESET SESSION AUTHORIZATION;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS dormant procurement planning: canonical warehouse and variant references, scoped uniqueness, quantity bounds, tenant FKs, rollback, deny-all RLS and no stock or purchase effect

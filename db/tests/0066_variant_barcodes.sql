\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_bar_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bar_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bar_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bar_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bar_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_bar_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_bar_a,upc_bar_b,upc_bar_reader,upc_bar_nocrm,upc_bar_unmapped,upc_bar_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0660000-0000-0000-0000-000000000001','bar-a','Synthetic A'),('a0660000-0000-0000-0000-000000000002','bar-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0660000-0000-0000-0000-00000000000'||i)::uuid,'test','bar-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0660000-0000-0000-0000-000000000002'::uuid ELSE 'a0660000-0000-0000-0000-000000000001'::uuid END,
 ('b0660000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_bar_a','upc_bar_b','upc_bar_reader','upc_bar_nocrm','upc_bar_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0660000-0000-0000-0000-000000000002'::uuid ELSE 'a0660000-0000-0000-0000-000000000001'::uuid END,
 ('b0660000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0660000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'bar-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0660000-0000-0000-0000-000000000001','a0660000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='bar-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0660000-0000-0000-0000-000000000001','a0660000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0660000-0000-0000-0000-000000000001','a0660000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('bar-1','bar-2') AND p.permission_key IN ('catalog.read','catalog.write','ops.audit.read'))
 OR (r.role_key='bar-3' AND p.permission_key IN ('catalog.read'))
 OR (r.role_key='bar-4' AND p.permission_key IN ('catalog.write')));
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0660000-0000-0000-0000-000000000001','d0660000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0660000-0000-0000-0000-000000000002','d0660000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0660000-0000-0000-0000-000000000001','e0660000-0000-0000-0000-000000000001','d0660000-0000-0000-0000-000000000001','00123','One'),
 ('a0660000-0000-0000-0000-000000000001','e0660000-0000-0000-0000-000000000003','d0660000-0000-0000-0000-000000000001','different','Two'),
 ('a0660000-0000-0000-0000-000000000002','e0660000-0000-0000-0000-000000000002','d0660000-0000-0000-0000-000000000002','00123','B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0660000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('bar-a','bar-b') AND m.module_key='catalog';
SET SESSION AUTHORIZATION upc_bar_b;
SELECT catalog.register_variant_barcode('e0660000-0000-0000-0000-000000000002','00123');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_a;
DO $$
DECLARE v uuid:='e0660000-0000-0000-0000-000000000001'; v2 uuid:='e0660000-0000-0000-0000-000000000003'; foreign_v uuid:='e0660000-0000-0000-0000-000000000002'; absent uuid:='e0660000-0000-0000-0000-000000000099'; id uuid; retry uuid; snap jsonb; facts jsonb; bad text; cmd text;
BEGIN
 IF EXISTS(SELECT 1 FROM catalog.variant_barcodes) THEN RAISE EXCEPTION 'FAIL cross tenant read'; END IF;
 SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.product_id) FROM catalog.products p),(SELECT jsonb_agg(to_jsonb(vv) ORDER BY vv.variant_id) FROM catalog.variants vv)) INTO facts;
 id:=catalog.register_variant_barcode(v,'00123');
 SELECT to_jsonb(b) INTO STRICT snap FROM catalog.variant_barcodes b WHERE b.barcode_id=id;
 retry:=catalog.register_variant_barcode(v,'00123');
 IF retry IS DISTINCT FROM id OR snap IS DISTINCT FROM (SELECT to_jsonb(b) FROM catalog.variant_barcodes b WHERE barcode_id=id) THEN RAISE EXCEPTION 'FAIL exact replay'; END IF;
 PERFORM catalog.register_variant_barcode(v,'123');
 PERFORM catalog.register_variant_barcode(v,'AbC');
 PERFORM catalog.register_variant_barcode(v,'abc');
 PERFORM catalog.register_variant_barcode(v2,repeat('X',128));
 IF (SELECT count(*) FROM catalog.variant_barcodes)<>5 OR (SELECT count(*) FROM catalog.variant_barcodes WHERE variant_id=v)<>4 THEN RAISE EXCEPTION 'FAIL distinct aliases'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(v2,'00123'); RAISE EXCEPTION 'FAIL conflicting variant'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM catalog.register_variant_barcode(foreign_v,'00123'); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.register_variant_barcode(absent,'00123'); RAISE EXCEPTION 'FAIL missing variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.register_variant_barcode(NULL,'X'); RAISE EXCEPTION 'FAIL null variant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',' 123','123 ','1 2',E'1\n2',E'1\t2','۱۲۳',repeat('X',129)] LOOP
  BEGIN PERFORM catalog.register_variant_barcode(v,bad); RAISE EXCEPTION 'FAIL invalid code'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO catalog.variant_barcodes(tenant_id,variant_id,barcode_code) VALUES(iam.current_tenant_id(),gen_random_uuid(),''BYPASS'')','UPDATE catalog.variant_barcodes SET barcode_code=''BYPASS''','DELETE FROM catalog.variant_barcodes','TRUNCATE catalog.variant_barcodes','SET ROLE upc_barcode_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct DML/role'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM catalog.register_variant_barcode(v,'ROLLBACK'); RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF facts IS DISTINCT FROM jsonb_build_array((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.product_id) FROM catalog.products p),(SELECT jsonb_agg(to_jsonb(vv) ORDER BY vv.variant_id) FROM catalog.variants vv))
 OR (SELECT count(*) FROM catalog.variant_barcodes)<>5
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.variant_barcodes' AND event_type='insert' AND actor_user_id=iam.current_user_id())<>5
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.variant_barcodes')<>5 THEN RAISE EXCEPTION 'FAIL canonical facts or audit'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.variant_barcodes)<>5 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.variant_barcodes) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.variant_barcodes) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.variant_barcodes) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_bar_b;
DO $$ BEGIN IF (SELECT count(*) FROM catalog.variant_barcodes)<>1 OR NOT EXISTS(SELECT 1 FROM catalog.variant_barcodes WHERE barcode_code='00123' AND variant_id='e0660000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL B scope'; END IF; END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0660000-0000-0000-0000-000000000001',module_id,false,'b0660000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_bar_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.variant_barcodes) THEN RAISE EXCEPTION 'FAIL disabled module read'; END IF;
 BEGIN PERFORM catalog.register_variant_barcode(gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL disabled module write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.variant_barcodes)<>6 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.variant_barcodes')<>6
 OR has_table_privilege('upc_runtime','catalog.variant_barcodes','INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_column_privilege('upc_barcode_executor','catalog.variants','sku','SELECT,UPDATE')
 OR pg_has_role('upc_runtime','upc_barcode_executor','MEMBER') THEN RAISE EXCEPTION 'FAIL global count or ACL'; END IF;
END $$;
ROLLBACK;
\echo PASS variant barcode metadata: exact code, tenant uniqueness, replay, conflict, scoped grants and audit

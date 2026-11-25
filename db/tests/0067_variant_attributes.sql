\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_attr_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attr_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attr_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attr_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attr_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attr_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_attr_a,upc_attr_b,upc_attr_reader,upc_attr_nocrm,upc_attr_unmapped,upc_attr_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0670000-0000-0000-0000-000000000001','attr-a','Synthetic A'),('a0670000-0000-0000-0000-000000000002','attr-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0670000-0000-0000-0000-00000000000'||i)::uuid,'test','attr-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0670000-0000-0000-0000-000000000002'::uuid ELSE 'a0670000-0000-0000-0000-000000000001'::uuid END,
 ('b0670000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_attr_a','upc_attr_b','upc_attr_reader','upc_attr_nocrm','upc_attr_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0670000-0000-0000-0000-000000000002'::uuid ELSE 'a0670000-0000-0000-0000-000000000001'::uuid END,
 ('b0670000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0670000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'attr-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0670000-0000-0000-0000-000000000001','a0670000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='attr-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0670000-0000-0000-0000-000000000001','a0670000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0670000-0000-0000-0000-000000000001','a0670000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('attr-1','attr-2') AND p.permission_key IN ('catalog.read','catalog.write','ops.audit.read'))
 OR (r.role_key='attr-3' AND p.permission_key IN ('catalog.read'))
 OR (r.role_key='attr-4' AND p.permission_key IN ('catalog.write')));
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES
 ('a0670000-0000-0000-0000-000000000001','d0670000-0000-0000-0000-000000000001','Synthetic A','physical'),
 ('a0670000-0000-0000-0000-000000000002','d0670000-0000-0000-0000-000000000002','Synthetic B','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES
 ('a0670000-0000-0000-0000-000000000001','e0670000-0000-0000-0000-000000000001','d0670000-0000-0000-0000-000000000001','00123','One'),
 ('a0670000-0000-0000-0000-000000000001','e0670000-0000-0000-0000-000000000003','d0670000-0000-0000-0000-000000000001','different','Two'),
 ('a0670000-0000-0000-0000-000000000002','e0670000-0000-0000-0000-000000000002','d0670000-0000-0000-0000-000000000002','00123','B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0670000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('attr-a','attr-b') AND m.module_key='catalog';
SET SESSION AUTHORIZATION upc_attr_b;
SELECT catalog.register_attribute_definition('color','رنگ') AS foreign_attr \gset
SELECT catalog.set_variant_attribute_value('e0670000-0000-0000-0000-000000000002',:'foreign_attr','White');
RESET SESSION AUTHORIZATION;
SELECT set_config('upc.test_foreign_attr',:'foreign_attr',true);
SET SESSION AUTHORIZATION upc_attr_a;
SELECT catalog.register_variant_barcode('e0670000-0000-0000-0000-000000000001','00123');
INSERT INTO catalog.categories(tenant_id,name) VALUES(iam.current_tenant_id(),'Synthetic category');
INSERT INTO catalog.product_categories SELECT iam.current_tenant_id(),'d0670000-0000-0000-0000-000000000001',category_id FROM catalog.categories;
RESET SESSION AUTHORIZATION;
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES('a0670000-0000-0000-0000-000000000001','f0670000-0000-0000-0000-000000000001','original','IRR','Synthetic');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES('a0670000-0000-0000-0000-000000000001','e0670000-0000-0000-0000-000000000001','f0670000-0000-0000-0000-000000000001',1000,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
CREATE TEMP TABLE prior_attribute_facts AS SELECT jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.products t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.variants t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.categories t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.product_categories t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.variant_barcodes t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.price_lists t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.price_entries t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM inventory.stock_ledger t)) AS facts;
SET SESSION AUTHORIZATION upc_attr_a;
DO $$
DECLARE v uuid:='e0670000-0000-0000-0000-000000000001'; v2 uuid:='e0670000-0000-0000-0000-000000000003'; fv uuid:='e0670000-0000-0000-0000-000000000002'; fa uuid:=current_setting('upc.test_foreign_attr')::uuid; absent uuid:='e0670000-0000-0000-0000-000000000099'; color uuid; size_id uuid; id uuid; retry uuid; snap jsonb; def_snap jsonb; bad text; cmd text;
BEGIN
 IF EXISTS(SELECT 1 FROM catalog.attribute_definitions) OR EXISTS(SELECT 1 FROM catalog.variant_attribute_values) THEN RAISE EXCEPTION 'FAIL foreign read'; END IF;
 color:=catalog.register_attribute_definition('color','رنگ');
 SELECT to_jsonb(d) INTO STRICT def_snap FROM catalog.attribute_definitions d WHERE attribute_id=color;
 retry:=catalog.register_attribute_definition('color','رنگ');
 IF retry IS DISTINCT FROM color OR def_snap IS DISTINCT FROM (SELECT to_jsonb(d) FROM catalog.attribute_definitions d WHERE attribute_id=color) THEN RAISE EXCEPTION 'FAIL definition replay'; END IF;
 size_id:=catalog.register_attribute_definition('size','سایز');
 id:=catalog.set_variant_attribute_value(v,color,'مشکی');
 SELECT to_jsonb(a) INTO STRICT snap FROM catalog.variant_attribute_values a WHERE assignment_id=id;
 retry:=catalog.set_variant_attribute_value(v,color,'مشکی');
 IF retry IS DISTINCT FROM id OR snap IS DISTINCT FROM (SELECT to_jsonb(a) FROM catalog.variant_attribute_values a WHERE assignment_id=id) THEN RAISE EXCEPTION 'FAIL value replay'; END IF;
 retry:=catalog.set_variant_attribute_value(v,color,'White  Pearl');
 IF retry IS DISTINCT FROM id OR NOT EXISTS(SELECT 1 FROM catalog.variant_attribute_values a WHERE assignment_id=id AND value_text='White  Pearl' AND to_jsonb(a)->'created_at'=snap->'created_at' AND changed_at>=(snap->>'changed_at')::timestamptz) THEN RAISE EXCEPTION 'FAIL value replacement'; END IF;
 PERFORM catalog.set_variant_attribute_value(v,size_id,'XL');
 PERFORM catalog.set_variant_attribute_value(v2,color,'White  Pearl');
 BEGIN PERFORM catalog.register_attribute_definition('color','Different'); RAISE EXCEPTION 'FAIL key conflict'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(fv,color,'X'); RAISE EXCEPTION 'FAIL foreign variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(v,fa,'X'); RAISE EXCEPTION 'FAIL foreign attribute'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(absent,color,'X'); RAISE EXCEPTION 'FAIL missing variant'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(v,absent,'X'); RAISE EXCEPTION 'FAIL missing attribute'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(NULL,color,'X'); RAISE EXCEPTION 'FAIL null variant'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(v,NULL,'X'); RAISE EXCEPTION 'FAIL null attribute'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',' ','Bad Key','UPPER',repeat('x',81)] LOOP
  BEGIN PERFORM catalog.register_attribute_definition(bad,'Label'); RAISE EXCEPTION 'FAIL invalid key'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',' ',E'bad\nvalue',repeat('x',121)] LOOP
  BEGIN PERFORM catalog.register_attribute_definition('invalid-label',bad); RAISE EXCEPTION 'FAIL invalid label'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH bad IN ARRAY ARRAY[NULL::text,'',' ',E'bad\nvalue',E'bad\tvalue',repeat('x',513)] LOOP
  BEGIN PERFORM catalog.set_variant_attribute_value(v,color,bad); RAISE EXCEPTION 'FAIL invalid value'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 END LOOP;
 FOREACH cmd IN ARRAY ARRAY['INSERT INTO catalog.attribute_definitions(tenant_id,attribute_key,display_name) VALUES(iam.current_tenant_id(),''bypass'',''Bypass'')','UPDATE catalog.attribute_definitions SET display_name=''Bypass''','DELETE FROM catalog.attribute_definitions','TRUNCATE catalog.attribute_definitions','INSERT INTO catalog.variant_attribute_values(tenant_id,variant_id,attribute_id,value_text) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid(),''Bypass'')','UPDATE catalog.variant_attribute_values SET value_text=''Bypass''','DELETE FROM catalog.variant_attribute_values','TRUNCATE catalog.variant_attribute_values','SET ROLE upc_attribute_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write or role'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 SELECT to_jsonb(a) INTO STRICT snap FROM catalog.variant_attribute_values a WHERE assignment_id=id;
 BEGIN PERFORM catalog.set_variant_attribute_value(v,color,'Rollback'); PERFORM catalog.register_attribute_definition('rollback','Rollback'); RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF snap IS DISTINCT FROM (SELECT to_jsonb(a) FROM catalog.variant_attribute_values a WHERE assignment_id=id) OR (SELECT count(*) FROM catalog.attribute_definitions)<>2 OR (SELECT count(*) FROM catalog.variant_attribute_values)<>3 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type IN ('catalog.attribute_definitions','catalog.variant_attribute_values'))<>6 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.variant_attribute_values' AND event_type='update' AND actor_user_id=iam.current_user_id() AND entity_id=id)<>1 THEN RAISE EXCEPTION 'FAIL rollback, count or audit'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_attr_reader;
DO $$ BEGIN IF (SELECT count(*) FROM catalog.attribute_definitions)<>2 OR (SELECT count(*) FROM catalog.variant_attribute_values)<>3 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM catalog.register_attribute_definition('reader','Reader'); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(gen_random_uuid(),gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL reader assignment'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_attr_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.attribute_definitions) OR EXISTS(SELECT 1 FROM catalog.variant_attribute_values) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_attribute_definition('invalid','Invalid'); RAISE EXCEPTION 'FAIL unauthorized definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(gen_random_uuid(),gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized assignment'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_attr_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.attribute_definitions) OR EXISTS(SELECT 1 FROM catalog.variant_attribute_values) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_attribute_definition('invalid','Invalid'); RAISE EXCEPTION 'FAIL unauthorized definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(gen_random_uuid(),gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized assignment'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_attr_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.attribute_definitions) OR EXISTS(SELECT 1 FROM catalog.variant_attribute_values) THEN RAISE EXCEPTION 'FAIL unauthorized read'; END IF;
 BEGIN PERFORM catalog.register_attribute_definition('invalid','Invalid'); RAISE EXCEPTION 'FAIL unauthorized definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(gen_random_uuid(),gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL unauthorized assignment'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_attr_b;
DO $$ BEGIN IF (SELECT count(*) FROM catalog.attribute_definitions)<>1 OR (SELECT count(*) FROM catalog.variant_attribute_values)<>1 OR NOT EXISTS(SELECT 1 FROM catalog.variant_attribute_values WHERE value_text='White') THEN RAISE EXCEPTION 'FAIL B scope'; END IF; END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0670000-0000-0000-0000-000000000001',module_id,false,'b0670000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_attr_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.attribute_definitions) OR EXISTS(SELECT 1 FROM catalog.variant_attribute_values) THEN RAISE EXCEPTION 'FAIL disabled module read'; END IF;
 BEGIN PERFORM catalog.register_attribute_definition('invalid','Invalid'); RAISE EXCEPTION 'FAIL disabled definition'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM catalog.set_variant_attribute_value(gen_random_uuid(),gen_random_uuid(),'X'); RAISE EXCEPTION 'FAIL disabled assignment'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT facts FROM prior_attribute_facts) IS DISTINCT FROM jsonb_build_array(
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.products t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.variants t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.categories t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.product_categories t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.variant_barcodes t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.price_lists t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM catalog.price_entries t),
 (SELECT jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text) FROM inventory.stock_ledger t))
 OR (SELECT count(*) FROM catalog.attribute_definitions)<>3 OR (SELECT count(*) FROM catalog.variant_attribute_values)<>4
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type IN ('catalog.attribute_definitions','catalog.variant_attribute_values'))<>8
 OR has_table_privilege('upc_runtime','catalog.attribute_definitions','INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_table_privilege('upc_runtime','catalog.variant_attribute_values','INSERT,UPDATE,DELETE,TRUNCATE')
 OR has_column_privilege('upc_attribute_executor','catalog.variants','sku','SELECT,UPDATE')
 OR pg_has_role('upc_runtime','upc_attribute_executor','MEMBER') THEN RAISE EXCEPTION 'FAIL canonical snapshot or ACL'; END IF;
END $$;
ROLLBACK;
\echo PASS variant attributes: canonical definitions, one current value, exact replay, tenant isolation, protected updates, audit and rollback

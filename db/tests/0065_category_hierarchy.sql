\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_tree_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tree_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tree_reader LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_tree_a,upc_tree_b,upc_tree_reader;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0650000-0000-0000-0000-000000000001','tree-a','Synthetic A'),
 ('a0650000-0000-0000-0000-000000000002','tree-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('b0650000-0000-0000-0000-000000000001','test','tree-a'),
 ('b0650000-0000-0000-0000-000000000002','test','tree-b'),
 ('b0650000-0000-0000-0000-000000000003','test','tree-reader');
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000001'),
 ('a0650000-0000-0000-0000-000000000002','b0650000-0000-0000-0000-000000000002'),
 ('a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_tree_a','a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000001'),
 ('upc_tree_b','a0650000-0000-0000-0000-000000000002','b0650000-0000-0000-0000-000000000002'),
 ('upc_tree_reader','a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('a0650000-0000-0000-0000-000000000001','tree-editor'),
 ('a0650000-0000-0000-0000-000000000002','tree-editor'),
 ('a0650000-0000-0000-0000-000000000001','tree-reader');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key
 FROM iam.roles r CROSS JOIN iam.permissions p WHERE r.role_key='tree-editor' AND p.permission_key IN ('catalog.read','catalog.write','catalog.price.write','ops.audit.read');
INSERT INTO iam.role_grants SELECT tenant_id,role_id,'catalog.read' FROM iam.roles WHERE role_key='tree-reader';
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id
 FROM iam.memberships m JOIN iam.roles r USING(tenant_id)
 WHERE (m.user_id='b0650000-0000-0000-0000-000000000003' AND r.role_key='tree-reader')
 OR (m.user_id<>'b0650000-0000-0000-0000-000000000003' AND r.role_key='tree-editor');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0650000-0000-0000-0000-000000000001','Synthetic test'
 FROM core.tenants t CROSS JOIN platform.modules m WHERE t.tenant_key IN ('tree-a','tree-b') AND m.module_key='catalog';


CREATE ROLE upc_tree_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_tree_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_tree_unmapped,upc_tree_none;
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES('b0650000-0000-0000-0000-000000000004','test','tree-none');
INSERT INTO iam.memberships VALUES('a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000004',clock_timestamp());
INSERT INTO iam.db_principals VALUES('upc_tree_none','a0650000-0000-0000-0000-000000000001','b0650000-0000-0000-0000-000000000004');
SET SESSION AUTHORIZATION upc_tree_b;
INSERT INTO catalog.categories(tenant_id,category_id,name) VALUES(iam.current_tenant_id(),'c0650000-0000-0000-0000-000000000009','Root');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tree_a;
INSERT INTO catalog.categories(tenant_id,category_id,name) VALUES
 (iam.current_tenant_id(),'c0650000-0000-0000-0000-000000000001','Root'),
 (iam.current_tenant_id(),'c0650000-0000-0000-0000-000000000002','Branch'),
 (iam.current_tenant_id(),'c0650000-0000-0000-0000-000000000003','Leaf'),
 (iam.current_tenant_id(),'c0650000-0000-0000-0000-000000000004','Other');
INSERT INTO catalog.products(tenant_id,product_id,name,kind) VALUES(iam.current_tenant_id(),'d0650000-0000-0000-0000-000000000001','Synthetic','physical');
INSERT INTO catalog.variants(tenant_id,variant_id,product_id,sku,name) VALUES(iam.current_tenant_id(),'e0650000-0000-0000-0000-000000000001','d0650000-0000-0000-0000-000000000001','tree-sku','Synthetic');
INSERT INTO catalog.price_lists(tenant_id,price_list_id,list_key,currency,name) VALUES(iam.current_tenant_id(),'f0650000-0000-0000-0000-000000000001','original','IRR','Synthetic');
INSERT INTO catalog.price_entries(tenant_id,variant_id,price_list_id,amount,valid_during) VALUES(iam.current_tenant_id(),'e0650000-0000-0000-0000-000000000001','f0650000-0000-0000-0000-000000000001',1000,tstzrange('2026-01-01 00:00+00',NULL,'[)'));
INSERT INTO catalog.product_categories VALUES(iam.current_tenant_id(),'d0650000-0000-0000-0000-000000000001','c0650000-0000-0000-0000-000000000003');
DO $$
DECLARE root uuid:='c0650000-0000-0000-0000-000000000001'; branch uuid:='c0650000-0000-0000-0000-000000000002'; leaf uuid:='c0650000-0000-0000-0000-000000000003'; other uuid:='c0650000-0000-0000-0000-000000000004'; foreign_id uuid:='c0650000-0000-0000-0000-000000000009'; absent uuid:='c0650000-0000-0000-0000-000000000099';
 result uuid; original jsonb; snap jsonb; before_facts jsonb; after_facts jsonb; cmd text; n int;
BEGIN
 SELECT jsonb_agg(to_jsonb(c)-'parent_category_id' ORDER BY c.category_id) INTO original FROM catalog.categories c;
 SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.product_id) FROM catalog.products p),(SELECT jsonb_agg(to_jsonb(v) ORDER BY v.variant_id) FROM catalog.variants v),(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.price_id) FROM catalog.price_entries e),(SELECT jsonb_agg(to_jsonb(l) ORDER BY l.price_list_id) FROM catalog.price_lists l),(SELECT jsonb_agg(to_jsonb(pc) ORDER BY pc.category_id) FROM catalog.product_categories pc)) INTO before_facts;
 result:=catalog.set_category_parent(branch,root);
 IF result IS DISTINCT FROM branch THEN RAISE EXCEPTION 'FAIL first edge'; END IF;
 result:=catalog.set_category_parent(leaf,branch);
 IF result IS DISTINCT FROM leaf OR (SELECT parent_category_id FROM catalog.categories WHERE category_id=leaf) IS DISTINCT FROM branch THEN RAISE EXCEPTION 'FAIL second edge'; END IF;
 result:=catalog.set_category_parent(other,leaf);
 IF result IS DISTINCT FROM other THEN RAISE EXCEPTION 'FAIL third edge'; END IF;
 SELECT jsonb_agg(to_jsonb(c) ORDER BY c.category_id) INTO snap FROM catalog.categories c;
 result:=catalog.set_category_parent(other,leaf);
 IF result IS DISTINCT FROM other OR snap IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.category_id) FROM catalog.categories c) THEN RAISE EXCEPTION 'FAIL replay'; END IF;
 BEGIN PERFORM catalog.set_category_parent(root,other); RAISE EXCEPTION 'FAIL long cycle'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(root,branch); RAISE EXCEPTION 'FAIL two cycle'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(root,root); RAISE EXCEPTION 'FAIL self cycle'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(leaf,foreign_id); RAISE EXCEPTION 'FAIL cross tenant parent'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(foreign_id,root); RAISE EXCEPTION 'FAIL cross tenant child'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(leaf,absent); RAISE EXCEPTION 'FAIL missing parent'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(absent,NULL); RAISE EXCEPTION 'FAIL missing child'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM catalog.set_category_parent(NULL,root); RAISE EXCEPTION 'FAIL null child'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN INSERT INTO catalog.categories(tenant_id,name) VALUES(iam.current_tenant_id(),'rOoT'); RAISE EXCEPTION 'FAIL duplicate name'; EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN INSERT INTO catalog.categories(tenant_id,name,parent_category_id) VALUES(iam.current_tenant_id(),'Bypass',root); RAISE EXCEPTION 'FAIL direct parent insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE catalog.categories SET parent_category_id=NULL WHERE category_id=leaf; RAISE EXCEPTION 'FAIL direct parent update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY['DELETE FROM catalog.categories','TRUNCATE catalog.categories','SET ROLE upc_category_executor'] LOOP
 BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct DML or role'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM catalog.set_category_parent(other,root); RAISE EXCEPTION 'Synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF snap IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.category_id) FROM catalog.categories c) OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.categories')<>3 THEN RAISE EXCEPTION 'FAIL rejected or rolled back changes'; END IF;
 result:=catalog.set_category_parent(other,root);
 IF result IS DISTINCT FROM other OR (SELECT parent_category_id FROM catalog.categories WHERE category_id=other) IS DISTINCT FROM root THEN RAISE EXCEPTION 'FAIL reparent'; END IF;
 result:=catalog.set_category_parent(branch,NULL);
 IF result IS DISTINCT FROM branch OR NOT EXISTS(SELECT 1 FROM catalog.categories WHERE category_id=branch AND parent_category_id IS NULL) OR (SELECT parent_category_id FROM catalog.categories WHERE category_id=leaf) IS DISTINCT FROM branch THEN RAISE EXCEPTION 'FAIL detach'; END IF;
 result:=catalog.set_category_parent(branch,NULL);
 IF result IS DISTINCT FROM branch OR original IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c)-'parent_category_id' ORDER BY c.category_id) FROM catalog.categories c) THEN RAISE EXCEPTION 'FAIL original category fields'; END IF;
 SELECT jsonb_build_array((SELECT jsonb_agg(to_jsonb(p) ORDER BY p.product_id) FROM catalog.products p),(SELECT jsonb_agg(to_jsonb(v) ORDER BY v.variant_id) FROM catalog.variants v),(SELECT jsonb_agg(to_jsonb(e) ORDER BY e.price_id) FROM catalog.price_entries e),(SELECT jsonb_agg(to_jsonb(l) ORDER BY l.price_list_id) FROM catalog.price_lists l),(SELECT jsonb_agg(to_jsonb(pc) ORDER BY pc.category_id) FROM catalog.product_categories pc)) INTO after_facts;
 IF before_facts IS DISTINCT FROM after_facts OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.categories' AND event_type='update' AND actor_user_id=iam.current_user_id())<>5 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.categories')<>5 THEN RAISE EXCEPTION 'FAIL canonical facts or audit'; END IF;
 UPDATE catalog.categories SET name='Other renamed',is_active=false WHERE category_id=other;
 DELETE FROM catalog.product_categories WHERE category_id=leaf;
 INSERT INTO catalog.product_categories VALUES(iam.current_tenant_id(),'d0650000-0000-0000-0000-000000000001',leaf);
 IF NOT EXISTS(SELECT 1 FROM catalog.categories WHERE category_id=other AND NOT is_active AND name='Other renamed') OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.categories')<>5 THEN RAISE EXCEPTION 'FAIL legacy operations'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tree_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.categories)<>4 THEN RAISE EXCEPTION 'FAIL reader scope'; END IF;
 BEGIN PERFORM catalog.set_category_parent('c0650000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tree_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.categories) THEN RAISE EXCEPTION 'FAIL no permission read'; END IF;
 BEGIN PERFORM catalog.set_category_parent(gen_random_uuid(),NULL); RAISE EXCEPTION 'FAIL no permission write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tree_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.categories) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM catalog.set_category_parent(gen_random_uuid(),NULL); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_tree_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM catalog.categories)<>1 OR NOT EXISTS(SELECT 1 FROM catalog.categories WHERE name='Root' AND parent_category_id IS NULL) OR EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_type='catalog.categories') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0650000-0000-0000-0000-000000000001',module_id,false,'b0650000-0000-0000-0000-000000000001','Synthetic disable' FROM platform.modules WHERE module_key='catalog';
SET SESSION AUTHORIZATION upc_tree_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM catalog.categories) THEN RAISE EXCEPTION 'FAIL disabled catalog read'; END IF;
 BEGIN PERFORM catalog.set_category_parent('c0650000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL disabled catalog write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
DO $$
DECLARE c text;
BEGIN
 FOREACH c IN ARRAY ARRAY['tenant_id','category_id','name','is_active'] LOOP
 IF NOT has_column_privilege('upc_runtime','catalog.categories',c,'INSERT') THEN RAISE EXCEPTION 'FAIL original insert grant'; END IF;
 END LOOP;
 IF NOT has_column_privilege('upc_runtime','catalog.categories','name','UPDATE') OR NOT has_column_privilege('upc_runtime','catalog.categories','is_active','UPDATE')
 OR has_column_privilege('upc_runtime','catalog.categories','parent_category_id','INSERT,UPDATE') OR has_column_privilege('upc_category_executor','catalog.categories','name','SELECT,UPDATE')
 OR pg_has_role('upc_runtime','upc_category_executor','MEMBER') OR (SELECT count(*) FROM catalog.categories)<>5
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='catalog.categories')<>5 THEN RAISE EXCEPTION 'FAIL ACL or global count'; END IF;
END $$;
ROLLBACK;
\echo PASS category hierarchy: canonical categories, recursive cycle rejection, exact replay, legacy ACL, audit and rollback

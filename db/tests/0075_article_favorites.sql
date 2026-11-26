\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_article_favorite_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_article_favorite_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_article_favorite_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_article_favorite_nocrm LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_article_favorite_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_article_favorite_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_article_favorite_a,upc_article_favorite_b,upc_article_favorite_reader,upc_article_favorite_nocrm,upc_article_favorite_unmapped,upc_article_favorite_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0750000-0000-0000-0000-000000000001','favorite-a','Synthetic A'),('a0750000-0000-0000-0000-000000000002','favorite-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0750000-0000-0000-0000-00000000000'||i)::uuid,'test','favorite-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0750000-0000-0000-0000-000000000002'::uuid ELSE 'a0750000-0000-0000-0000-000000000001'::uuid END,
 ('b0750000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_article_favorite_a','upc_article_favorite_b','upc_article_favorite_reader','upc_article_favorite_nocrm','upc_article_favorite_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0750000-0000-0000-0000-000000000002'::uuid ELSE 'a0750000-0000-0000-0000-000000000001'::uuid END,
 ('b0750000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0750000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'favorite-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='favorite-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('favorite-1','favorite-2') AND p.permission_key IN ('crm.read','content.read','content.favorites.read','content.favorites.write','ops.audit.read'))
 OR (r.role_key='favorite-3' AND p.permission_key IN ('crm.read','content.read','content.favorites.read'))
 OR (r.role_key='favorite-4' AND p.permission_key IN ('content.favorites.read','content.favorites.write')));
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('a0750000-0000-0000-0000-000000000001','d0750000-0000-0000-0000-000000000001','Synthetic A'),
 ('a0750000-0000-0000-0000-000000000001','d0750000-0000-0000-0000-000000000003','Synthetic A2'),
 ('a0750000-0000-0000-0000-000000000002','d0750000-0000-0000-0000-000000000002','Synthetic B');
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0750000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('favorite-a','favorite-b') AND m.module_key IN ('crm','content');
INSERT INTO content.articles(tenant_id,article_id,slug,title,body) VALUES ('a0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001','synthetic-a','Synthetic A','Text A'),('a0750000-0000-0000-0000-000000000002','e0750000-0000-0000-0000-000000000002','synthetic-b','Synthetic B','Text B'),('a0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000003','synthetic-a2','Synthetic A2','Text A2');
SET SESSION AUTHORIZATION upc_article_favorite_b;
SELECT content.set_article_favorite('d0750000-0000-0000-0000-000000000002','e0750000-0000-0000-0000-000000000002',true);
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_article_favorite_a;
DO $$
DECLARE fid uuid; replay uuid; before_row jsonb; cmd text;
BEGIN
 IF content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',false) IS NOT NULL THEN RAISE EXCEPTION 'FAIL absent remove'; END IF;
 fid:=content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true);
 SELECT to_jsonb(f) INTO before_row FROM content.article_favorites f WHERE favorite_id=fid;
 replay:=content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true);
 IF fid IS NULL OR replay IS DISTINCT FROM fid OR before_row IS NULL
 OR (SELECT to_jsonb(f) FROM content.article_favorites f WHERE favorite_id=fid) IS DISTINCT FROM before_row
 OR (SELECT count(*) FROM content.article_favorites)<>1
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_favorites' AND entity_id=fid AND event_type='insert' AND actor_user_id=iam.current_user_id())<>1
 THEN RAISE EXCEPTION 'FAIL add, scope, replay or audit'; END IF;
 replay:=content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM content.article_favorites WHERE favorite_id=fid AND NOT is_active) THEN RAISE EXCEPTION 'FAIL deactivate'; END IF;
 SELECT to_jsonb(f) INTO before_row FROM content.article_favorites f WHERE favorite_id=fid;
 replay:=content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',false);
 IF replay IS DISTINCT FROM fid OR (SELECT to_jsonb(f) FROM content.article_favorites f WHERE favorite_id=fid) IS DISTINCT FROM before_row THEN RAISE EXCEPTION 'FAIL remove replay'; END IF;
 replay:=content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true);
 IF replay IS DISTINCT FROM fid OR NOT EXISTS(SELECT 1 FROM content.article_favorites WHERE favorite_id=fid AND is_active)
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_favorites' AND entity_id=fid AND event_type='update')<>2 THEN RAISE EXCEPTION 'FAIL reactivate/audit'; END IF;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000002','e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL foreign customer'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000002',false); RAISE EXCEPTION 'FAIL foreign article'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM content.set_article_favorite(NULL,'e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL null customer'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001',NULL,true); RAISE EXCEPTION 'FAIL null article'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',NULL); RAISE EXCEPTION 'FAIL null state'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO content.article_favorites(tenant_id,customer_id,article_id) VALUES(iam.current_tenant_id(),gen_random_uuid(),gen_random_uuid())',
 'UPDATE content.article_favorites SET is_active=false','DELETE FROM content.article_favorites','TRUNCATE content.article_favorites','SET ROLE upc_article_favorite_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000003',true); RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002'; EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM content.article_favorites)<>1 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_favorites')<>3 THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_article_favorite_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_favorites)<>1 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_article_favorite_nocrm;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_favorites) THEN RAISE EXCEPTION 'FAIL missing base permissions'; END IF;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL missing base permission write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_article_favorite_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_favorites) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0750000-0000-0000-0000-000000000001',module_id,false,'b0750000-0000-0000-0000-000000000001','Synthetic disabled' FROM platform.modules WHERE module_key='content';
SET SESSION AUTHORIZATION upc_article_favorite_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_favorites) THEN RAISE EXCEPTION 'FAIL disabled content read'; END IF;
 BEGIN PERFORM content.set_article_favorite('d0750000-0000-0000-0000-000000000001','e0750000-0000-0000-0000-000000000001',true); RAISE EXCEPTION 'FAIL disabled content write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_article_favorite_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_favorites)<>1 OR NOT EXISTS(SELECT 1 FROM content.article_favorites WHERE article_id='e0750000-0000-0000-0000-000000000002' AND customer_id='d0750000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_favorites)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_favorites')<>4
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='content.article_favorites'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','content.article_favorites','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_article_favorite_executor','MEMBER')
 OR has_column_privilege('upc_article_favorite_executor','crm.customers','display_name','SELECT')
 OR has_column_privilege('upc_article_favorite_executor','content.articles','body','SELECT')
 OR has_table_privilege('upc_article_favorite_executor','crm.customer_identifiers','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_article_favorite_executor','sales.orders','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_article_favorite_executor','catalog.product_favorites','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_article_favorite_executor','content.article_revisions','SELECT,INSERT,UPDATE,DELETE')
 OR has_table_privilege('upc_article_favorite_executor','crm.customer_consent_events','SELECT,INSERT,UPDATE,DELETE')
 OR has_any_column_privilege('upc_article_favorite_executor','content.articles','UPDATE,INSERT')
 OR EXISTS(SELECT 1 FROM catalog.product_favorites WHERE tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002'))
 OR EXISTS(SELECT 1 FROM content.article_revisions WHERE tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002'))
 OR EXISTS(SELECT 1 FROM crm.customer_consent_events WHERE tenant_id IN ('a0750000-0000-0000-0000-000000000001','a0750000-0000-0000-0000-000000000002'))
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='content.set_article_favorite(uuid,uuid,boolean)'::regprocedure AND r.rolname='upc_article_favorite_executor' AND NOT r.rolcanlogin AND NOT r.rolbypassrls AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS article favorites: composite tenant FKs, read/write and module gates, add/remove/reactivate, idempotency, audit and rollback

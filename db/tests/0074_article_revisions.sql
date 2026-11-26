\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_revision_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_revision_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_revision_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_revision_nobase LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_revision_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_revision_none LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_revision_a,upc_revision_b,upc_revision_reader,upc_revision_nobase,upc_revision_unmapped,upc_revision_none;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0740000-0000-0000-0000-000000000001','revision-a','Synthetic A'),('a0740000-0000-0000-0000-000000000002','revision-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0740000-0000-0000-0000-00000000000'||i)::uuid,'test','revision-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0740000-0000-0000-0000-000000000002'::uuid ELSE 'a0740000-0000-0000-0000-000000000001'::uuid END,
 ('b0740000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_revision_a','upc_revision_b','upc_revision_reader','upc_revision_nobase','upc_revision_none'])[i]::name,
 CASE WHEN i=2 THEN 'a0740000-0000-0000-0000-000000000002'::uuid ELSE 'a0740000-0000-0000-0000-000000000001'::uuid END,
 ('b0740000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0740000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'revision-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0740000-0000-0000-0000-000000000001','a0740000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='revision-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0740000-0000-0000-0000-000000000001','a0740000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0740000-0000-0000-0000-000000000001','a0740000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('revision-1','revision-2') AND p.permission_key IN ('content.read','content.write','content.revisions.read','content.revisions.capture','ops.audit.read'))
 OR (r.role_key='revision-3' AND p.permission_key IN ('content.read','content.revisions.read'))
 OR (r.role_key='revision-4' AND p.permission_key IN ('content.revisions.read','content.revisions.capture')));
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT t.tenant_id,m.module_id,true,'b0740000-0000-0000-0000-000000000001','Synthetic fixture' FROM core.tenants t CROSS JOIN platform.modules m
 WHERE t.tenant_key IN ('revision-a','revision-b') AND m.module_key='content';
INSERT INTO content.articles(tenant_id,article_id,slug,title,body,seo_title) VALUES
 ('a0740000-0000-0000-0000-000000000001','d0740000-0000-0000-0000-000000000001','synthetic-a','Synthetic title','Initial body',NULL),
 ('a0740000-0000-0000-0000-000000000002','d0740000-0000-0000-0000-000000000002','synthetic-b','Synthetic title','Initial body',NULL);
SET SESSION AUTHORIZATION upc_revision_b;
SELECT content.capture_article_revision('d0740000-0000-0000-0000-000000000002');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_revision_a;
DO $$
DECLARE first_id uuid; second_id uuid; replay uuid; before_row jsonb; before_article jsonb; cmd text;
BEGIN
 SELECT to_jsonb(a) INTO before_article FROM content.articles a WHERE article_id='d0740000-0000-0000-0000-000000000001';
 first_id:=content.capture_article_revision('d0740000-0000-0000-0000-000000000001');
 SELECT to_jsonb(r) INTO before_row FROM content.article_revisions r WHERE revision_id=first_id;
 replay:=content.capture_article_revision('d0740000-0000-0000-0000-000000000001');
 IF first_id IS NULL OR replay IS DISTINCT FROM first_id OR before_row IS NULL
 OR (SELECT to_jsonb(r) FROM content.article_revisions r WHERE revision_id=first_id) IS DISTINCT FROM before_row
 OR (SELECT to_jsonb(a) FROM content.articles a WHERE article_id='d0740000-0000-0000-0000-000000000001') IS DISTINCT FROM before_article
 OR (SELECT count(*) FROM content.article_revisions)<>1
 OR NOT EXISTS(SELECT 1 FROM content.article_revisions WHERE revision_id=first_id AND captured_by=iam.current_user_id()
  AND snapshot->>'body'='Initial body' AND snapshot->'seo_title'='null'::jsonb AND NOT snapshot ? 'status' AND NOT snapshot ? 'author_user_id')
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_revisions' AND entity_id=first_id AND event_type='insert' AND actor_user_id=iam.current_user_id())<>1
 THEN RAISE EXCEPTION 'FAIL capture, replay, scope or audit'; END IF;
 UPDATE content.articles SET body='Second body',seo_title='Synthetic SEO' WHERE article_id='d0740000-0000-0000-0000-000000000001';
 second_id:=content.capture_article_revision('d0740000-0000-0000-0000-000000000001');
 IF second_id IS NULL OR second_id=first_id OR (SELECT count(*) FROM content.article_revisions)<>2
 OR (SELECT to_jsonb(r) FROM content.article_revisions r WHERE revision_id=first_id) IS DISTINCT FROM before_row
 OR NOT EXISTS(SELECT 1 FROM content.article_revisions WHERE revision_id=second_id AND snapshot->>'body'='Second body' AND snapshot->>'seo_title'='Synthetic SEO')
 THEN RAISE EXCEPTION 'FAIL distinct immutable version'; END IF;
 UPDATE content.articles SET body='Initial body',seo_title=NULL WHERE article_id='d0740000-0000-0000-0000-000000000001';
 replay:=content.capture_article_revision('d0740000-0000-0000-0000-000000000001');
 IF replay IS DISTINCT FROM first_id OR (SELECT count(*) FROM content.article_revisions)<>2
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_revisions')<>2 THEN RAISE EXCEPTION 'FAIL identical reverted state'; END IF;
 BEGIN PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000002'); RAISE EXCEPTION 'FAIL foreign article'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM content.capture_article_revision(NULL); RAISE EXCEPTION 'FAIL null article'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 FOREACH cmd IN ARRAY ARRAY[
 'INSERT INTO content.article_revisions(tenant_id,article_id,captured_by,snapshot,snapshot_digest) VALUES(iam.current_tenant_id(),gen_random_uuid(),iam.current_user_id(),''{}'',sha256(convert_to(''{}'',''UTF8'')))',
 'UPDATE content.article_revisions SET snapshot=''{}''','DELETE FROM content.article_revisions','TRUNCATE content.article_revisions','SET ROLE upc_revision_executor'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL direct write %',cmd; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
  UPDATE content.articles SET body='Rolled back' WHERE article_id='d0740000-0000-0000-0000-000000000001';
  PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM content.article_revisions)<>2 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_revisions')<>2
 OR (SELECT body FROM content.articles WHERE article_id='d0740000-0000-0000-0000-000000000001')<>'Initial body' THEN RAISE EXCEPTION 'FAIL rollback'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_revision_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_revisions)<>2 THEN RAISE EXCEPTION 'FAIL reader'; END IF;
 BEGIN PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL reader write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_revision_nobase;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_revisions) THEN RAISE EXCEPTION 'FAIL missing base permissions'; END IF;
 BEGIN PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL missing base permission capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_revision_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_revisions) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL unmapped capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
INSERT INTO platform.tenant_module_grants(tenant_id,module_id,enabled,decided_by,reason)
 SELECT 'a0740000-0000-0000-0000-000000000001',module_id,false,'b0740000-0000-0000-0000-000000000001','Synthetic disabled' FROM platform.modules WHERE module_key='content';
SET SESSION AUTHORIZATION upc_revision_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.article_revisions) THEN RAISE EXCEPTION 'FAIL disabled content read'; END IF;
 BEGIN PERFORM content.capture_article_revision('d0740000-0000-0000-0000-000000000001'); RAISE EXCEPTION 'FAIL disabled content capture'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_revision_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_revisions)<>1 OR NOT EXISTS(SELECT 1 FROM content.article_revisions WHERE article_id='d0740000-0000-0000-0000-000000000002') THEN RAISE EXCEPTION 'FAIL B scope'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF (SELECT count(*) FROM content.article_revisions)<>3 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='content.article_revisions')<>3
 OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='content.article_revisions'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR has_table_privilege('upc_runtime','content.article_revisions','INSERT,UPDATE,DELETE,TRUNCATE')
 OR pg_has_role('upc_runtime','upc_revision_executor','MEMBER')
 OR has_any_column_privilege('upc_revision_executor','content.articles','INSERT,UPDATE,REFERENCES')
 OR has_column_privilege('upc_revision_executor','content.articles','status','SELECT')
 OR has_any_column_privilege('upc_revision_executor','content.article_revisions','UPDATE')
 OR has_table_privilege('upc_revision_executor','content.article_revisions','DELETE,TRUNCATE')
 OR has_table_privilege('upc_revision_executor','crm.customers','SELECT,INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'FAIL structural contract'; END IF;
END $$;
SELECT count(*) AS upc_base_table_count FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND n.nspname IN ('core','iam','crm','catalog','inventory','sales','finance','platform','ops','content','analytics','hr','procurement','web');
ROLLBACK;
\echo PASS article revisions: immutable distinct snapshots, tenant module permission gates, exact state retry, original article unchanged by capture, audit and rollback

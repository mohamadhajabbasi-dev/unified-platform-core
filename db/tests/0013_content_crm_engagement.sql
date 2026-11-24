\set ON_ERROR_STOP on
-- All values are invented synthetic fixtures; no external account or live DB.
BEGIN;
CREATE ROLE upc_eng_admin LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_eng_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_eng_b LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_platform_approver TO upc_eng_admin;
GRANT upc_runtime TO upc_eng_a,upc_eng_b;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('d0000000-0000-0000-0000-000000000001','eng-a','Synthetic tenant A'),
 ('d0000000-0000-0000-0000-000000000002','eng-b','Synthetic tenant B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject) VALUES
 ('d1000000-0000-0000-0000-000000000001','synthetic','eng-admin'),
 ('d1000000-0000-0000-0000-000000000002','synthetic','eng-a'),
 ('d1000000-0000-0000-0000-000000000003','synthetic','eng-b');
INSERT INTO iam.platform_staff_assignments(login_role,user_id,is_superadmin)
 VALUES('upc_eng_admin','d1000000-0000-0000-0000-000000000001',true);
INSERT INTO iam.memberships(tenant_id,user_id) VALUES
 ('d0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002'),
 ('d0000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003');
INSERT INTO iam.db_principals VALUES
 ('upc_eng_a','d0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000002'),
 ('upc_eng_b','d0000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000003');
INSERT INTO iam.roles(tenant_id,role_key) VALUES
 ('d0000000-0000-0000-0000-000000000001','eng-editor'),
 ('d0000000-0000-0000-0000-000000000002','eng-editor');
INSERT INTO iam.role_grants(tenant_id,role_id,permission_key)
 SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.role_key='eng-editor' AND p.permission_key IN
 ('content.read','content.write','crm.engagement.read','crm.engagement.write','crm.consent.read','crm.consent.write');
INSERT INTO iam.membership_roles(tenant_id,user_id,role_id)
 SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id WHERE r.role_key='eng-editor';
-- The only central customer: no per-channel customer master.
INSERT INTO crm.customers(tenant_id,customer_id,display_name) VALUES
 ('d0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','Synthetic customer A'),
 ('d0000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002','Synthetic customer B');

SET SESSION AUTHORIZATION upc_eng_admin;
SELECT platform.record_module_decision('d0000000-0000-0000-0000-000000000001','content',true,NULL,'Synthetic editorial approval');
SELECT platform.record_module_decision('d0000000-0000-0000-0000-000000000002','content',true,NULL,'Synthetic editorial approval');
SELECT platform.record_module_decision('d0000000-0000-0000-0000-000000000001','crm',true,NULL,'Synthetic CRM approval');
SELECT platform.record_module_decision('d0000000-0000-0000-0000-000000000002','crm',true,NULL,'Synthetic CRM approval');
RESET SESSION AUTHORIZATION;

SET SESSION AUTHORIZATION upc_eng_a;
INSERT INTO content.articles(tenant_id,article_id,author_user_id,slug,title,body,seo_title)
VALUES(iam.current_tenant_id(),'d3000000-0000-0000-0000-000000000001',iam.current_user_id(),
 'synthetic-topic','Synthetic article','Synthetic, non-personal content','Synthetic SEO');
UPDATE content.articles SET status='published',published_at=clock_timestamp() WHERE slug='synthetic-topic';
INSERT INTO crm.conversations(tenant_id,conversation_id,customer_id,channel,external_thread_digest)
 VALUES(iam.current_tenant_id(),'d4000000-0000-0000-0000-000000000001',
 'd2000000-0000-0000-0000-000000000001','whatsapp',decode(repeat('ab',32),'hex'));
INSERT INTO crm.conversation_messages(tenant_id,conversation_id,direction,sender_kind,body_ciphertext,key_ref,source_digest)
 VALUES(iam.current_tenant_id(),'d4000000-0000-0000-0000-000000000001',
 'inbound','customer',decode('aabbcc','hex'),'vault:synthetic',decode(repeat('cd',32),'hex'));
INSERT INTO crm.support_tickets(tenant_id,ticket_key,customer_id,conversation_id,subject,assigned_user_id)
 VALUES(iam.current_tenant_id(),'SYN-1','d2000000-0000-0000-0000-000000000001',
 'd4000000-0000-0000-0000-000000000001','Synthetic support',iam.current_user_id());
INSERT INTO crm.customer_consent_events(tenant_id,customer_id,purpose,granted,origin_channel,evidence_digest)
 VALUES(iam.current_tenant_id(),'d2000000-0000-0000-0000-000000000001','messaging',true,'whatsapp',decode(repeat('ef',32),'hex'));

DO $$
BEGIN
 IF (SELECT count(*) FROM content.articles)<>1
 OR (SELECT count(*) FROM crm.conversations)<>1
 OR (SELECT count(*) FROM crm.conversation_messages)<>1
 OR (SELECT count(*) FROM crm.support_tickets)<>1
 OR (SELECT count(*) FROM crm.customer_consent_events)<>1 THEN
   RAISE EXCEPTION 'FAIL authorized editorial/support records';
 END IF;
 BEGIN
  INSERT INTO content.articles(tenant_id,slug,title,body)
  VALUES(iam.current_tenant_id(),'SYNTHETIC-TOPIC','duplicate','not permitted');
  RAISE EXCEPTION 'FAIL duplicate case insensitive slug';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  INSERT INTO crm.conversation_messages(tenant_id,conversation_id,direction,sender_kind,body_ciphertext,key_ref,source_digest)
  VALUES(iam.current_tenant_id(),'d4000000-0000-0000-0000-000000000001',
  'inbound','customer',decode('deadbeef','hex'),'vault:synthetic',decode(repeat('cd',32),'hex'));
  RAISE EXCEPTION 'FAIL message delivery idempotency';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  DELETE FROM crm.customer_consent_events;
  RAISE EXCEPTION 'FAIL consent immutable delete';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO crm.support_tickets(tenant_id,ticket_key,customer_id,subject)
  VALUES(iam.current_tenant_id(),'FAKE-B','d2000000-0000-0000-0000-000000000002','bad foreign tenant');
  RAISE EXCEPTION 'FAIL cross tenant customer foreign key';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_eng_b;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM content.articles)
 OR EXISTS(SELECT 1 FROM crm.conversations)
 OR EXISTS(SELECT 1 FROM crm.conversation_messages)
 OR EXISTS(SELECT 1 FROM crm.support_tickets)
 OR EXISTS(SELECT 1 FROM crm.customer_consent_events) THEN
   RAISE EXCEPTION 'FAIL tenant data leakage';
 END IF;
 BEGIN
  INSERT INTO content.articles(tenant_id,slug,title,body)
  VALUES('d0000000-0000-0000-0000-000000000001','fake-topic','cross tenant','bad');
  RAISE EXCEPTION 'FAIL cross tenant insert';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_eng_admin;
SELECT platform.record_module_decision('d0000000-0000-0000-0000-000000000001','content',false,NULL,'Synthetic revocation');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_eng_a;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM content.articles) THEN RAISE EXCEPTION 'FAIL revoked content module'; END IF;
 IF (SELECT count(*) FROM crm.conversations)<>1 THEN RAISE EXCEPTION 'FAIL unrelated CRM module changed'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
ROLLBACK;
\echo PASS canonical editorial/CRM support: no duplicate masters, module grants, RLS, consent, idempotency

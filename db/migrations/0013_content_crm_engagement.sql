-- Migration 0013: requirements-first content and customer engagement.
-- Synthetic disposable PostgreSQL ONLY. Never run on ERPPlus/Commerce or live DB.
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'upc_greenfield_test' THEN
    RAISE EXCEPTION 'Migration 0013 requires isolated upc_greenfield_test';
  END IF;
END $$;

CREATE SCHEMA content;
REVOKE ALL ON SCHEMA content FROM PUBLIC;
INSERT INTO platform.modules(module_key,version_label) VALUES ('content','0.1');

INSERT INTO iam.permissions(permission_key,description) VALUES
 ('content.read','Read tenant editorial content'),
 ('content.write','Edit tenant editorial content'),
 ('crm.engagement.read','Read tenant CRM conversations and support'),
 ('crm.engagement.write','Maintain tenant CRM conversations and support'),
 ('crm.consent.read','Read tenant customer consent history'),
 ('crm.consent.write','Append trusted tenant customer consent evidence');

-- Editorial content is distinct from catalog.products; views come from analytics,
-- never a second mutable article view counter.
CREATE TABLE content.articles (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 article_id uuid NOT NULL DEFAULT gen_random_uuid(),
 author_user_id uuid,
 slug text NOT NULL CHECK (slug=btrim(slug) AND length(slug) BETWEEN 2 AND 200),
 title text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 300),
 excerpt text,
 body text NOT NULL,
 seo_title text CHECK (length(seo_title)<=300),
 seo_description text CHECK (length(seo_description)<=500),
 focus_keyword text CHECK (length(focus_keyword)<=200),
 cover_asset_ref text CHECK (length(cover_asset_ref) BETWEEN 1 AND 350),
 status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','archived')),
 is_featured boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 published_at timestamptz,
 PRIMARY KEY(tenant_id,article_id),
 FOREIGN KEY(tenant_id,author_user_id) REFERENCES iam.memberships(tenant_id,user_id),
 CHECK (status<>'published' OR published_at IS NOT NULL)
);
CREATE UNIQUE INDEX articles_tenant_slug_uq ON content.articles(tenant_id,lower(slug)) WHERE status<>'archived';
CREATE INDEX articles_tenant_published_idx ON content.articles(tenant_id,published_at DESC) WHERE status='published';

-- One conversation can be anonymous until verified. Never create Customers on a
-- message arrival. Store only opaque digest of external provider thread ID.
CREATE TABLE crm.conversations (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 conversation_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid,
 channel text NOT NULL CHECK(channel IN ('web','app','whatsapp','telegram','bale','email','phone','in_person','other')),
 external_thread_digest bytea CHECK(external_thread_digest IS NULL OR octet_length(external_thread_digest)=32),
 state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','resolved','closed')),
 started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,conversation_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id)
);
CREATE UNIQUE INDEX conversation_external_thread_uq
  ON crm.conversations(tenant_id,channel,external_thread_digest)
  WHERE external_thread_digest IS NOT NULL;
CREATE INDEX conversation_customer_idx ON crm.conversations(tenant_id,customer_id,started_at DESC);

-- Ciphertext is encrypted by an application-managed key before insertion.
-- No plaintext message body or third-party token is retained in the table.
CREATE TABLE crm.conversation_messages (
 tenant_id uuid NOT NULL,
 message_id uuid NOT NULL DEFAULT gen_random_uuid(),
 conversation_id uuid NOT NULL,
 source_digest bytea CHECK(source_digest IS NULL OR octet_length(source_digest)=32),
 direction text NOT NULL CHECK(direction IN ('inbound','outbound','internal')),
 sender_kind text NOT NULL CHECK(sender_kind IN ('customer','staff','bot','system')),
 body_ciphertext bytea NOT NULL CHECK(octet_length(body_ciphertext)>0),
 key_ref text NOT NULL CHECK(length(btrim(key_ref)) BETWEEN 1 AND 200),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,message_id),
 FOREIGN KEY(tenant_id,conversation_id) REFERENCES crm.conversations(tenant_id,conversation_id)
);
CREATE UNIQUE INDEX conversation_message_idempotent_uq
 ON crm.conversation_messages(tenant_id,conversation_id,source_digest)
 WHERE source_digest IS NOT NULL;
CREATE INDEX conversation_messages_thread_idx
 ON crm.conversation_messages(tenant_id,conversation_id,occurred_at);

-- Support tickets link conversations and the original tenant customer.
-- They are distinct service cases, not a duplicate customer or sale.
CREATE TABLE crm.support_tickets (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 ticket_id uuid NOT NULL DEFAULT gen_random_uuid(),
 ticket_key text NOT NULL CHECK(length(btrim(ticket_key)) BETWEEN 1 AND 100),
 customer_id uuid,
 conversation_id uuid,
 assigned_user_id uuid,
 subject text NOT NULL CHECK(length(btrim(subject)) BETWEEN 1 AND 300),
 priority text NOT NULL DEFAULT 'normal' CHECK(priority IN ('low','normal','high','urgent')),
 state text NOT NULL DEFAULT 'open' CHECK(state IN ('open','waiting','resolved','closed')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 resolved_at timestamptz,
 PRIMARY KEY(tenant_id,ticket_id),
 UNIQUE(tenant_id,ticket_key),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,conversation_id) REFERENCES crm.conversations(tenant_id,conversation_id),
 FOREIGN KEY(tenant_id,assigned_user_id) REFERENCES iam.memberships(tenant_id,user_id),
 CHECK(resolved_at IS NULL OR state IN ('resolved','closed'))
);
CREATE INDEX support_tickets_state_idx ON crm.support_tickets(tenant_id,state,priority,created_at DESC);

-- Append-only consent evidence. Current effective consent is derived from latest
-- verified event; messages/marketing must not infer consent from signup alone.
CREATE TABLE crm.customer_consent_events (
 tenant_id uuid NOT NULL,
 consent_event_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 purpose text NOT NULL CHECK(purpose IN ('marketing','messaging','analytics','privacy_notice')),
 granted boolean NOT NULL,
 origin_channel text NOT NULL CHECK(origin_channel IN ('web','app','whatsapp','telegram','bale','email','phone','in_person','other')),
 evidence_digest bytea NOT NULL CHECK(octet_length(evidence_digest)=32),
 observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,consent_event_id),
 UNIQUE(tenant_id,evidence_digest),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id)
);
CREATE INDEX customer_consent_lookup_idx
 ON crm.customer_consent_events(tenant_id,customer_id,purpose,observed_at DESC);

-- Tenant-isolation and permission enforcement; all writes fail closed if module
-- disabled or membership permissions removed. Runtime never gets DELETE grants.
DO $$
DECLARE rel regclass; p_read text; p_write text; m text;
BEGIN
 FOREACH rel IN ARRAY ARRAY[
 'content.articles'::regclass,
 'crm.conversations'::regclass,'crm.conversation_messages'::regclass,
 'crm.support_tickets'::regclass,'crm.customer_consent_events'::regclass]
 LOOP
   IF rel='content.articles'::regclass THEN
     p_read:='content.read';p_write:='content.write';m:='content';
   ELSIF rel='crm.customer_consent_events'::regclass THEN
     p_read:='crm.consent.read';p_write:='crm.consent.write';m:='crm';
   ELSE
     p_read:='crm.engagement.read';p_write:='crm.engagement.write';m:='crm';
   END IF;
   EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
   EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
   EXECUTE format('CREATE POLICY canonical_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND platform.module_enabled(%L))',rel,p_read,m);
   EXECUTE format('CREATE POLICY canonical_insert ON %s FOR INSERT TO upc_runtime WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND iam.has_permission(%L) AND platform.module_enabled(%L))',rel,p_read,p_write,m);
 END LOOP;
END $$;
CREATE POLICY content_update ON content.articles FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND iam.has_permission('content.write') AND platform.module_enabled('content'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('content.read') AND iam.has_permission('content.write') AND platform.module_enabled('content'));
CREATE POLICY ticket_update ON crm.support_tickets FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND platform.module_enabled('crm'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND platform.module_enabled('crm'));
CREATE POLICY conversation_update ON crm.conversations FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND platform.module_enabled('crm'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND platform.module_enabled('crm'));

GRANT USAGE ON SCHEMA content TO upc_runtime;
GRANT SELECT,INSERT ON content.articles,crm.conversations,crm.conversation_messages,crm.support_tickets,crm.customer_consent_events TO upc_runtime;
GRANT UPDATE(slug,title,excerpt,body,seo_title,seo_description,focus_keyword,cover_asset_ref,status,is_featured,published_at)
 ON content.articles TO upc_runtime;
GRANT UPDATE(state,customer_id) ON crm.conversations TO upc_runtime;
GRANT UPDATE(subject,priority,state,assigned_user_id,resolved_at,customer_id,conversation_id)
 ON crm.support_tickets TO upc_runtime;
COMMIT;

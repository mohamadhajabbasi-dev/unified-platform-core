-- 0013: consent-gated visitor sessions and bounded event collection.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
CREATE SCHEMA web;
REVOKE ALL ON SCHEMA web FROM PUBLIC;
CREATE ROLE upc_web_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_web_collector NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions VALUES ('web.analytics.read','Read own eligible Commerce analytics'),
 ('web.analytics.collect','Collect consented visits through trusted service'),
 ('web.analytics.privacy','Withdraw consent and purge expired visits');
-- No IP, raw URL, user agent, fingerprint, email, phone or cross-tenant visitor ID.
-- Source and campaign codes must come from sanitized, server-controlled taxonomy.
CREATE TABLE web.visitor_sessions (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 session_id uuid NOT NULL,
 started_at timestamptz NOT NULL,
 collection_until timestamptz NOT NULL,
 retain_until timestamptz NOT NULL,
 consent_version text NOT NULL CHECK(consent_version ~ '^[a-zA-Z0-9_.-]{1,40}$'),
 source_type text NOT NULL CHECK(source_type IN ('direct','organic','paid','referral','social','email','other')),
 source_code text CHECK(source_code ~ '^[a-zA-Z0-9_-]{1,80}$'),
 medium_code text CHECK(medium_code ~ '^[a-zA-Z0-9_-]{1,80}$'),
 campaign_code text CHECK(campaign_code ~ '^[a-zA-Z0-9_-]{1,80}$'),
 landing_kind text NOT NULL CHECK(landing_kind IN ('home','catalog','product','content','checkout','other')),
 withdrawn_at timestamptz,
 PRIMARY KEY(tenant_id,session_id),
 CHECK(collection_until>started_at AND retain_until>collection_until),
 CHECK(withdrawn_at IS NULL OR withdrawn_at>=started_at)
);
CREATE INDEX visitor_retention_idx ON web.visitor_sessions(tenant_id,retain_until);
CREATE INDEX visitor_source_idx ON web.visitor_sessions(tenant_id,started_at,source_type);
CREATE TABLE web.visit_events (
 tenant_id uuid NOT NULL,
 event_id uuid NOT NULL,
 session_id uuid NOT NULL,
 event_kind text NOT NULL CHECK(event_kind IN ('page_view','product_view','cart_add','checkout_start')),
 page_kind text NOT NULL CHECK(page_kind IN ('home','catalog','product','content','checkout','other')),
 variant_id uuid,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,event_id),
 FOREIGN KEY(tenant_id,session_id) REFERENCES web.visitor_sessions(tenant_id,session_id) ON DELETE CASCADE,
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id),
 CHECK(event_kind NOT IN ('product_view','cart_add') OR variant_id IS NOT NULL)
);
CREATE INDEX visit_events_session_idx ON web.visit_events(tenant_id,session_id,recorded_at);
CREATE INDEX visit_events_time_idx ON web.visit_events(tenant_id,recorded_at);
ALTER TABLE web.visitor_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE web.visitor_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE web.visit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE web.visit_events FORCE ROW LEVEL SECURITY;
CREATE POLICY sessions_read ON web.visitor_sessions FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('web.analytics.read')
 AND platform.commerce_eligible() AND withdrawn_at IS NULL AND retain_until>statement_timestamp());
CREATE POLICY events_read ON web.visit_events FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('web.analytics.read')
 AND platform.commerce_eligible() AND EXISTS(SELECT 1 FROM web.visitor_sessions s
 WHERE s.tenant_id=visit_events.tenant_id AND s.session_id=visit_events.session_id
 AND s.withdrawn_at IS NULL AND s.retain_until>statement_timestamp()));
CREATE POLICY sessions_executor ON web.visitor_sessions FOR ALL TO upc_web_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY events_executor ON web.visit_events FOR ALL TO upc_web_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT USAGE ON SCHEMA web TO upc_runtime,upc_web_collector,upc_web_executor;
GRANT USAGE ON SCHEMA iam,platform TO upc_web_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.commerce_eligible() TO upc_web_executor;
GRANT SELECT ON web.visitor_sessions,web.visit_events TO upc_runtime;
GRANT SELECT,INSERT,DELETE ON web.visitor_sessions,web.visit_events TO upc_web_executor;
GRANT UPDATE(withdrawn_at,source_code,medium_code,campaign_code,source_type,landing_kind) ON web.visitor_sessions TO upc_web_executor;
CREATE FUNCTION web.require_access(p_permission text,p_collect boolean) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR (p_collect AND NOT platform.commerce_eligible())
 THEN RAISE EXCEPTION 'Analytics access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 RETURN t;
END $$;
ALTER FUNCTION web.require_access(text,boolean) OWNER TO upc_web_executor;
REVOKE ALL ON FUNCTION web.require_access(text,boolean) FROM PUBLIC;
CREATE FUNCTION web.lock_session(p_tenant uuid,p_session uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('web-session',p_tenant,p_session)::text,0))
$$;
ALTER FUNCTION web.lock_session(uuid,uuid) OWNER TO upc_web_executor;
REVOKE ALL ON FUNCTION web.lock_session(uuid,uuid) FROM PUBLIC;
-- Collector authenticates consent, classifies bots and generates fresh random session UUIDs.
-- A boolean is not itself evidence of lawful consent; trusted service is required.
CREATE FUNCTION web.start_session(p_session uuid,p_consent boolean,p_bot boolean,p_version text,p_source text,
 p_source_code text,p_medium text,p_campaign text,p_landing text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=web.require_access('web.analytics.collect',true); prior web.visitor_sessions%ROWTYPE; ts timestamptz;
BEGIN
 IF p_session IS NULL OR p_consent IS DISTINCT FROM true OR p_bot IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Consented non-bot session required' USING ERRCODE='42501'; END IF;
 PERFORM web.lock_session(t,p_session);
 SELECT * INTO prior FROM web.visitor_sessions WHERE tenant_id=t AND session_id=p_session;
 IF FOUND THEN
  IF prior.withdrawn_at IS NOT NULL OR prior.collection_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'Session inactive' USING ERRCODE='23514'; END IF;
  IF prior.consent_version IS DISTINCT FROM p_version OR prior.source_type IS DISTINCT FROM p_source
  OR prior.source_code IS DISTINCT FROM p_source_code OR prior.medium_code IS DISTINCT FROM p_medium
  OR prior.campaign_code IS DISTINCT FROM p_campaign OR prior.landing_kind IS DISTINCT FROM p_landing
  THEN RAISE EXCEPTION 'Session idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN p_session;
 END IF;
 ts:=clock_timestamp();
 INSERT INTO web.visitor_sessions(tenant_id,session_id,started_at,collection_until,retain_until,consent_version,source_type,source_code,medium_code,campaign_code,landing_kind)
 VALUES(t,p_session,ts,ts+interval '24 hours',ts+interval '30 days',p_version,p_source,p_source_code,p_medium,p_campaign,p_landing);
 RETURN p_session;
END $$;
CREATE FUNCTION web.record_event(p_event uuid,p_session uuid,p_kind text,p_page text,p_variant uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=web.require_access('web.analytics.collect',true); s web.visitor_sessions%ROWTYPE; e web.visit_events%ROWTYPE;
BEGIN
 IF p_event IS NULL OR p_session IS NULL THEN RAISE EXCEPTION 'Event/session required' USING ERRCODE='22023'; END IF;
 PERFORM web.lock_session(t,p_session);
 SELECT * INTO s FROM web.visitor_sessions WHERE tenant_id=t AND session_id=p_session;
 IF NOT FOUND THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='23503'; END IF;
 IF s.withdrawn_at IS NOT NULL OR s.collection_until<=clock_timestamp()
 THEN RAISE EXCEPTION 'Session inactive' USING ERRCODE='23514'; END IF;
 -- Lock event key after session; duplicate requests do not increase counts.
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('web-event',t,p_event)::text,0));
 SELECT * INTO e FROM web.visit_events WHERE tenant_id=t AND event_id=p_event;
 IF FOUND THEN
  IF e.session_id<>p_session OR e.event_kind IS DISTINCT FROM p_kind OR e.page_kind IS DISTINCT FROM p_page
  OR e.variant_id IS DISTINCT FROM p_variant THEN RAISE EXCEPTION 'Event idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN p_event;
 END IF;
 -- Hard per-session cap; global rate limiting and partitioning remain service/design tasks.
 IF (SELECT count(*) FROM web.visit_events WHERE tenant_id=t AND session_id=p_session)>=500
 THEN RAISE EXCEPTION 'Session event limit' USING ERRCODE='23514'; END IF;
 INSERT INTO web.visit_events(tenant_id,event_id,session_id,event_kind,page_kind,variant_id)
 VALUES(t,p_event,p_session,p_kind,p_page,p_variant);
 RETURN p_event;
END $$;
-- Withdrawal remains available after entitlement is revoked. Erase event and source
-- data immediately; keep a bounded tombstone to prevent retry re-collection until purge.
CREATE FUNCTION web.withdraw_session(p_session uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=web.require_access('web.analytics.privacy',false);
BEGIN
 PERFORM web.lock_session(t,p_session);
 UPDATE web.visitor_sessions SET withdrawn_at=clock_timestamp(),source_code=NULL,medium_code=NULL,campaign_code=NULL,
 source_type='other',landing_kind='other' WHERE tenant_id=t AND session_id=p_session AND withdrawn_at IS NULL;
 DELETE FROM web.visit_events WHERE tenant_id=t AND session_id=p_session;
END $$;
CREATE FUNCTION web.purge_expired(p_limit integer DEFAULT 1000) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=web.require_access('web.analytics.privacy',false); n integer;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION 'Invalid purge limit' USING ERRCODE='22023'; END IF;
 WITH expired AS (SELECT session_id FROM web.visitor_sessions WHERE tenant_id=t AND retain_until<=clock_timestamp()
 ORDER BY retain_until,session_id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM web.visitor_sessions s USING expired e WHERE s.tenant_id=t AND s.session_id=e.session_id;
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY['web.start_session(uuid,boolean,boolean,text,text,text,text,text,text)'::regprocedure,
 'web.record_event(uuid,uuid,text,text,uuid)'::regprocedure,'web.withdraw_session(uuid)'::regprocedure,
 'web.purge_expired(integer)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_web_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_web_collector',f);
 END LOOP;
END $$;
CREATE VIEW web.daily_sources WITH(security_invoker=true) AS
 SELECT s.tenant_id,(s.started_at AT TIME ZONE 'UTC')::date AS visit_date,s.source_type,s.source_code,s.medium_code,s.campaign_code,
 count(DISTINCT s.session_id) AS sessions,count(e.event_id) AS events
 FROM web.visitor_sessions s LEFT JOIN web.visit_events e USING(tenant_id,session_id)
 GROUP BY s.tenant_id,(s.started_at AT TIME ZONE 'UTC')::date,s.source_type,s.source_code,s.medium_code,s.campaign_code;
GRANT SELECT ON web.daily_sources TO upc_runtime;
COMMIT;

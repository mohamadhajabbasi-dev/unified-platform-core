-- 0014: move existing web tables; extend one shared analytics model.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE SCHEMA analytics;
REVOKE ALL ON SCHEMA analytics FROM PUBLIC;
CREATE ROLE upc_app_collector NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO platform.modules(module_key,version_label) VALUES('app.analytics','0.1');
INSERT INTO iam.permissions VALUES
 ('app.analytics.read','Read own eligible app analytics'),
 ('app.analytics.collect','Collect consented app telemetry'),
 ('app.analytics.privacy','Withdraw and purge app telemetry'),
 ('app.registry.write','Manage own tenant app registry');
CREATE FUNCTION platform.app_eligible() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT platform.has_paid_entitlement('app.analytics') AND platform.module_enabled('app.analytics')
$$;
ALTER FUNCTION platform.app_eligible() OWNER TO upc_policy_reader;
REVOKE ALL ON FUNCTION platform.app_eligible() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION platform.app_eligible() TO upc_runtime,upc_web_executor;
GRANT USAGE ON SCHEMA analytics TO upc_runtime,upc_web_executor,upc_app_collector;
-- Tenant-owned application registry; shared cross-tenant distribution is deliberately deferred.
CREATE TABLE platform.applications (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 application_id uuid NOT NULL DEFAULT gen_random_uuid(),
 app_platform text NOT NULL CHECK(app_platform IN ('android','ios','windows')),
 package_key text NOT NULL CHECK(package_key ~ '^[A-Za-z0-9_.-]{1,200}$'),
 display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 1 AND 200),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,application_id), UNIQUE(tenant_id,app_platform,package_key)
);
CREATE TABLE platform.app_releases (
 tenant_id uuid NOT NULL,
 application_id uuid NOT NULL,
 release_id uuid NOT NULL DEFAULT gen_random_uuid(),
 version_label text NOT NULL CHECK(version_label ~ '^[A-Za-z0-9_.+-]{1,80}$'),
 build_key text NOT NULL CHECK(build_key ~ '^[A-Za-z0-9_.-]{1,80}$'),
 release_channel text NOT NULL CHECK(release_channel IN ('stable','beta','internal')),
 artifact_sha256 text CHECK(artifact_sha256 ~ '^[a-f0-9]{64}$'),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,application_id,release_id),
 UNIQUE(tenant_id,application_id,build_key,release_channel),
 FOREIGN KEY(tenant_id,application_id) REFERENCES platform.applications(tenant_id,application_id)
);
DO $$
DECLARE rel regclass;
BEGIN
 FOREACH rel IN ARRAY ARRAY['platform.applications'::regclass,'platform.app_releases'::regclass] LOOP
 EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
 EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
 EXECUTE format('CREATE POLICY app_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND platform.app_eligible() AND (iam.has_permission(''app.analytics.read'') OR iam.has_permission(''app.registry.write'')))',rel);
 EXECUTE format('CREATE POLICY app_insert ON %s FOR INSERT TO upc_runtime WITH CHECK(tenant_id=iam.current_tenant_id() AND platform.app_eligible() AND iam.has_permission(''app.registry.write''))',rel);
 EXECUTE format('CREATE POLICY app_update ON %s FOR UPDATE TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND platform.app_eligible() AND iam.has_permission(''app.registry.write'')) WITH CHECK(tenant_id=iam.current_tenant_id() AND platform.app_eligible() AND iam.has_permission(''app.registry.write''))',rel);
 EXECUTE format('CREATE POLICY app_executor_read ON %s FOR SELECT TO upc_web_executor USING(tenant_id=iam.current_tenant_id())',rel);
 END LOOP;
END $$;
GRANT SELECT,INSERT ON platform.applications,platform.app_releases TO upc_runtime;
GRANT UPDATE(display_name,is_active) ON platform.applications TO upc_runtime;
GRANT UPDATE(is_active) ON platform.app_releases TO upc_runtime;
GRANT SELECT ON platform.applications,platform.app_releases TO upc_web_executor;
CREATE TABLE analytics.app_installations (
 tenant_id uuid NOT NULL,
 application_id uuid NOT NULL,
 installation_id uuid NOT NULL,
 first_release_id uuid NOT NULL,
 consent_version text NOT NULL CHECK(consent_version ~ '^[a-zA-Z0-9_.-]{1,40}$'),
 first_open_at timestamptz NOT NULL,
 retain_until timestamptz NOT NULL CHECK(retain_until>first_open_at),
 withdrawn_at timestamptz CHECK(withdrawn_at>=first_open_at),
 PRIMARY KEY(tenant_id,application_id,installation_id),
 FOREIGN KEY(tenant_id,application_id,first_release_id) REFERENCES platform.app_releases(tenant_id,application_id,release_id)
);
CREATE INDEX app_install_retention_idx ON analytics.app_installations(tenant_id,retain_until);
ALTER TABLE analytics.app_installations ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.app_installations FORCE ROW LEVEL SECURITY;
CREATE POLICY install_read ON analytics.app_installations FOR SELECT TO upc_runtime USING(
 tenant_id=iam.current_tenant_id() AND platform.app_eligible() AND iam.has_permission('app.analytics.read')
 AND withdrawn_at IS NULL AND retain_until>statement_timestamp());
CREATE POLICY install_executor ON analytics.app_installations FOR ALL TO upc_web_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
GRANT SELECT ON analytics.app_installations TO upc_runtime;
GRANT SELECT,INSERT,DELETE ON analytics.app_installations TO upc_web_executor;
GRANT UPDATE(withdrawn_at) ON analytics.app_installations TO upc_web_executor;
ALTER TABLE web.visitor_sessions SET SCHEMA analytics;
ALTER TABLE analytics.visitor_sessions RENAME TO sessions;
ALTER TABLE web.visit_events SET SCHEMA analytics;
ALTER TABLE analytics.visit_events RENAME TO events;
ALTER TABLE analytics.sessions ADD COLUMN channel text NOT NULL DEFAULT 'web' CHECK(channel IN ('web','app'));
ALTER TABLE analytics.sessions ADD COLUMN application_id uuid;
ALTER TABLE analytics.sessions ADD COLUMN release_id uuid;
ALTER TABLE analytics.sessions ADD COLUMN installation_id uuid;
ALTER TABLE analytics.sessions ADD CHECK((channel='web' AND application_id IS NULL AND release_id IS NULL AND installation_id IS NULL)
 OR (channel='app' AND application_id IS NOT NULL AND release_id IS NOT NULL AND installation_id IS NOT NULL));
ALTER TABLE analytics.sessions ADD FOREIGN KEY(tenant_id,application_id,release_id) REFERENCES platform.app_releases(tenant_id,application_id,release_id);
ALTER TABLE analytics.sessions ADD FOREIGN KEY(tenant_id,application_id,installation_id) REFERENCES analytics.app_installations(tenant_id,application_id,installation_id) ON DELETE CASCADE;
CREATE INDEX sessions_install_idx ON analytics.sessions(tenant_id,application_id,installation_id);
ALTER TABLE analytics.events DROP CONSTRAINT visit_events_event_kind_check;
ALTER TABLE analytics.events ADD CHECK(event_kind IN ('page_view','product_view','cart_add','checkout_start','screen_view','search','notification_open','app_update'));
DROP POLICY sessions_read ON analytics.sessions;
CREATE POLICY sessions_read ON analytics.sessions FOR SELECT TO upc_runtime USING(
 tenant_id=iam.current_tenant_id() AND withdrawn_at IS NULL AND retain_until>statement_timestamp()
 AND ((channel='web' AND iam.has_permission('web.analytics.read') AND platform.commerce_eligible())
 OR (channel='app' AND iam.has_permission('app.analytics.read') AND platform.app_eligible())));
DROP POLICY events_read ON analytics.events;
CREATE POLICY events_read ON analytics.events FOR SELECT TO upc_runtime USING(
 tenant_id=iam.current_tenant_id() AND EXISTS(SELECT 1 FROM analytics.sessions s
 WHERE s.tenant_id=events.tenant_id AND s.session_id=events.session_id));
-- Same private writer, independent external capability for each channel.
CREATE FUNCTION analytics.require_channel(p_channel text,p_action text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR p_channel IS NULL OR p_channel NOT IN ('web','app') OR p_action NOT IN ('collect','privacy')
 OR NOT iam.has_permission(p_channel||'.analytics.'||p_action)
 OR (p_action='collect' AND NOT CASE WHEN p_channel='web' THEN platform.commerce_eligible() ELSE platform.app_eligible() END)
 THEN RAISE EXCEPTION 'Analytics access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 RETURN t;
END $$;
CREATE FUNCTION analytics.lock_install(p_tenant uuid,p_app uuid,p_install uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('analytics-install',p_tenant,p_app,p_install)::text,0))
$$;
ALTER FUNCTION analytics.require_channel(text,text) OWNER TO upc_web_executor;
ALTER FUNCTION analytics.lock_install(uuid,uuid,uuid) OWNER TO upc_web_executor;
REVOKE ALL ON FUNCTION analytics.require_channel(text,text),analytics.lock_install(uuid,uuid,uuid) FROM PUBLIC;
CREATE FUNCTION analytics.first_open(p_app uuid,p_release uuid,p_install uuid,p_consent boolean,p_version text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel('app','collect'); i analytics.app_installations%ROWTYPE; ts timestamptz;
BEGIN
 IF p_app IS NULL OR p_release IS NULL OR p_install IS NULL OR p_consent IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'Consented installation required' USING ERRCODE='42501'; END IF;
 PERFORM analytics.lock_install(t,p_app,p_install);
 SELECT * INTO i FROM analytics.app_installations WHERE tenant_id=t AND application_id=p_app AND installation_id=p_install;
 IF FOUND THEN
 IF i.withdrawn_at IS NOT NULL OR i.retain_until<=clock_timestamp() THEN RAISE EXCEPTION 'Installation inactive' USING ERRCODE='23514'; END IF;
 IF i.first_release_id<>p_release OR i.consent_version IS DISTINCT FROM p_version THEN RAISE EXCEPTION 'First open conflict' USING ERRCODE='23505'; END IF;
 RETURN p_install;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM platform.applications a JOIN platform.app_releases r USING(tenant_id,application_id)
 WHERE a.tenant_id=t AND a.application_id=p_app AND r.release_id=p_release AND a.is_active AND r.is_active)
 THEN RAISE EXCEPTION 'App release unavailable' USING ERRCODE='23503'; END IF;
 ts:=clock_timestamp();
 INSERT INTO analytics.app_installations(tenant_id,application_id,installation_id,first_release_id,consent_version,first_open_at,retain_until)
 VALUES(t,p_app,p_install,p_release,p_version,ts,ts+interval '30 days');
 RETURN p_install;
END $$;
CREATE FUNCTION analytics.start_session_internal(p_channel text,p_app uuid,p_release uuid,p_install uuid,p_session uuid,p_consent boolean,p_bot boolean,p_version text,p_source text,
 p_source_code text,p_medium text,p_campaign text,p_landing text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel(p_channel,'collect'); prior analytics.sessions%ROWTYPE; ts timestamptz; expiry timestamptz;
BEGIN
 IF p_session IS NULL OR p_consent IS DISTINCT FROM true OR p_bot IS DISTINCT FROM false
 THEN RAISE EXCEPTION 'Consented non-bot session required' USING ERRCODE='42501'; END IF;
 IF p_channel='app' THEN
  PERFORM analytics.lock_install(t,p_app,p_install);
  SELECT i.retain_until INTO expiry FROM analytics.app_installations i
   JOIN platform.applications a USING(tenant_id,application_id)
   JOIN platform.app_releases r ON r.tenant_id=i.tenant_id AND r.application_id=i.application_id
   WHERE i.tenant_id=t AND i.application_id=p_app AND i.installation_id=p_install
    AND i.withdrawn_at IS NULL AND i.retain_until>clock_timestamp()+interval '1 second'
    AND i.consent_version=p_version AND a.is_active AND r.release_id=p_release AND r.is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Active consented installation and release required' USING ERRCODE='23514'; END IF;
 END IF;
 PERFORM web.lock_session(t,p_session);
 SELECT * INTO prior FROM analytics.sessions WHERE tenant_id=t AND session_id=p_session;
 IF FOUND THEN
  IF prior.withdrawn_at IS NOT NULL OR prior.collection_until<=clock_timestamp()
  THEN RAISE EXCEPTION 'Session inactive' USING ERRCODE='23514'; END IF;
  IF prior.channel<>p_channel OR prior.application_id IS DISTINCT FROM p_app
  OR prior.release_id IS DISTINCT FROM p_release OR prior.installation_id IS DISTINCT FROM p_install
  OR prior.consent_version IS DISTINCT FROM p_version OR prior.source_type IS DISTINCT FROM p_source
  OR prior.source_code IS DISTINCT FROM p_source_code OR prior.medium_code IS DISTINCT FROM p_medium
  OR prior.campaign_code IS DISTINCT FROM p_campaign OR prior.landing_kind IS DISTINCT FROM p_landing
  THEN RAISE EXCEPTION 'Session idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN p_session;
 END IF;
 ts:=clock_timestamp();
 expiry:=COALESCE(expiry,ts+interval '30 days');
 INSERT INTO analytics.sessions(tenant_id,session_id,started_at,collection_until,retain_until,consent_version,source_type,source_code,medium_code,campaign_code,landing_kind,channel,application_id,release_id,installation_id)
 VALUES(t,p_session,ts,LEAST(ts+interval '24 hours',expiry-interval '1 microsecond'),expiry,p_version,p_source,p_source_code,p_medium,p_campaign,p_landing,p_channel,p_app,p_release,p_install);
 RETURN p_session;
END $$;

CREATE FUNCTION analytics.record_event_internal(p_channel text,p_event uuid,p_session uuid,p_kind text,p_page text,p_variant uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel(p_channel,'collect'); s analytics.sessions%ROWTYPE; e analytics.events%ROWTYPE;
BEGIN
 IF p_event IS NULL OR p_session IS NULL THEN RAISE EXCEPTION 'Event/session required' USING ERRCODE='22023'; END IF;
 PERFORM web.lock_session(t,p_session);
 SELECT * INTO s FROM analytics.sessions WHERE tenant_id=t AND session_id=p_session;
 IF NOT FOUND OR s.channel<>p_channel THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='23503'; END IF;
 IF s.withdrawn_at IS NOT NULL OR s.collection_until<=clock_timestamp()
 THEN RAISE EXCEPTION 'Session inactive' USING ERRCODE='23514'; END IF;
 IF p_channel='app' AND NOT EXISTS(SELECT 1 FROM platform.applications a JOIN platform.app_releases r USING(tenant_id,application_id)
 WHERE a.tenant_id=t AND a.application_id=s.application_id AND r.release_id=s.release_id AND a.is_active AND r.is_active)
 THEN RAISE EXCEPTION 'App or release disabled' USING ERRCODE='42501'; END IF;
 IF p_channel='web' AND p_kind IN ('screen_view','search','notification_open','app_update') THEN
  RAISE EXCEPTION 'App event requires app session' USING ERRCODE='22023'; END IF;
 -- Lock event key after session; duplicate requests do not increase counts.
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('web-event',t,p_event)::text,0));
 SELECT * INTO e FROM analytics.events WHERE tenant_id=t AND event_id=p_event;
 IF FOUND THEN
  IF e.session_id<>p_session OR e.event_kind IS DISTINCT FROM p_kind OR e.page_kind IS DISTINCT FROM p_page
  OR e.variant_id IS DISTINCT FROM p_variant THEN RAISE EXCEPTION 'Event idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN p_event;
 END IF;
 -- Hard per-session cap; global rate limiting and partitioning remain service/design tasks.
 IF (SELECT count(*) FROM analytics.events WHERE tenant_id=t AND session_id=p_session)>=500
 THEN RAISE EXCEPTION 'Session event limit' USING ERRCODE='23514'; END IF;
 INSERT INTO analytics.events(tenant_id,event_id,session_id,event_kind,page_kind,variant_id)
 VALUES(t,p_event,p_session,p_kind,p_page,p_variant);
 RETURN p_event;
END $$;

-- Existing web functions remain thin channel-specific wrappers, not alternate writers.
CREATE OR REPLACE FUNCTION web.start_session(p_session uuid,p_consent boolean,p_bot boolean,p_version text,p_source text,
 p_source_code text,p_medium text,p_campaign text,p_landing text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT analytics.start_session_internal('web',NULL,NULL,NULL,p_session,p_consent,p_bot,p_version,p_source,p_source_code,p_medium,p_campaign,p_landing)
$$;
CREATE OR REPLACE FUNCTION web.record_event(p_event uuid,p_session uuid,p_kind text,p_page text,p_variant uuid DEFAULT NULL) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT analytics.record_event_internal('web',p_event,p_session,p_kind,p_page,p_variant)
$$;
CREATE FUNCTION analytics.start_app_session(p_app uuid,p_release uuid,p_install uuid,p_session uuid,p_consent boolean,p_version text,
 p_source text,p_source_code text,p_medium text,p_campaign text,p_landing text) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT analytics.start_session_internal('app',p_app,p_release,p_install,p_session,p_consent,false,p_version,p_source,p_source_code,p_medium,p_campaign,p_landing)
$$;
CREATE FUNCTION analytics.record_app_event(p_event uuid,p_session uuid,p_kind text,p_page text,p_variant uuid DEFAULT NULL) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT analytics.record_event_internal('app',p_event,p_session,p_kind,p_page,p_variant)
$$;
-- Withdrawal of installation locks each session before deleting its data;
-- concurrent app session creation takes installation lock first.
CREATE FUNCTION analytics.withdraw_installation(p_app uuid,p_install uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel('app','privacy'); s uuid;
BEGIN
 PERFORM analytics.lock_install(t,p_app,p_install);
 FOR s IN SELECT session_id FROM analytics.sessions WHERE tenant_id=t AND application_id=p_app AND installation_id=p_install ORDER BY session_id LOOP
  PERFORM web.lock_session(t,s);
 END LOOP;
 UPDATE analytics.app_installations SET withdrawn_at=clock_timestamp()
 WHERE tenant_id=t AND application_id=p_app AND installation_id=p_install AND withdrawn_at IS NULL;
 DELETE FROM analytics.sessions WHERE tenant_id=t AND application_id=p_app AND installation_id=p_install;
END $$;
CREATE FUNCTION analytics.purge_expired_installations(p_limit integer DEFAULT 1000) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel('app','privacy'); n integer;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION 'Invalid purge limit' USING ERRCODE='22023'; END IF;
 WITH expired AS (SELECT application_id,installation_id FROM analytics.app_installations
 WHERE tenant_id=t AND retain_until<=clock_timestamp() ORDER BY retain_until,application_id,installation_id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM analytics.app_installations i USING expired e WHERE i.tenant_id=t AND i.application_id=e.application_id AND i.installation_id=e.installation_id;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
CREATE OR REPLACE FUNCTION web.withdraw_session(p_session uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel('web','privacy');
BEGIN
 PERFORM web.lock_session(t,p_session);
 UPDATE analytics.sessions SET withdrawn_at=clock_timestamp(),source_code=NULL,medium_code=NULL,campaign_code=NULL,
 source_type='other',landing_kind='other' WHERE tenant_id=t AND session_id=p_session AND channel='web' AND withdrawn_at IS NULL;
 DELETE FROM analytics.events e USING analytics.sessions s WHERE e.tenant_id=t AND e.session_id=p_session
 AND s.tenant_id=e.tenant_id AND s.session_id=e.session_id AND s.channel='web';
END $$;
CREATE OR REPLACE FUNCTION web.purge_expired(p_limit integer DEFAULT 1000) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=analytics.require_channel('web','privacy'); n integer;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION 'Invalid purge limit' USING ERRCODE='22023'; END IF;
 WITH expired AS (SELECT session_id FROM analytics.sessions WHERE tenant_id=t AND channel='web' AND retain_until<=clock_timestamp()
 ORDER BY retain_until,session_id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM analytics.sessions s USING expired e WHERE s.tenant_id=t AND s.session_id=e.session_id;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
DO $$
DECLARE f regprocedure;
BEGIN
 FOREACH f IN ARRAY ARRAY[
 'analytics.start_session_internal(text,uuid,uuid,uuid,uuid,boolean,boolean,text,text,text,text,text,text)'::regprocedure,
 'analytics.record_event_internal(text,uuid,uuid,text,text,uuid)'::regprocedure,
 'analytics.first_open(uuid,uuid,uuid,boolean,text)'::regprocedure,
 'analytics.start_app_session(uuid,uuid,uuid,uuid,boolean,text,text,text,text,text,text)'::regprocedure,
 'analytics.record_app_event(uuid,uuid,text,text,uuid)'::regprocedure,
 'analytics.withdraw_installation(uuid,uuid)'::regprocedure,'analytics.purge_expired_installations(integer)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_web_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION analytics.first_open(uuid,uuid,uuid,boolean,text),
 analytics.start_app_session(uuid,uuid,uuid,uuid,boolean,text,text,text,text,text,text),
 analytics.record_app_event(uuid,uuid,text,text,uuid),analytics.withdraw_installation(uuid,uuid),
 analytics.purge_expired_installations(integer) TO upc_app_collector;
CREATE OR REPLACE VIEW web.daily_sources WITH(security_invoker=true) AS
 SELECT s.tenant_id,(s.started_at AT TIME ZONE 'UTC')::date AS visit_date,s.source_type,s.source_code,s.medium_code,s.campaign_code,
 count(DISTINCT s.session_id) AS sessions,count(e.event_id) AS events
 FROM analytics.sessions s LEFT JOIN analytics.events e USING(tenant_id,session_id) WHERE s.channel='web'
 GROUP BY s.tenant_id,(s.started_at AT TIME ZONE 'UTC')::date,s.source_type,s.source_code,s.medium_code,s.campaign_code;
CREATE VIEW analytics.daily_activity WITH(security_invoker=true) AS
 SELECT tenant_id,channel,application_id,(started_at AT TIME ZONE 'UTC')::date AS activity_date,
 count(*) AS sessions,count(DISTINCT installation_id) AS active_installations
 FROM analytics.sessions GROUP BY tenant_id,channel,application_id,(started_at AT TIME ZONE 'UTC')::date;
CREATE VIEW analytics.daily_first_opens WITH(security_invoker=true) AS
 SELECT tenant_id,application_id,first_release_id,(first_open_at AT TIME ZONE 'UTC')::date AS first_open_date,count(*) AS first_opens
 FROM analytics.app_installations GROUP BY tenant_id,application_id,first_release_id,(first_open_at AT TIME ZONE 'UTC')::date;
GRANT SELECT ON analytics.daily_activity,analytics.daily_first_opens TO upc_runtime;
COMMIT;

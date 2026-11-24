-- 0016: consented acquisition and order attribution; no duplicate customer or order.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE ROLE upc_attribution_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_attribution_verifier NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions VALUES ('crm.attribution.read','Read permitted retained acquisition evidence'),
 ('crm.attribution.write','Link independently authenticated customer and acquisition evidence'),
 ('crm.attribution.privacy','Purge expired attribution evidence');
ALTER TABLE crm.customer_consent_events ADD UNIQUE(tenant_id,customer_id,consent_event_id);
ALTER TABLE sales.orders ADD UNIQUE(tenant_id,order_id,customer_id);
CREATE TABLE crm.customer_acquisition_events (
 tenant_id uuid NOT NULL,
 acquisition_id uuid NOT NULL DEFAULT gen_random_uuid(),
 customer_id uuid NOT NULL,
 consent_event_id uuid NOT NULL,
 session_id uuid,
 channel text NOT NULL CHECK(channel IN ('web','app','in_person','phone')),
 evidence_digest bytea NOT NULL CHECK(octet_length(evidence_digest)=32),
 touched_at timestamptz NOT NULL,
 linked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 retain_until timestamptz NOT NULL CHECK(retain_until>touched_at),
 linked_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,acquisition_id),
 UNIQUE(tenant_id,acquisition_id,customer_id),
 UNIQUE(tenant_id,evidence_digest),
 UNIQUE(tenant_id,session_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id),
 FOREIGN KEY(tenant_id,customer_id,consent_event_id) REFERENCES crm.customer_consent_events(tenant_id,customer_id,consent_event_id),
 FOREIGN KEY(tenant_id,session_id) REFERENCES analytics.sessions(tenant_id,session_id) ON DELETE CASCADE,
 CHECK((session_id IS NOT NULL)=(channel IN ('web','app'))),
 CHECK(linked_at>=touched_at)
);
CREATE INDEX acquisition_customer_time_idx ON crm.customer_acquisition_events(tenant_id,customer_id,touched_at,acquisition_id);
CREATE INDEX acquisition_retention_idx ON crm.customer_acquisition_events(tenant_id,retain_until);
CREATE TABLE sales.order_attribution (
 tenant_id uuid NOT NULL,
 order_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 acquisition_id uuid NOT NULL,
 attributed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 attributed_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,order_id),
 FOREIGN KEY(tenant_id,order_id,customer_id) REFERENCES sales.orders(tenant_id,order_id,customer_id),
 FOREIGN KEY(tenant_id,acquisition_id,customer_id) REFERENCES crm.customer_acquisition_events(tenant_id,acquisition_id,customer_id) ON DELETE CASCADE
);
CREATE INDEX order_attribution_touch_idx ON sales.order_attribution(tenant_id,acquisition_id);
ALTER TABLE crm.customer_acquisition_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.customer_acquisition_events FORCE ROW LEVEL SECURITY;
ALTER TABLE sales.order_attribution ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales.order_attribution FORCE ROW LEVEL SECURITY;
CREATE POLICY acquisition_read ON crm.customer_acquisition_events FOR SELECT TO upc_runtime USING(
 tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.attribution.read') AND platform.module_enabled('crm')
 AND retain_until>statement_timestamp() AND (session_id IS NULL OR EXISTS(SELECT 1 FROM analytics.sessions s
 WHERE s.tenant_id=customer_acquisition_events.tenant_id AND s.session_id=customer_acquisition_events.session_id)));
CREATE POLICY order_attribution_read ON sales.order_attribution FOR SELECT TO upc_runtime USING(
 tenant_id=iam.current_tenant_id() AND iam.has_permission('sales.read') AND platform.module_enabled('sales')
 AND EXISTS(SELECT 1 FROM crm.customer_acquisition_events a WHERE a.tenant_id=order_attribution.tenant_id AND a.acquisition_id=order_attribution.acquisition_id));
CREATE POLICY acquisition_private ON crm.customer_acquisition_events FOR ALL TO upc_attribution_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY order_attribution_private ON sales.order_attribution FOR ALL TO upc_attribution_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY attribution_consent_dependency ON crm.customer_consent_events FOR SELECT TO upc_attribution_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY attribution_session_dependency ON analytics.sessions FOR SELECT TO upc_attribution_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY attribution_order_dependency ON sales.orders FOR SELECT TO upc_attribution_executor USING(tenant_id=iam.current_tenant_id());
GRANT USAGE ON SCHEMA iam,platform,crm,sales,analytics TO upc_attribution_executor;
GRANT USAGE ON SCHEMA crm,sales TO upc_attribution_verifier;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),
 platform.module_enabled(text),platform.commerce_eligible(),platform.app_eligible() TO upc_attribution_executor;
GRANT SELECT(tenant_id,customer_id,verified_at,revoked_at) ON crm.customer_identifiers TO upc_attribution_executor;
GRANT SELECT ON crm.customer_consent_events,analytics.sessions,sales.orders TO upc_attribution_executor;
GRANT SELECT,INSERT,DELETE ON crm.customer_acquisition_events TO upc_attribution_executor;
GRANT SELECT,INSERT ON sales.order_attribution TO upc_attribution_executor;
GRANT SELECT ON crm.customer_acquisition_events,sales.order_attribution TO upc_runtime;
CREATE FUNCTION crm.lock_acquisition_customer(p_tenant uuid,p_customer uuid) RETURNS void
LANGUAGE sql SET search_path=pg_catalog AS $$
 SELECT pg_advisory_xact_lock(hashtextextended(jsonb_build_array('acquisition-customer',p_tenant,p_customer)::text,0))
$$;
ALTER FUNCTION crm.lock_acquisition_customer(uuid,uuid) OWNER TO upc_attribution_executor;
REVOKE ALL ON FUNCTION crm.lock_acquisition_customer(uuid,uuid) FROM PUBLIC;
-- Consent is append-only; serialize analytics consent changes with new links.
-- Revocation erases attribution relationships, not financial orders or customers.
CREATE FUNCTION crm.guard_analytics_consent() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.purpose<>'analytics' THEN RETURN NEW; END IF;
 IF NEW.tenant_id IS DISTINCT FROM iam.current_tenant_id() OR current_setting('transaction_isolation')<>'read committed'
 THEN RAISE EXCEPTION 'Mapped READ COMMITTED consent writer required' USING ERRCODE='42501'; END IF;
 PERFORM crm.lock_acquisition_customer(NEW.tenant_id,NEW.customer_id);
 NEW.observed_at:=clock_timestamp();
 IF NOT NEW.granted THEN
  DELETE FROM crm.customer_acquisition_events WHERE tenant_id=NEW.tenant_id AND customer_id=NEW.customer_id;
 END IF;
 RETURN NEW;
END $$;
ALTER FUNCTION crm.guard_analytics_consent() OWNER TO upc_attribution_executor;
REVOKE ALL ON FUNCTION crm.guard_analytics_consent() FROM PUBLIC;
CREATE TRIGGER analytics_consent_gate BEFORE INSERT ON crm.customer_consent_events FOR EACH ROW EXECUTE FUNCTION crm.guard_analytics_consent();
CREATE FUNCTION crm.erase_withdrawn_session_links() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF NEW.withdrawn_at IS NOT NULL AND OLD.withdrawn_at IS NULL THEN
  DELETE FROM crm.customer_acquisition_events WHERE tenant_id=NEW.tenant_id AND session_id=NEW.session_id;
 END IF;
 RETURN NULL;
END $$;
ALTER FUNCTION crm.erase_withdrawn_session_links() OWNER TO upc_attribution_executor;
REVOKE ALL ON FUNCTION crm.erase_withdrawn_session_links() FROM PUBLIC;
CREATE TRIGGER session_withdraw_attribution AFTER UPDATE OF withdrawn_at ON analytics.sessions FOR EACH ROW EXECUTE FUNCTION crm.erase_withdrawn_session_links();
CREATE FUNCTION crm.attribution_context(p_permission text) RETURNS uuid
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission(p_permission) OR (p_permission<>'crm.attribution.privacy' AND NOT platform.module_enabled('crm'))
 THEN RAISE EXCEPTION 'Attribution access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 RETURN t;
END $$;
ALTER FUNCTION crm.attribution_context(text) OWNER TO upc_attribution_executor;
REVOKE ALL ON FUNCTION crm.attribution_context(text) FROM PUBLIC;
CREATE FUNCTION crm.channel_attribution_enabled(p_channel text) RETURNS boolean LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT CASE p_channel WHEN 'web' THEN platform.commerce_eligible() WHEN 'app' THEN platform.app_eligible()
 WHEN 'in_person' THEN true WHEN 'phone' THEN true ELSE false END
$$;
ALTER FUNCTION crm.channel_attribution_enabled(text) OWNER TO upc_attribution_executor;
REVOKE ALL ON FUNCTION crm.channel_attribution_enabled(text) FROM PUBLIC;
-- The trusted verifier must independently authenticate the customer/session relationship,
-- not merely accept a customer UUID from a browser. SQL checks existing verified identity
-- and current consent; it never creates a customer from a visitor.
CREATE FUNCTION crm.record_acquisition(p_customer uuid,p_channel text,p_session uuid,p_evidence bytea) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=crm.attribution_context('crm.attribution.write'); c crm.customer_consent_events%ROWTYPE;
 s analytics.sessions%ROWTYPE; prior crm.customer_acquisition_events%ROWTYPE; aid uuid; touched timestamptz; expiry timestamptz;
BEGIN
 IF p_customer IS NULL OR p_channel IS NULL OR p_channel NOT IN ('web','app','in_person','phone')
 OR (p_session IS NOT NULL)<>(p_channel IN ('web','app')) OR p_evidence IS NULL OR octet_length(p_evidence)<>32
 THEN RAISE EXCEPTION 'Invalid acquisition evidence' USING ERRCODE='22023'; END IF;
 IF NOT crm.channel_attribution_enabled(p_channel) THEN RAISE EXCEPTION 'Channel not eligible' USING ERRCODE='42501'; END IF;
 PERFORM crm.lock_acquisition_customer(t,p_customer);
 IF NOT EXISTS(SELECT 1 FROM crm.customer_identifiers WHERE tenant_id=t AND customer_id=p_customer AND verified_at<=clock_timestamp() AND revoked_at IS NULL)
 THEN RAISE EXCEPTION 'Verified customer required' USING ERRCODE='23503'; END IF;
 SELECT * INTO c FROM crm.customer_consent_events WHERE tenant_id=t AND customer_id=p_customer AND purpose='analytics'
 AND observed_at<=clock_timestamp() ORDER BY observed_at DESC,granted ASC,consent_event_id LIMIT 1;
 IF NOT FOUND OR NOT c.granted THEN RAISE EXCEPTION 'Current customer analytics consent required' USING ERRCODE='42501'; END IF;
 IF p_session IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('web-session',t,p_session)::text,0));
  SELECT * INTO s FROM analytics.sessions WHERE tenant_id=t AND session_id=p_session;
  IF NOT FOUND OR s.channel<>p_channel THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='23503'; END IF;
  IF s.withdrawn_at IS NOT NULL OR s.retain_until<=clock_timestamp() THEN RAISE EXCEPTION 'Session unavailable for attribution' USING ERRCODE='23514'; END IF;
  touched:=s.started_at; expiry:=s.retain_until;
 ELSE
  touched:=clock_timestamp(); expiry:=touched+interval '30 days';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('acquisition-evidence',t,encode(p_evidence,'hex'))::text,0));
 SELECT * INTO prior FROM crm.customer_acquisition_events WHERE tenant_id=t AND evidence_digest=p_evidence;
 IF FOUND THEN
  IF prior.customer_id<>p_customer OR prior.channel<>p_channel OR prior.session_id IS DISTINCT FROM p_session
  THEN RAISE EXCEPTION 'Acquisition evidence conflict' USING ERRCODE='23505'; END IF;
  IF prior.retain_until<=clock_timestamp() THEN RAISE EXCEPTION 'Acquisition expired' USING ERRCODE='23514'; END IF;
  RETURN prior.acquisition_id;
 END IF;
 IF p_session IS NOT NULL AND EXISTS(SELECT 1 FROM crm.customer_acquisition_events WHERE tenant_id=t AND session_id=p_session)
 THEN RAISE EXCEPTION 'Session already attributed' USING ERRCODE='23505'; END IF;
 INSERT INTO crm.customer_acquisition_events(tenant_id,customer_id,consent_event_id,session_id,channel,evidence_digest,touched_at,retain_until,linked_by)
 VALUES(t,p_customer,c.consent_event_id,p_session,p_channel,p_evidence,touched,expiry,iam.current_user_id()) RETURNING acquisition_id INTO aid;
 RETURN aid;
END $$;
-- Deterministic last retained touch in order channel, linked no later than checkout.
-- Historical attribution cannot be rewritten; privacy erasure deliberately removes it.
CREATE FUNCTION sales.attribute_order(p_order uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=crm.attribution_context('crm.attribution.write'); o sales.orders%ROWTYPE; aid uuid; chosen crm.customer_acquisition_events%ROWTYPE;
BEGIN
 IF NOT platform.module_enabled('sales') OR NOT iam.has_permission('sales.read') THEN RAISE EXCEPTION 'Sales access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO o FROM sales.orders WHERE tenant_id=t AND order_id=p_order;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order unavailable' USING ERRCODE='23503'; END IF;
 IF NOT crm.channel_attribution_enabled(o.channel) THEN RAISE EXCEPTION 'Order channel not eligible' USING ERRCODE='42501'; END IF;
 PERFORM crm.lock_acquisition_customer(t,o.customer_id);
 SELECT acquisition_id INTO aid FROM sales.order_attribution WHERE tenant_id=t AND order_id=p_order;
 IF FOUND THEN RETURN aid; END IF;
 SELECT a.* INTO chosen FROM crm.customer_acquisition_events a
 WHERE a.tenant_id=t AND a.customer_id=o.customer_id AND a.channel=o.channel
 AND a.touched_at<=o.created_at AND a.linked_at<=o.created_at AND a.retain_until>clock_timestamp()
 ORDER BY a.touched_at DESC,a.acquisition_id LIMIT 1;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF chosen.session_id IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('web-session',t,chosen.session_id)::text,0));
  IF NOT EXISTS(SELECT 1 FROM crm.customer_acquisition_events WHERE tenant_id=t AND acquisition_id=chosen.acquisition_id AND retain_until>clock_timestamp())
  OR NOT EXISTS(SELECT 1 FROM analytics.sessions WHERE tenant_id=t AND session_id=chosen.session_id AND withdrawn_at IS NULL AND retain_until>clock_timestamp()) THEN RETURN NULL; END IF;
 END IF;
 INSERT INTO sales.order_attribution(tenant_id,order_id,customer_id,acquisition_id,attributed_by)
 VALUES(t,p_order,o.customer_id,chosen.acquisition_id,iam.current_user_id());
 RETURN chosen.acquisition_id;
END $$;
CREATE FUNCTION crm.purge_expired_acquisition(p_limit integer DEFAULT 1000) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=crm.attribution_context('crm.attribution.privacy'); n integer;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION 'Invalid limit' USING ERRCODE='22023'; END IF;
 WITH expired AS (SELECT acquisition_id FROM crm.customer_acquisition_events WHERE tenant_id=t AND retain_until<=clock_timestamp()
 ORDER BY retain_until,acquisition_id LIMIT p_limit FOR UPDATE SKIP LOCKED)
 DELETE FROM crm.customer_acquisition_events a USING expired e WHERE a.tenant_id=t AND a.acquisition_id=e.acquisition_id;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;
DO $$ DECLARE f regprocedure; BEGIN
 FOREACH f IN ARRAY ARRAY['crm.record_acquisition(uuid,text,uuid,bytea)'::regprocedure,'sales.attribute_order(uuid)'::regprocedure,'crm.purge_expired_acquisition(integer)'::regprocedure] LOOP
 EXECUTE format('ALTER FUNCTION %s OWNER TO upc_attribution_executor',f);
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO upc_attribution_verifier',f);
 END LOOP;
END $$;
CREATE VIEW crm.acquisition_sources WITH(security_invoker=true) AS
 SELECT a.tenant_id,a.acquisition_id,a.customer_id,a.channel,a.touched_at,a.retain_until,
 COALESCE(s.source_type,'other') AS source_type,s.source_code,s.medium_code,s.campaign_code
 FROM crm.customer_acquisition_events a LEFT JOIN analytics.sessions s USING(tenant_id,session_id);
CREATE VIEW crm.first_retained_acquisition WITH(security_invoker=true) AS
 SELECT DISTINCT ON(tenant_id,customer_id) * FROM crm.acquisition_sources
 ORDER BY tenant_id,customer_id,touched_at,acquisition_id;
GRANT SELECT ON crm.acquisition_sources,crm.first_retained_acquisition TO upc_runtime;
COMMIT;

-- 0015: official distribution aggregates, distinct from installation telemetry.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_distribution_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_distribution_importer NOLOGIN NOSUPERUSER NOBYPASSRLS;
INSERT INTO iam.permissions VALUES ('app.distribution.import','Import independently verified distribution aggregates');
CREATE TABLE analytics.app_distribution_reports (
 tenant_id uuid NOT NULL,
 report_id uuid NOT NULL DEFAULT gen_random_uuid(),
 application_id uuid NOT NULL,
 release_id uuid,
 source text NOT NULL CHECK(source IN ('cafebazaar','myket','google_play','app_store','website','microsoft_store')),
 report_day date NOT NULL CHECK(isfinite(report_day)),
 report_timezone text NOT NULL CHECK(length(report_timezone) BETWEEN 1 AND 100),
 metric text NOT NULL CHECK(metric IN ('store_page_views','downloads','provider_installs','provider_updates')),
 native_metric_key text NOT NULL CHECK(native_metric_key ~ '^[A-Za-z0-9_.-]{1,100}$'),
 revision integer NOT NULL CHECK(revision>0),
 metric_count bigint CHECK(metric_count>=0),
 unknown_reason text CHECK(unknown_reason IN ('not_available','not_reported','suppressed','delayed')),
 report_digest bytea NOT NULL CHECK(octet_length(report_digest)=32),
 source_report_ref text NOT NULL CHECK(source_report_ref ~ '^[A-Za-z0-9_.:-]{1,160}$'),
 imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 imported_by uuid NOT NULL REFERENCES core.users(user_id),
 PRIMARY KEY(tenant_id,report_id),
 UNIQUE NULLS NOT DISTINCT(tenant_id,application_id,release_id,source,report_day,metric,revision),
 FOREIGN KEY(tenant_id,application_id) REFERENCES platform.applications(tenant_id,application_id),
 FOREIGN KEY(tenant_id,application_id,release_id) REFERENCES platform.app_releases(tenant_id,application_id,release_id),
 CHECK((metric_count IS NULL)<>(unknown_reason IS NULL))
);
CREATE INDEX distribution_lookup_idx ON analytics.app_distribution_reports(tenant_id,application_id,source,report_day,metric,revision DESC);
ALTER TABLE analytics.app_distribution_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics.app_distribution_reports FORCE ROW LEVEL SECURITY;
CREATE POLICY distribution_read ON analytics.app_distribution_reports FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('app.analytics.read') AND platform.app_eligible());
CREATE POLICY distribution_private ON analytics.app_distribution_reports FOR ALL TO upc_distribution_executor
 USING(tenant_id=iam.current_tenant_id()) WITH CHECK(tenant_id=iam.current_tenant_id());
CREATE POLICY distribution_app_read ON platform.applications FOR SELECT TO upc_distribution_executor USING(tenant_id=iam.current_tenant_id());
CREATE POLICY distribution_release_read ON platform.app_releases FOR SELECT TO upc_distribution_executor USING(tenant_id=iam.current_tenant_id());
GRANT USAGE ON SCHEMA analytics,iam,platform TO upc_distribution_executor;
GRANT USAGE ON SCHEMA analytics TO upc_distribution_importer;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.current_user_id(),iam.has_permission(text),platform.app_eligible() TO upc_distribution_executor;
GRANT SELECT ON platform.applications,platform.app_releases TO upc_distribution_executor;
GRANT SELECT,INSERT ON analytics.app_distribution_reports TO upc_distribution_executor;
GRANT SELECT ON analytics.app_distribution_reports TO upc_runtime;
-- Trusted importer validates provider provenance and exact tenant ownership outside SQL.
-- An observed count is not proof of download authenticity on its own.
CREATE FUNCTION analytics.import_distribution_report(p_app uuid,p_release uuid,p_source text,p_day date,p_zone text,
 p_metric text,p_native text,p_revision integer,p_count bigint,p_unknown text,p_digest bytea,p_ref text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); u uuid:=iam.current_user_id(); app_kind text;
 prior analytics.app_distribution_reports%ROWTYPE; rid uuid;
BEGIN
 IF t IS NULL OR u IS NULL OR NOT iam.has_permission('app.distribution.import') OR NOT platform.app_eligible()
 THEN RAISE EXCEPTION 'Distribution import denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_app IS NULL OR p_source IS NULL OR p_day IS NULL OR NOT isfinite(p_day) OR p_zone IS NULL
 OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_zone)
 OR p_metric IS NULL OR p_native IS NULL OR p_revision IS NULL OR p_revision<1
 OR (p_count IS NULL)=(p_unknown IS NULL) OR p_count<0 OR p_digest IS NULL OR octet_length(p_digest)<>32 OR p_ref IS NULL
 THEN RAISE EXCEPTION 'Invalid distribution report' USING ERRCODE='22023'; END IF;
 IF p_day>(clock_timestamp() AT TIME ZONE p_zone)::date THEN RAISE EXCEPTION 'Future report day' USING ERRCODE='22023'; END IF;
 SELECT app_platform INTO app_kind FROM platform.applications WHERE tenant_id=t AND application_id=p_app;
 IF NOT FOUND OR (p_release IS NOT NULL AND NOT EXISTS(SELECT 1 FROM platform.app_releases
 WHERE tenant_id=t AND application_id=p_app AND release_id=p_release))
 THEN RAISE EXCEPTION 'App or release unavailable' USING ERRCODE='23503'; END IF;
 IF NOT (p_source='website' OR (app_kind='android' AND p_source IN ('cafebazaar','myket','google_play'))
 OR (app_kind='ios' AND p_source='app_store') OR (app_kind='windows' AND p_source='microsoft_store'))
 THEN RAISE EXCEPTION 'Source incompatible with app platform' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('distribution',t,p_app,p_release,p_source,p_day,p_metric)::text,0));
 SELECT * INTO prior FROM analytics.app_distribution_reports
 WHERE tenant_id=t AND application_id=p_app AND release_id IS NOT DISTINCT FROM p_release
 AND source=p_source AND report_day=p_day AND metric=p_metric AND revision=p_revision;
 IF FOUND THEN
  IF prior.report_timezone<>p_zone OR prior.native_metric_key<>p_native OR prior.metric_count IS DISTINCT FROM p_count
  OR prior.unknown_reason IS DISTINCT FROM p_unknown OR prior.report_digest<>p_digest OR prior.source_report_ref<>p_ref
  THEN RAISE EXCEPTION 'Distribution report idempotency conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.report_id;
 END IF;
 SELECT * INTO prior FROM analytics.app_distribution_reports
 WHERE tenant_id=t AND application_id=p_app AND release_id IS NOT DISTINCT FROM p_release
 AND source=p_source AND report_day=p_day AND metric=p_metric ORDER BY revision DESC LIMIT 1;
 IF FOUND THEN
  IF p_revision<>prior.revision+1 OR p_zone<>prior.report_timezone OR p_native<>prior.native_metric_key
  THEN RAISE EXCEPTION 'Report revision or metric definition conflict' USING ERRCODE='23514'; END IF;
 ELSE
  IF p_revision<>1 THEN RAISE EXCEPTION 'First report revision must be one' USING ERRCODE='23514'; END IF;
 END IF;
 INSERT INTO analytics.app_distribution_reports(tenant_id,application_id,release_id,source,report_day,report_timezone,
 metric,native_metric_key,revision,metric_count,unknown_reason,report_digest,source_report_ref,imported_by)
 VALUES(t,p_app,p_release,p_source,p_day,p_zone,p_metric,p_native,p_revision,p_count,p_unknown,p_digest,p_ref,u)
 RETURNING report_id INTO rid;
 RETURN rid;
END $$;
ALTER FUNCTION analytics.import_distribution_report(uuid,uuid,text,date,text,text,text,integer,bigint,text,bytea,text) OWNER TO upc_distribution_executor;
REVOKE ALL ON FUNCTION analytics.import_distribution_report(uuid,uuid,text,date,text,text,text,integer,bigint,text,bytea,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION analytics.import_distribution_report(uuid,uuid,text,date,text,text,text,integer,bigint,text,bytea,text) TO upc_distribution_importer;
-- No sum across sources or app-total and release-detail scopes. Latest revision only.
-- A missing row is also unknown, not zero; caller must show missing coverage explicitly.
CREATE VIEW analytics.distribution_latest WITH(security_invoker=true) AS
 SELECT DISTINCT ON(tenant_id,application_id,release_id,source,report_day,metric)
 tenant_id,application_id,release_id,source,report_day,report_timezone,metric,native_metric_key,revision,metric_count,
 CASE WHEN metric_count IS NULL THEN 'unknown' ELSE 'reported' END AS status,unknown_reason,report_digest,source_report_ref,imported_at
 FROM analytics.app_distribution_reports
 ORDER BY tenant_id,application_id,release_id,source,report_day,metric,revision DESC;
GRANT SELECT ON analytics.distribution_latest TO upc_runtime;
COMMIT;

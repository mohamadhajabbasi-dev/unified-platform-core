-- 0078: transactional internal price-entry change facts, no delivery or external consumer.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
CREATE ROLE upc_outbox_capture NOLOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB;
CREATE TABLE ops.outbox_events (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 event_id uuid NOT NULL DEFAULT gen_random_uuid(),
 event_kind text NOT NULL CHECK(event_kind='catalog.price_entry.changed'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,event_id)
);
CREATE INDEX outbox_tenant_time_idx ON ops.outbox_events(tenant_id,recorded_at,event_id);
ALTER TABLE ops.outbox_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.outbox_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.outbox_events FROM PUBLIC,upc_runtime,upc_platform_approver;
GRANT USAGE ON SCHEMA ops,catalog,iam TO upc_outbox_capture;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id() TO upc_outbox_capture;
GRANT INSERT(tenant_id,event_kind) ON ops.outbox_events TO upc_outbox_capture;
-- postgres exception is solely for the disposable CI bootstrap/fixture owner.
CREATE POLICY outbox_capture_insert ON ops.outbox_events FOR INSERT TO upc_outbox_capture
 WITH CHECK(tenant_id=iam.current_tenant_id() OR session_user='postgres');
CREATE FUNCTION ops.capture_price_entry_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_RELID<>'catalog.price_entries'::regclass OR TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' THEN
  RAISE EXCEPTION 'Invalid outbox trigger source' USING ERRCODE='42501';
 END IF;
 IF TG_OP='UPDATE' THEN
  IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NULL; END IF;
  IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
   INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(OLD.tenant_id,'catalog.price_entry.changed');
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN
  INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(OLD.tenant_id,'catalog.price_entry.changed');
 ELSE
  INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(NEW.tenant_id,'catalog.price_entry.changed');
 END IF;
 RETURN NULL;
END $$;
ALTER FUNCTION ops.capture_price_entry_change() OWNER TO upc_outbox_capture;
REVOKE ALL ON FUNCTION ops.capture_price_entry_change() FROM PUBLIC,upc_runtime,upc_platform_approver;
CREATE TRIGGER price_entry_outbox AFTER INSERT OR UPDATE OR DELETE ON catalog.price_entries
 FOR EACH ROW EXECUTE FUNCTION ops.capture_price_entry_change();
COMMIT;

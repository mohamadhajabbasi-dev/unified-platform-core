-- 0064: canonical service queue identity and nullable ticket assignment.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES ('crm.queues.write','Register service queues and assign existing tickets');
CREATE ROLE upc_queue_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE crm.service_queues (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 queue_id uuid NOT NULL DEFAULT gen_random_uuid(),
 queue_key text NOT NULL CHECK(queue_key ~ '^[a-z0-9][a-z0-9_.-]{0,79}$'),
 display_name text NOT NULL CHECK(length(display_name) BETWEEN 1 AND 120 AND display_name ~ '[^[:space:]]'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,queue_id),
 UNIQUE(tenant_id,queue_key)
);
CREATE UNIQUE INDEX service_queues_name_uq ON crm.service_queues(tenant_id,lower(btrim(display_name)));
ALTER TABLE crm.service_queues ENABLE ROW LEVEL SECURITY;
ALTER TABLE crm.service_queues FORCE ROW LEVEL SECURITY;
REVOKE ALL ON crm.service_queues FROM PUBLIC;
CREATE POLICY queue_read ON crm.service_queues FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND platform.module_enabled('crm'));
CREATE POLICY queue_executor_read ON crm.service_queues FOR SELECT TO upc_queue_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.queues.write') AND platform.module_enabled('crm'));
CREATE POLICY queue_executor_insert ON crm.service_queues FOR INSERT TO upc_queue_executor WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.queues.write') AND platform.module_enabled('crm'));
GRANT SELECT ON crm.service_queues TO upc_runtime,upc_queue_executor;
GRANT INSERT(tenant_id,queue_key,display_name) ON crm.service_queues TO upc_queue_executor;
ALTER TABLE crm.support_tickets ADD COLUMN queue_id uuid,
 ADD FOREIGN KEY(tenant_id,queue_id) REFERENCES crm.service_queues(tenant_id,queue_id);
CREATE INDEX support_tickets_queue_idx ON crm.support_tickets(tenant_id,queue_id,state,priority,created_at) WHERE queue_id IS NOT NULL;
-- Preserve every original insert column, but not the newly added queue_id.
REVOKE INSERT ON crm.support_tickets FROM upc_runtime;
GRANT INSERT(tenant_id,ticket_id,ticket_key,customer_id,conversation_id,assigned_user_id,subject,priority,state,created_at,resolved_at)
 ON crm.support_tickets TO upc_runtime;
GRANT USAGE ON SCHEMA crm,iam,platform TO upc_queue_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text),platform.module_enabled(text) TO upc_queue_executor;
GRANT SELECT(tenant_id,ticket_id,queue_id),UPDATE(queue_id) ON crm.support_tickets TO upc_queue_executor;
CREATE POLICY queue_ticket_read ON crm.support_tickets FOR SELECT TO upc_queue_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.queues.write') AND platform.module_enabled('crm'));
CREATE POLICY queue_ticket_update ON crm.support_tickets FOR UPDATE TO upc_queue_executor USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.queues.write') AND platform.module_enabled('crm')) WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('crm.engagement.read') AND iam.has_permission('crm.engagement.write') AND iam.has_permission('crm.queues.write') AND platform.module_enabled('crm'));
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 -- Bootstrap/maintenance must later use a separate audited provisioning path.
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;
CREATE TRIGGER service_queue_audit AFTER INSERT ON crm.service_queues FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE TRIGGER ticket_queue_audit AFTER UPDATE OF queue_id ON crm.support_tickets FOR EACH ROW
 WHEN (OLD.queue_id IS DISTINCT FROM NEW.queue_id) EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION crm.register_service_queue(p_key text,p_name text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior crm.service_queues%ROWTYPE; q uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.queues.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Queue access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_key IS NULL OR p_key !~ '^[a-z0-9][a-z0-9_.-]{0,79}$' OR p_name IS NULL OR length(p_name) NOT BETWEEN 1 AND 120 OR p_name !~ '[^[:space:]]'
 THEN RAISE EXCEPTION 'Invalid queue metadata' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('crm-service-queue',t,p_key)::text,0));
 IF t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.queues.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Queue access denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM crm.service_queues WHERE tenant_id=t AND queue_key=p_key;
 IF FOUND THEN
  IF prior.display_name IS DISTINCT FROM p_name THEN RAISE EXCEPTION 'Queue key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.queue_id;
 END IF;
 INSERT INTO crm.service_queues(tenant_id,queue_key,display_name) VALUES(t,p_key,p_name) RETURNING queue_id INTO q;
 RETURN q;
END $$;
CREATE FUNCTION crm.set_ticket_queue(p_ticket uuid,p_queue uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.queues.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Queue access denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_ticket IS NULL THEN RAISE EXCEPTION 'Ticket required' USING ERRCODE='22023'; END IF;
 SELECT queue_id INTO prior FROM crm.support_tickets WHERE tenant_id=t AND ticket_id=p_ticket FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Ticket or queue unavailable' USING ERRCODE='23503'; END IF;
 IF t IS NULL OR NOT iam.has_permission('crm.engagement.read') OR NOT iam.has_permission('crm.engagement.write') OR NOT iam.has_permission('crm.queues.write') OR NOT platform.module_enabled('crm') THEN RAISE EXCEPTION 'Queue access denied' USING ERRCODE='42501'; END IF;
 IF p_queue IS NOT NULL AND NOT EXISTS(SELECT 1 FROM crm.service_queues WHERE tenant_id=t AND queue_id=p_queue)
 THEN RAISE EXCEPTION 'Ticket or queue unavailable' USING ERRCODE='23503'; END IF;
 IF prior IS DISTINCT FROM p_queue THEN
  UPDATE crm.support_tickets SET queue_id=p_queue WHERE tenant_id=t AND ticket_id=p_ticket;
  IF NOT FOUND THEN RAISE EXCEPTION 'Queue assignment denied' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN p_ticket;
END $$;
ALTER FUNCTION crm.register_service_queue(text,text) OWNER TO upc_queue_executor;
ALTER FUNCTION crm.set_ticket_queue(uuid,uuid) OWNER TO upc_queue_executor;
REVOKE ALL ON FUNCTION crm.register_service_queue(text,text),crm.set_ticket_queue(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm.register_service_queue(text,text),crm.set_ticket_queue(uuid,uuid) TO upc_runtime;
COMMIT;

-- 0070: tenant-scoped incident report metadata, not attack detection or live health status.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
INSERT INTO iam.permissions VALUES
 ('ops.incidents.read','Read tenant incident report metadata'),
 ('ops.incidents.write','Register tenant incident report metadata');
CREATE ROLE upc_incident_executor NOLOGIN NOSUPERUSER NOBYPASSRLS;
CREATE TABLE ops.incidents (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 incident_id uuid NOT NULL DEFAULT gen_random_uuid(),
 report_key uuid NOT NULL CHECK(report_key<>'00000000-0000-0000-0000-000000000000'::uuid),
 report_kind text NOT NULL CHECK(report_kind IN ('availability','security')),
 reported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,incident_id),
 UNIQUE(tenant_id,report_key)
);
CREATE INDEX incidents_tenant_reported_idx ON ops.incidents(tenant_id,reported_at,incident_id);
ALTER TABLE ops.incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE ops.incidents FORCE ROW LEVEL SECURITY;
REVOKE ALL ON ops.incidents FROM PUBLIC;
-- Cross-module operational metadata uses explicit permission gates, not a purchased module.
CREATE POLICY incident_runtime_read ON ops.incidents FOR SELECT TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('ops.incidents.read'));
CREATE POLICY incident_executor_read ON ops.incidents FOR SELECT TO upc_incident_executor
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('ops.incidents.read') AND iam.has_permission('ops.incidents.write'));
CREATE POLICY incident_executor_insert ON ops.incidents FOR INSERT TO upc_incident_executor
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('ops.incidents.read') AND iam.has_permission('ops.incidents.write'));
GRANT USAGE ON SCHEMA ops,iam TO upc_incident_executor;
GRANT EXECUTE ON FUNCTION iam.current_tenant_id(),iam.has_permission(text) TO upc_incident_executor;
GRANT SELECT ON ops.incidents TO upc_runtime,upc_incident_executor;
GRANT INSERT(tenant_id,report_key,report_kind) ON ops.incidents TO upc_incident_executor;
CREATE OR REPLACE FUNCTION ops.record_dossier_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); actor uuid:=iam.current_user_id(); j jsonb; target uuid;
BEGIN
 IF t IS NULL OR actor IS NULL THEN RAISE EXCEPTION 'Mapped audit actor required' USING ERRCODE='42501'; END IF;
 j:=CASE WHEN TG_OP='DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
 IF (j->>'tenant_id')::uuid IS DISTINCT FROM t THEN RAISE EXCEPTION 'Audit scope mismatch' USING ERRCODE='42501'; END IF;
 target:=CASE WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='business_locations' THEN (j->>'location_id')::uuid
 WHEN TG_TABLE_SCHEMA='core' AND TG_TABLE_NAME='sites' THEN (j->>'site_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tags' THEN (j->>'tag_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='customer_tag_links' THEN (j->>'link_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='service_queues' THEN (j->>'queue_id')::uuid
 WHEN TG_TABLE_SCHEMA='crm' AND TG_TABLE_NAME='support_tickets' THEN (j->>'ticket_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='categories' THEN (j->>'category_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_barcodes' THEN (j->>'barcode_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='attribute_definitions' THEN (j->>'attribute_id')::uuid
 WHEN TG_TABLE_SCHEMA='catalog' AND TG_TABLE_NAME='variant_attribute_values' THEN (j->>'assignment_id')::uuid
 WHEN TG_TABLE_SCHEMA='inventory' AND TG_TABLE_NAME='reorder_policies' THEN (j->>'policy_id')::uuid
 WHEN TG_TABLE_SCHEMA='sales' AND TG_TABLE_NAME='shipping_methods' THEN (j->>'method_id')::uuid
 WHEN TG_TABLE_SCHEMA='ops' AND TG_TABLE_NAME='incidents' THEN (j->>'incident_id')::uuid
 ELSE COALESCE((j->>'stakeholder_id')::uuid,(j->>'address_id')::uuid,(j->>'user_id')::uuid,t) END;
 INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id)
 VALUES(t,actor,lower(TG_OP),TG_TABLE_SCHEMA||'.'||TG_TABLE_NAME,target);
 RETURN NULL;
END $$;


CREATE TRIGGER incident_report_audit AFTER INSERT ON ops.incidents
 FOR EACH ROW EXECUTE FUNCTION ops.record_dossier_change();
CREATE FUNCTION ops.register_incident_report(p_report_key uuid,p_kind text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); prior ops.incidents%ROWTYPE; iid uuid;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('ops.incidents.read') OR NOT iam.has_permission('ops.incidents.write')
 THEN RAISE EXCEPTION 'Incident reporting denied' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed'
 THEN RAISE EXCEPTION 'READ COMMITTED required' USING ERRCODE='25000'; END IF;
 IF p_report_key IS NULL OR p_report_key='00000000-0000-0000-0000-000000000000'::uuid OR p_kind IS NULL OR p_kind NOT IN ('availability','security')
 THEN RAISE EXCEPTION 'Invalid incident report' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('ops-incident-report',t,p_report_key)::text,0));
 IF t IS DISTINCT FROM iam.current_tenant_id() OR NOT iam.has_permission('ops.incidents.read') OR NOT iam.has_permission('ops.incidents.write')
 THEN RAISE EXCEPTION 'Incident reporting denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO prior FROM ops.incidents WHERE tenant_id=t AND report_key=p_report_key;
 IF FOUND THEN
  IF prior.report_kind IS DISTINCT FROM p_kind THEN RAISE EXCEPTION 'Incident report key conflict' USING ERRCODE='23505'; END IF;
  RETURN prior.incident_id;
 END IF;
 INSERT INTO ops.incidents(tenant_id,report_key,report_kind) VALUES(t,p_report_key,p_kind) RETURNING incident_id INTO iid;
 RETURN iid;
END $$;
ALTER FUNCTION ops.register_incident_report(uuid,text) OWNER TO upc_incident_executor;
REVOKE ALL ON FUNCTION ops.register_incident_report(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ops.register_incident_report(uuid,text) TO upc_runtime;
COMMIT;

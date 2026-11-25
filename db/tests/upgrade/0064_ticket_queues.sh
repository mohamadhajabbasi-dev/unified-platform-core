#!/usr/bin/env bash
set -euo pipefail
: "${PG_CONTAINER:?dedicated queue upgrade CI service required}"
psql_ci() { docker exec -i "$PG_CONTAINER" psql -X -qAt -U postgres -d upc_greenfield_test -v ON_ERROR_STOP=1 "$@"; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export LC_ALL=C
[[ "$(psql_ci -c "SELECT current_database()='upc_greenfield_test' AND to_regclass('core.tenants') IS NULL")" == t ]]
n=0
for migration in db/migrations/*.sql; do
 [[ "$(basename "$migration")" == 0064_* ]] && break
 psql_ci < "$migration"
 n=$((n+1))
done
[[ "$n" == 63 ]]
python3 - "$tmp/legacy.sql" <<'PY'
from pathlib import Path
import sys
lines=Path("db/tests/0013_content_crm_engagement.sql").read_text().splitlines()
assert lines.count("ROLLBACK;")==1 and lines[-2]=="ROLLBACK;"
assert lines[-1].startswith(r"\echo PASS canonical editorial/CRM support:")
lines[-2]="COMMIT;"
Path(sys.argv[1]).write_text("\n".join(lines)+"\n")
PY
psql_ci < "$tmp/legacy.sql"
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_eng_b;
INSERT INTO crm.support_tickets(tenant_id,ticket_key,customer_id,subject,assigned_user_id) VALUES(iam.current_tenant_id(),'SYN-B','d2000000-0000-0000-0000-000000000002','Synthetic B',iam.current_user_id());
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_eng_a;
UPDATE crm.support_tickets SET state='resolved',resolved_at=clock_timestamp(),priority='high' WHERE ticket_key='SYN-1';
RESET SESSION AUTHORIZATION;
SQL
[[ "$(psql_ci -c "SELECT count(*)=2 FROM crm.support_tickets")" == t ]]
snapshot() {
 psql_ci <<'SQL'
SELECT format('SELECT %L,COALESCE(jsonb_agg(to_jsonb(t)%s ORDER BY (to_jsonb(t)%s)::text),''[]''::jsonb) FROM %I.%I t%s;',schemaname||'.'||tablename,
 CASE WHEN schemaname='crm' AND tablename='support_tickets' THEN '-''queue_id''' ELSE '' END,
 CASE WHEN schemaname='crm' AND tablename='support_tickets' THEN '-''queue_id''' ELSE '' END,schemaname,tablename,
 CASE WHEN schemaname='iam' AND tablename='permissions' THEN ' WHERE permission_key<>''crm.queues.write''' ELSE '' END)
 FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema') AND schemaname NOT LIKE 'pg_%'
 AND NOT (schemaname='crm' AND tablename='service_queues') ORDER BY schemaname,tablename
\gexec
SQL
}
snapshot > "$tmp/before"
psql_ci < db/migrations/0064_service_queues.sql
snapshot > "$tmp/after"
cmp "$tmp/before" "$tmp/after"
[[ "$(psql_ci -c "SELECT count(*)=2 AND bool_and(queue_id IS NULL) FROM crm.support_tickets")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=0 FROM crm.service_queues")" == t ]]
[[ "$(psql_ci -c "SELECT count(*)=1 FROM iam.permissions WHERE permission_key='crm.queues.write'")" == t ]]
psql_ci <<'SQL'
SET SESSION AUTHORIZATION upc_eng_a;
INSERT INTO crm.support_tickets(tenant_id,ticket_key,subject) VALUES(iam.current_tenant_id(),'UPGRADE-NEW','Synthetic');
UPDATE crm.support_tickets SET priority='urgent' WHERE ticket_key='UPGRADE-NEW';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM crm.support_tickets WHERE ticket_key='UPGRADE-NEW' AND priority='urgent' AND queue_id IS NULL) THEN RAISE EXCEPTION 'FAIL legacy runtime write after upgrade'; END IF;
 BEGIN INSERT INTO crm.support_tickets(tenant_id,ticket_key,subject,queue_id) VALUES(iam.current_tenant_id(),'BYPASS','Synthetic',NULL); RAISE EXCEPTION 'FAIL direct queue INSERT'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE crm.support_tickets SET queue_id=NULL WHERE ticket_key='SYN-1'; RAISE EXCEPTION 'FAIL direct queue UPDATE'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SQL
echo 'PASS committed pre-0064 ticket upgrade: exact prior rows, nullable queue, no backfill, original runtime writes preserved'

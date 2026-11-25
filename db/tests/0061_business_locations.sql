\set ON_ERROR_STOP on
BEGIN;
CREATE ROLE upc_location_a LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_location_b LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_location_reader LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_location_none LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_location_nolegal LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE upc_location_unmapped LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT upc_runtime TO upc_location_a,upc_location_b,upc_location_reader,upc_location_none,upc_location_nolegal,upc_location_unmapped;
INSERT INTO core.tenants(tenant_id,tenant_key,display_name) VALUES
 ('a0610000-0000-0000-0000-000000000001','loc-a','Synthetic A'),
 ('a0610000-0000-0000-0000-000000000002','loc-b','Synthetic B');
INSERT INTO core.users(user_id,identity_issuer,identity_subject)
 SELECT ('b0610000-0000-0000-0000-00000000000'||i)::uuid,'test','location-'||i FROM generate_series(1,5) i;
INSERT INTO iam.memberships(tenant_id,user_id)
 SELECT CASE WHEN i=2 THEN 'a0610000-0000-0000-0000-000000000002'::uuid ELSE 'a0610000-0000-0000-0000-000000000001'::uuid END,
 ('b0610000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.db_principals(login_role,tenant_id,user_id)
 SELECT (ARRAY['upc_location_a','upc_location_b','upc_location_reader','upc_location_none','upc_location_nolegal'])[i]::name,
 CASE WHEN i=2 THEN 'a0610000-0000-0000-0000-000000000002'::uuid ELSE 'a0610000-0000-0000-0000-000000000001'::uuid END,
 ('b0610000-0000-0000-0000-00000000000'||i)::uuid FROM generate_series(1,5) i;
INSERT INTO iam.roles(tenant_id,role_id,role_key)
 SELECT tenant_id,('c0610000-0000-0000-0000-00000000000'||right(user_id::text,1))::uuid,'location-'||right(user_id::text,1)
 FROM iam.memberships WHERE tenant_id IN ('a0610000-0000-0000-0000-000000000001','a0610000-0000-0000-0000-000000000002');
INSERT INTO iam.membership_roles SELECT m.tenant_id,m.user_id,r.role_id FROM iam.memberships m JOIN iam.roles r
 ON r.tenant_id=m.tenant_id AND r.role_key='location-'||right(m.user_id::text,1)
 WHERE m.tenant_id IN ('a0610000-0000-0000-0000-000000000001','a0610000-0000-0000-0000-000000000002');
INSERT INTO iam.role_grants SELECT r.tenant_id,r.role_id,p.permission_key FROM iam.roles r CROSS JOIN iam.permissions p
 WHERE r.tenant_id IN ('a0610000-0000-0000-0000-000000000001','a0610000-0000-0000-0000-000000000002') AND (
 (r.role_key IN ('location-1','location-2') AND p.permission_key IN ('tenant.locations.read','tenant.locations.write','tenant.legal.read','tenant.legal.write','ops.audit.read'))
 OR (r.role_key='location-3' AND p.permission_key='tenant.locations.read')
 OR (r.role_key='location-5' AND p.permission_key IN ('tenant.locations.read','tenant.locations.write')));
SET SESSION AUTHORIZATION upc_location_b;
INSERT INTO core.tenant_addresses(tenant_id,address_id,address_kind,country_code,address_text)
 VALUES(iam.current_tenant_id(),'d0610000-0000-0000-0000-000000000002','operating','IR','Synthetic B address');
INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,address_id)
 VALUES(iam.current_tenant_id(),'main','Synthetic B','store','d0610000-0000-0000-0000-000000000002');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_a;
INSERT INTO core.tenant_addresses(tenant_id,address_id,address_kind,country_code,address_text)
 VALUES(iam.current_tenant_id(),'d0610000-0000-0000-0000-000000000001','operating','IR','Synthetic A address');
DO $$
DECLARE t uuid:=iam.current_tenant_id(); lid uuid; cmd text; bad text; before_audit bigint;
BEGIN
 INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,address_id)
 VALUES(t,'main','Synthetic A','branch','d0610000-0000-0000-0000-000000000001') RETURNING location_id INTO lid;
 INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,address_id)
 VALUES(t,'retail-2','Synthetic store','store','d0610000-0000-0000-0000-000000000001');
 IF (SELECT count(*) FROM core.business_locations)<>2 OR EXISTS(SELECT 1 FROM core.business_locations WHERE tenant_id<>t)
 THEN RAISE EXCEPTION 'FAIL location isolation'; END IF;
 UPDATE core.business_locations SET display_name='Renamed',is_active=false WHERE location_id=lid;
 IF NOT EXISTS(SELECT 1 FROM core.business_locations WHERE location_id=lid AND NOT is_active AND display_name='Renamed' AND created_at<=clock_timestamp())
 THEN RAISE EXCEPTION 'FAIL update'; END IF;
 IF (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.business_locations')<>3
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.business_locations' AND entity_id=lid AND actor_user_id=iam.current_user_id() AND tenant_id=t)<>2
 OR NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_id=lid AND event_type='insert' AND entity_type='core.business_locations')
 OR NOT EXISTS(SELECT 1 FROM ops.audit_events WHERE entity_id=lid AND event_type='update' AND entity_type='core.business_locations')
 THEN RAISE EXCEPTION 'FAIL location audit identity'; END IF;
 SELECT count(*) INTO before_audit FROM ops.audit_events;
 BEGIN
  INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(t,'main','Duplicate','store');
  RAISE EXCEPTION 'FAIL duplicate location';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 FOREACH bad IN ARRAY ARRAY['','UPPER','bad key',repeat('a',81)] LOOP
  BEGIN
   INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(t,bad,'Invalid','store');
   RAISE EXCEPTION 'FAIL invalid key';
  EXCEPTION WHEN check_violation THEN NULL; END;
 END LOOP;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(t,'bad-kind','Invalid','warehouse');
 RAISE EXCEPTION 'FAIL invalid kind'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(t,'bad-name',E' \t','store');
 RAISE EXCEPTION 'FAIL invalid name'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,address_id)
 VALUES(t,'foreign-address','Invalid','store','d0610000-0000-0000-0000-000000000002');
 RAISE EXCEPTION 'FAIL foreign address'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN UPDATE core.business_locations SET address_id='d0610000-0000-0000-0000-000000000003' WHERE location_id=lid;
 RAISE EXCEPTION 'FAIL missing address'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind)
 VALUES('a0610000-0000-0000-0000-000000000002','cross','Invalid','branch');
 RAISE EXCEPTION 'FAIL foreign tenant insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 UPDATE core.business_locations SET display_name='Forbidden' WHERE tenant_id='a0610000-0000-0000-0000-000000000002';
 IF FOUND THEN RAISE EXCEPTION 'FAIL foreign tenant update'; END IF;
 FOREACH cmd IN ARRAY ARRAY[
 'UPDATE core.business_locations SET tenant_id=tenant_id',
 'UPDATE core.business_locations SET location_id=location_id',
 'UPDATE core.business_locations SET location_key=location_key',
 'UPDATE core.business_locations SET location_kind=location_kind',
 'UPDATE core.business_locations SET created_at=created_at',
 'INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,created_at) VALUES(iam.current_tenant_id(),''fake-time'',''Invalid'',''store'',now())',
 'INSERT INTO core.business_locations(tenant_id,location_id,location_key,display_name,location_kind) VALUES(iam.current_tenant_id(),gen_random_uuid(),''fake-id'',''Invalid'',''store'')',
 'DELETE FROM core.business_locations','TRUNCATE core.business_locations',
 'DELETE FROM ops.audit_events','INSERT INTO ops.audit_events(tenant_id,actor_user_id,event_type,entity_type,entity_id) VALUES(iam.current_tenant_id(),iam.current_user_id(),''insert'',''fake'',gen_random_uuid())'] LOOP
  BEGIN EXECUTE cmd; RAISE EXCEPTION 'FAIL forbidden DML: %',cmd;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN
  INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(t,'rolled-back','Synthetic','branch');
  RAISE EXCEPTION 'synthetic rollback' USING ERRCODE='P0002';
 EXCEPTION WHEN no_data_found THEN NULL; END;
 IF (SELECT count(*) FROM core.business_locations)<>2 OR (SELECT count(*) FROM ops.audit_events)<>before_audit
 THEN RAISE EXCEPTION 'FAIL rejected or rolled back changes persisted'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_reader;
DO $$ BEGIN
 IF (SELECT count(*) FROM core.business_locations)<>2 OR EXISTS(SELECT 1 FROM core.tenant_addresses)
 THEN RAISE EXCEPTION 'FAIL reader scope or address disclosure'; END IF;
 UPDATE core.business_locations SET display_name='Forbidden';
 IF FOUND THEN RAISE EXCEPTION 'FAIL reader update'; END IF;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(iam.current_tenant_id(),'reader','Invalid','store');
 RAISE EXCEPTION 'FAIL reader insert'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_none;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.business_locations) THEN RAISE EXCEPTION 'FAIL no permission read'; END IF;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES(iam.current_tenant_id(),'none','Invalid','store');
 RAISE EXCEPTION 'FAIL no permission write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_nolegal;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.tenant_addresses) THEN RAISE EXCEPTION 'FAIL legal read'; END IF;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind,address_id)
 VALUES(iam.current_tenant_id(),'oracle','Invalid','store','d0610000-0000-0000-0000-000000000001');
 RAISE EXCEPTION 'FAIL unauthorized address binding'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE core.business_locations SET address_id='d0610000-0000-0000-0000-000000000003' WHERE location_key='main';
 RAISE EXCEPTION 'FAIL unauthorized address update'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_unmapped;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core.business_locations) THEN RAISE EXCEPTION 'FAIL unmapped read'; END IF;
 BEGIN INSERT INTO core.business_locations(tenant_id,location_key,display_name,location_kind) VALUES('a0610000-0000-0000-0000-000000000001','unmapped','Invalid','store');
 RAISE EXCEPTION 'FAIL unmapped write'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION upc_location_b;
DO $$ BEGIN
 IF (SELECT count(*) FROM core.business_locations)<>1 OR NOT EXISTS(SELECT 1 FROM core.business_locations WHERE location_key='main' AND display_name='Synthetic B')
 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.business_locations')<>1
 THEN RAISE EXCEPTION 'FAIL B same key isolation'; END IF;
END $$;
RESET SESSION AUTHORIZATION;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='core.business_locations'::regclass AND relrowsecurity AND relforcerowsecurity)
 OR NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='core' AND tablename='business_locations' AND indexname='business_locations_address_idx')
 OR has_table_privilege('upc_runtime','core.business_locations','DELETE,TRUNCATE')
 OR has_column_privilege('upc_runtime','core.business_locations','created_at','INSERT,UPDATE')
 OR has_column_privilege('upc_runtime','core.business_locations','location_id','INSERT,UPDATE')
 OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_roles r ON r.oid=p.proowner WHERE p.oid='ops.record_dossier_change()'::regprocedure
 AND r.rolname='upc_audit_writer' AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog'])
 THEN RAISE EXCEPTION 'FAIL location structural privilege contract'; END IF;
 IF (SELECT count(*) FROM core.business_locations)<>3 OR (SELECT count(*) FROM ops.audit_events WHERE entity_type='core.business_locations')<>4
 THEN RAISE EXCEPTION 'FAIL global count'; END IF;
END $$;
ROLLBACK;
\echo PASS business locations: canonical address FK, tenant keys, RLS, permissions, immutable identity, exact audit and atomic rollback

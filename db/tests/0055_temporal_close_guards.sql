\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
 IF has_function_privilege('upc_runtime','platform.module_enabled(text,timestamptz)','EXECUTE')
 OR has_function_privilege('upc_platform_approver','platform.module_enabled(text,timestamptz)','EXECUTE')
 OR NOT has_function_privilege('upc_finance_executor','platform.module_enabled(text,timestamptz)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL explicit-time entitlement ACL'; END IF;
 IF platform.module_enabled('finance',NULL) OR platform.module_enabled('finance',clock_timestamp())
 THEN RAISE EXCEPTION 'FAIL missing tenant entitlement'; END IF;
 IF (SELECT provolatile FROM pg_proc WHERE oid='platform.module_enabled(text)'::regprocedure)<>'s'
 OR (SELECT proowner FROM pg_proc WHERE oid='platform.module_enabled(text,timestamptz)'::regprocedure)
 <> (SELECT oid FROM pg_roles WHERE rolname='upc_policy_reader')
 OR NOT (SELECT prosecdef FROM pg_proc WHERE oid='platform.module_enabled(text,timestamptz)'::regprocedure)
 THEN RAISE EXCEPTION 'FAIL entitlement function boundary'; END IF;
END $$;
ROLLBACK;
\echo PASS temporal close guard ACL, tenantless and null-time denial

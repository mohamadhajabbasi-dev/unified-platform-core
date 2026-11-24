-- 0015: separate normalized tenant HR and payroll domain.
-- Prototype for a disposable PostgreSQL test DB. Not a deployed payroll system.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'isolated DB required'; END IF;
END $$;
CREATE SCHEMA hr;
REVOKE ALL ON SCHEMA hr FROM PUBLIC;
INSERT INTO platform.modules(module_key,version_label) VALUES ('hr','0.1');
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('hr.read','Read tenant HR personnel records'), ('hr.write','Maintain tenant HR personnel'),
 ('hr.payroll.read','Read tenant contracts and payroll'), ('hr.payroll.write','Maintain tenant contracts and payroll');

-- Independent employment identity; optional link to an EXISTING user membership.
-- Never invent a second authentication user or retain raw national/bank IDs.
CREATE TABLE hr.employees (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 employee_id uuid NOT NULL DEFAULT gen_random_uuid(),
 user_id uuid,
 personnel_code text NOT NULL CHECK(length(btrim(personnel_code)) BETWEEN 1 AND 80),
 display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 1 AND 250),
 protected_identity_ref text CHECK(length(protected_identity_ref) BETWEEN 5 AND 300),
 hired_on date NOT NULL CHECK(isfinite(hired_on)),
 terminated_on date CHECK(isfinite(terminated_on) AND terminated_on>=hired_on),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,employee_id),
 UNIQUE(tenant_id,personnel_code),
 UNIQUE(tenant_id,user_id),
 FOREIGN KEY(tenant_id,user_id) REFERENCES iam.memberships(tenant_id,user_id)
);
CREATE INDEX employee_user_idx ON hr.employees(tenant_id,user_id) WHERE user_id IS NOT NULL;

CREATE TABLE hr.employment_contracts (
 tenant_id uuid NOT NULL,
 contract_id uuid NOT NULL DEFAULT gen_random_uuid(),
 employee_id uuid NOT NULL,
 effective_dates daterange NOT NULL CHECK(
  NOT isempty(effective_dates) AND NOT lower_inf(effective_dates)
  AND isfinite(lower(effective_dates)) AND
  (upper_inf(effective_dates) OR isfinite(upper(effective_dates)))
 ),
 role_title text NOT NULL CHECK(length(btrim(role_title)) BETWEEN 1 AND 200),
 department text,
 monthly_base_pay numeric(20,4) NOT NULL CHECK(monthly_base_pay>=0 AND monthly_base_pay<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 is_insured boolean NOT NULL DEFAULT false,
 is_taxable boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,contract_id),
 FOREIGN KEY(tenant_id,employee_id) REFERENCES hr.employees(tenant_id,employee_id),
 CONSTRAINT one_contract_during_period EXCLUDE USING gist
  (tenant_id WITH =,employee_id WITH =,effective_dates WITH &&)
);
CREATE INDEX contract_employee_idx ON hr.employment_contracts(tenant_id,employee_id);

CREATE TABLE hr.payroll_periods (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 period_id uuid NOT NULL DEFAULT gen_random_uuid(),
 covered_dates daterange NOT NULL CHECK(
  NOT isempty(covered_dates) AND NOT lower_inf(covered_dates) AND NOT upper_inf(covered_dates)
  AND isfinite(lower(covered_dates)) AND isfinite(upper(covered_dates))
 ),
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','posted','closed')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,period_id),
 CONSTRAINT one_payroll_period EXCLUDE USING gist(tenant_id WITH =,covered_dates WITH &&)
);

-- Payroll components are distinct signed journal-like facts; totals derive
-- from these rows and must later post to existing finance.journal_entries.
CREATE TABLE hr.payroll_entries (
 tenant_id uuid NOT NULL,
 entry_id uuid NOT NULL DEFAULT gen_random_uuid(),
 period_id uuid NOT NULL,
 employee_id uuid NOT NULL,
 item_key text NOT NULL CHECK(length(btrim(item_key)) BETWEEN 1 AND 100),
 component text NOT NULL CHECK(component IN
  ('base','housing','food','child','bonus','commission','insurance','tax','deduction','other')),
 amount numeric(20,4) NOT NULL CHECK(amount<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,entry_id),
 UNIQUE(tenant_id,period_id,employee_id,item_key),
 FOREIGN KEY(tenant_id,period_id) REFERENCES hr.payroll_periods(tenant_id,period_id),
 FOREIGN KEY(tenant_id,employee_id) REFERENCES hr.employees(tenant_id,employee_id)
);
CREATE INDEX payroll_entries_employee_idx ON hr.payroll_entries(tenant_id,employee_id,period_id);
CREATE FUNCTION hr.guard_payroll_entries() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE current_status text;
BEGIN
 SELECT status INTO current_status FROM hr.payroll_periods
 WHERE tenant_id=NEW.tenant_id AND period_id=NEW.period_id FOR UPDATE;
 IF current_status IS NULL OR current_status<>'open' THEN
   RAISE EXCEPTION 'Payroll period must be open' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION hr.guard_payroll_entries() FROM PUBLIC;
CREATE TRIGGER payroll_period_gate BEFORE INSERT ON hr.payroll_entries
 FOR EACH ROW EXECUTE FUNCTION hr.guard_payroll_entries();

-- Loan and advance are one obligation master with different kind, not mirrored
-- balance columns. Repayment installments/ledger will be separate later.
CREATE TABLE hr.employee_obligations (
 tenant_id uuid NOT NULL,
 obligation_id uuid NOT NULL DEFAULT gen_random_uuid(),
 employee_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('loan','advance')),
 principal numeric(20,4) NOT NULL CHECK(principal>0 AND principal<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 issued_on date NOT NULL CHECK(isfinite(issued_on)),
 external_ref text,
 PRIMARY KEY(tenant_id,obligation_id),
 FOREIGN KEY(tenant_id,employee_id) REFERENCES hr.employees(tenant_id,employee_id)
);
CREATE INDEX employee_obligations_employee_idx ON hr.employee_obligations(tenant_id,employee_id);

CREATE TABLE hr.commission_plans (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 commission_plan_id uuid NOT NULL DEFAULT gen_random_uuid(),
 plan_key text NOT NULL CHECK(length(btrim(plan_key)) BETWEEN 1 AND 100),
 effective_dates daterange NOT NULL CHECK(NOT isempty(effective_dates) AND NOT lower_inf(effective_dates)
 AND isfinite(lower(effective_dates)) AND (upper_inf(effective_dates) OR isfinite(upper(effective_dates)))),
 percentage numeric(7,4) NOT NULL CHECK(percentage>=0 AND percentage<=100 AND percentage<>'NaN'::numeric),
 PRIMARY KEY(tenant_id,commission_plan_id),
 CONSTRAINT commission_plan_nonoverlap EXCLUDE USING gist
 (tenant_id WITH =,plan_key WITH =,effective_dates WITH &&)
);
CREATE TABLE hr.commission_entries (
 tenant_id uuid NOT NULL,
 commission_id uuid NOT NULL DEFAULT gen_random_uuid(),
 employee_id uuid NOT NULL,
 commission_plan_id uuid NOT NULL,
 order_id uuid NOT NULL,
 source_event_key text NOT NULL CHECK(length(btrim(source_event_key)) BETWEEN 1 AND 150),
 amount numeric(20,4) NOT NULL CHECK(amount>=0 AND amount<>'NaN'::numeric),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,commission_id),
 UNIQUE(tenant_id,source_event_key),
 FOREIGN KEY(tenant_id,employee_id) REFERENCES hr.employees(tenant_id,employee_id),
 FOREIGN KEY(tenant_id,commission_plan_id) REFERENCES hr.commission_plans(tenant_id,commission_plan_id),
 FOREIGN KEY(tenant_id,order_id) REFERENCES sales.orders(tenant_id,order_id)
);

DO $$
DECLARE rel regclass; pread text; pwrite text;
BEGIN
 FOREACH rel IN ARRAY ARRAY[
 'hr.employees'::regclass,'hr.employment_contracts'::regclass,
 'hr.payroll_periods'::regclass,'hr.payroll_entries'::regclass,
 'hr.employee_obligations'::regclass,'hr.commission_plans'::regclass,'hr.commission_entries'::regclass]
 LOOP
  IF rel='hr.employees'::regclass THEN pread:='hr.read';pwrite:='hr.write';
  ELSE pread:='hr.payroll.read';pwrite:='hr.payroll.write'; END IF;
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY hr_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND platform.module_enabled(''hr''))',rel,pread);
  EXECUTE format('CREATE POLICY hr_insert ON %s FOR INSERT TO upc_runtime WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(%L) AND iam.has_permission(%L) AND platform.module_enabled(''hr''))',rel,pread,pwrite);
 END LOOP;
END $$;
CREATE POLICY employee_update ON hr.employees FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('hr.read') AND iam.has_permission('hr.write') AND platform.module_enabled('hr'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('hr.read') AND iam.has_permission('hr.write') AND platform.module_enabled('hr'));
CREATE POLICY period_update ON hr.payroll_periods FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('hr.payroll.read') AND iam.has_permission('hr.payroll.write') AND platform.module_enabled('hr'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('hr.payroll.read') AND iam.has_permission('hr.payroll.write') AND platform.module_enabled('hr'));

GRANT USAGE ON SCHEMA hr TO upc_runtime;
GRANT SELECT,INSERT ON hr.employees,hr.employment_contracts,hr.payroll_periods,
 hr.payroll_entries,hr.employee_obligations,hr.commission_plans,hr.commission_entries TO upc_runtime;
GRANT UPDATE(display_name,is_active,terminated_on,protected_identity_ref) ON hr.employees TO upc_runtime;
GRANT UPDATE(status) ON hr.payroll_periods TO upc_runtime;
COMMIT;

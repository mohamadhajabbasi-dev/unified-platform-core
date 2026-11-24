-- 0004: one tenant-owned canonical product catalog and temporal price source.
BEGIN;
DO $$ BEGIN
 IF current_database() <> 'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF;
END $$;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE SCHEMA catalog;
REVOKE ALL ON SCHEMA catalog FROM PUBLIC;
INSERT INTO iam.permissions(permission_key,description) VALUES
 ('catalog.read','Read catalog and prices'),('catalog.write','Maintain products, variants and categories'),
 ('catalog.price.write','Maintain price lists and effective prices');
INSERT INTO platform.modules(module_key,version_label) VALUES ('catalog','0.1');

CREATE TABLE catalog.products (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 product_id uuid NOT NULL DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK (btrim(name)<>''),
 description text NOT NULL DEFAULT '',
 kind text NOT NULL CHECK (kind IN ('physical','digital','service')),
 is_active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,product_id)
);
CREATE TABLE catalog.variants (
 tenant_id uuid NOT NULL,
 variant_id uuid NOT NULL DEFAULT gen_random_uuid(),
 product_id uuid NOT NULL,
 sku text NOT NULL CHECK (sku=btrim(sku) AND sku<>''),
 name text NOT NULL CHECK (btrim(name)<>''),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id)
);
CREATE UNIQUE INDEX variants_tenant_sku_uq ON catalog.variants(tenant_id,lower(sku));
CREATE INDEX variants_product_idx ON catalog.variants(tenant_id,product_id);

CREATE TABLE catalog.categories (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 category_id uuid NOT NULL DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK (name=btrim(name) AND name<>''),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,category_id)
);
CREATE UNIQUE INDEX categories_tenant_name_uq ON catalog.categories(tenant_id,lower(name));
CREATE TABLE catalog.product_categories (
 tenant_id uuid NOT NULL,
 product_id uuid NOT NULL,
 category_id uuid NOT NULL,
 PRIMARY KEY(tenant_id,product_id,category_id),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id),
 FOREIGN KEY(tenant_id,category_id) REFERENCES catalog.categories(tenant_id,category_id)
);
CREATE INDEX product_categories_category_idx ON catalog.product_categories(tenant_id,category_id);

-- Currency belongs to price list; do not repeat it in each price entry.
CREATE TABLE catalog.price_lists (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 price_list_id uuid NOT NULL DEFAULT gen_random_uuid(),
 list_key text NOT NULL CHECK (list_key ~ '^[a-z][a-z0-9_.-]+$'),
 currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
 name text NOT NULL CHECK (btrim(name)<>''),
 is_active boolean NOT NULL DEFAULT true,
 PRIMARY KEY(tenant_id,price_list_id),
 UNIQUE(tenant_id,list_key)
);
CREATE TABLE catalog.price_entries (
 tenant_id uuid NOT NULL,
 price_id uuid NOT NULL DEFAULT gen_random_uuid(),
 variant_id uuid NOT NULL,
 price_list_id uuid NOT NULL,
 amount numeric(20,4) NOT NULL CHECK (amount>=0 AND amount<>'NaN'::numeric),
 valid_during tstzrange NOT NULL CHECK (
  NOT isempty(valid_during) AND NOT lower_inf(valid_during)
  AND isfinite(lower(valid_during)) AND lower_inc(valid_during) AND NOT upper_inc(valid_during)
  AND (upper_inf(valid_during) OR isfinite(upper(valid_during)))
 ),
 PRIMARY KEY(tenant_id,price_id),
 FOREIGN KEY(tenant_id,variant_id) REFERENCES catalog.variants(tenant_id,variant_id),
 FOREIGN KEY(tenant_id,price_list_id) REFERENCES catalog.price_lists(tenant_id,price_list_id),
 CONSTRAINT price_period_no_overlap EXCLUDE USING gist
  (tenant_id WITH =,variant_id WITH =,price_list_id WITH =,valid_during WITH &&)
);
CREATE INDEX price_entries_list_idx ON catalog.price_entries(tenant_id,price_list_id);
-- Historical prices cannot be reassigned or have their amount changed by runtime.
-- Existing range may only be shortened at the upper bound; never move its start.
CREATE FUNCTION catalog.guard_price_period() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF lower(NEW.valid_during) IS DISTINCT FROM lower(OLD.valid_during)
 OR NOT OLD.valid_during @> NEW.valid_during THEN
   RAISE EXCEPTION 'Price period may only be shortened without moving its start' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION catalog.guard_price_period() FROM PUBLIC;
CREATE TRIGGER price_period_guard BEFORE UPDATE OF valid_during ON catalog.price_entries
FOR EACH ROW EXECUTE FUNCTION catalog.guard_price_period();

DO $$
DECLARE rel regclass; write_perm text;
BEGIN
 FOREACH rel IN ARRAY ARRAY['catalog.products'::regclass,'catalog.variants'::regclass,
  'catalog.categories'::regclass,'catalog.product_categories'::regclass,
  'catalog.price_lists'::regclass,'catalog.price_entries'::regclass]
 LOOP
  write_perm := CASE WHEN rel IN ('catalog.price_lists'::regclass,'catalog.price_entries'::regclass)
   THEN 'catalog.price.write' ELSE 'catalog.write' END;
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY catalog_read ON %s FOR SELECT TO upc_runtime USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND platform.module_enabled(''catalog''))',rel);
  EXECUTE format('CREATE POLICY catalog_insert ON %s FOR INSERT TO upc_runtime WITH CHECK (tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND iam.has_permission(%L) AND platform.module_enabled(''catalog''))',rel,write_perm);
  EXECUTE format('CREATE POLICY catalog_update ON %s FOR UPDATE TO upc_runtime USING (tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND iam.has_permission(%L) AND platform.module_enabled(''catalog'')) WITH CHECK (tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND iam.has_permission(%L) AND platform.module_enabled(''catalog''))',rel,write_perm,write_perm);
 END LOOP;
END $$;
-- Association deletion is a distinct authorized operation, not product deletion.
CREATE POLICY category_unlink ON catalog.product_categories FOR DELETE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.read')
 AND iam.has_permission('catalog.write') AND platform.module_enabled('catalog'));
GRANT USAGE ON SCHEMA catalog TO upc_runtime;
GRANT SELECT,INSERT ON ALL TABLES IN SCHEMA catalog TO upc_runtime;
GRANT UPDATE(name,description,is_active) ON catalog.products TO upc_runtime;
GRANT UPDATE(name,sku,is_active) ON catalog.variants TO upc_runtime;
GRANT UPDATE(name,is_active) ON catalog.categories TO upc_runtime;
GRANT UPDATE(name,is_active) ON catalog.price_lists TO upc_runtime;
GRANT UPDATE(valid_during) ON catalog.price_entries TO upc_runtime;
GRANT DELETE ON catalog.product_categories TO upc_runtime;

-- Invoker rights: no bypass of caller's tenant/module/permission gates.
CREATE FUNCTION catalog.price_at(p_variant uuid,p_list uuid,p_at timestamptz DEFAULT statement_timestamp())
RETURNS TABLE(price_id uuid,amount numeric,currency text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 SELECT e.price_id,e.amount,l.currency
 FROM catalog.price_entries e JOIN catalog.price_lists l
 ON l.tenant_id=e.tenant_id AND l.price_list_id=e.price_list_id
 JOIN catalog.variants v ON v.tenant_id=e.tenant_id AND v.variant_id=e.variant_id
 JOIN catalog.products p ON p.tenant_id=v.tenant_id AND p.product_id=v.product_id
 WHERE e.tenant_id=iam.current_tenant_id() AND e.variant_id=p_variant AND e.price_list_id=p_list
 AND e.valid_during @> p_at AND l.is_active AND v.is_active AND p.is_active
$$;
REVOKE ALL ON FUNCTION catalog.price_at(uuid,uuid,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.price_at(uuid,uuid,timestamptz) TO upc_runtime;
COMMIT;

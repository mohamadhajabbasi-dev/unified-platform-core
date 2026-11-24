-- 0014: canonical product details and volume prices; isolated test database only.
BEGIN;
DO $$ BEGIN
 IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Isolated test DB required'; END IF;
END $$;

CREATE TABLE catalog.brands (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 brand_id uuid NOT NULL DEFAULT gen_random_uuid(),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 180),
 PRIMARY KEY(tenant_id,brand_id)
);
CREATE UNIQUE INDEX brands_per_tenant_uq ON catalog.brands(tenant_id,lower(name));

CREATE TABLE catalog.measure_units (
 tenant_id uuid NOT NULL REFERENCES core.tenants(tenant_id),
 unit_id uuid NOT NULL DEFAULT gen_random_uuid(),
 unit_key text NOT NULL CHECK(unit_key ~ '^[a-z][a-z0-9_.-]{0,40}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 1 AND 100),
 quantity_precision smallint NOT NULL DEFAULT 0 CHECK(quantity_precision BETWEEN 0 AND 6),
 PRIMARY KEY(tenant_id,unit_id), UNIQUE(tenant_id,unit_key)
);
-- These are references to child entities, NOT another Product master.
ALTER TABLE catalog.products ADD COLUMN brand_id uuid, ADD COLUMN unit_id uuid;
ALTER TABLE catalog.products ADD CONSTRAINT product_brand_fk
 FOREIGN KEY(tenant_id,brand_id) REFERENCES catalog.brands(tenant_id,brand_id);
ALTER TABLE catalog.products ADD CONSTRAINT product_unit_fk
 FOREIGN KEY(tenant_id,unit_id) REFERENCES catalog.measure_units(tenant_id,unit_id);

CREATE TABLE catalog.product_media (
 tenant_id uuid NOT NULL,
 media_id uuid NOT NULL DEFAULT gen_random_uuid(),
 product_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN ('image','video','document')),
 storage_ref text NOT NULL CHECK(length(btrim(storage_ref)) BETWEEN 5 AND 350),
 alt_text text CHECK(length(alt_text)<=400),
 display_order integer NOT NULL DEFAULT 0 CHECK(display_order>=0),
 PRIMARY KEY(tenant_id,media_id),
 UNIQUE(tenant_id,product_id,storage_ref),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id)
);
CREATE INDEX product_media_product_idx ON catalog.product_media(tenant_id,product_id,display_order);

CREATE TABLE catalog.product_warranties (
 tenant_id uuid NOT NULL,
 warranty_id uuid NOT NULL DEFAULT gen_random_uuid(),
 product_id uuid NOT NULL,
 provider_name text NOT NULL CHECK(length(btrim(provider_name)) BETWEEN 1 AND 200),
 duration_months integer CHECK(duration_months BETWEEN 0 AND 360),
 terms text,
 PRIMARY KEY(tenant_id,warranty_id),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id)
);
CREATE INDEX product_warranties_product_idx ON catalog.product_warranties(tenant_id,product_id);

-- Customer reviews are dependent on the canonical product and canonical CRM
-- customer, not a new product/customer entity. Ingestion requires a trusted API.
CREATE TABLE catalog.product_reviews (
 tenant_id uuid NOT NULL,
 review_id uuid NOT NULL DEFAULT gen_random_uuid(),
 product_id uuid NOT NULL,
 customer_id uuid NOT NULL,
 score smallint NOT NULL CHECK(score BETWEEN 1 AND 5),
 review_text text CHECK(length(review_text)<=5000),
 is_approved boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tenant_id,review_id),
 FOREIGN KEY(tenant_id,product_id) REFERENCES catalog.products(tenant_id,product_id),
 FOREIGN KEY(tenant_id,customer_id) REFERENCES crm.customers(tenant_id,customer_id)
);
CREATE INDEX product_reviews_published_idx
 ON catalog.product_reviews(tenant_id,product_id,created_at DESC) WHERE is_approved;

-- Price ladder is a dependent rule for the existing immutable price entry.
-- It is NOT a second price master. One bracket cannot overlap another.
CREATE TABLE catalog.price_quantity_tiers (
 tenant_id uuid NOT NULL,
 tier_id uuid NOT NULL DEFAULT gen_random_uuid(),
 price_id uuid NOT NULL,
 quantity_range int8range NOT NULL CHECK(
  NOT isempty(quantity_range) AND NOT lower_inf(quantity_range)
  AND lower(quantity_range)>=2 AND lower_inc(quantity_range)
  AND NOT upper_inc(quantity_range)
 ),
 tier_amount numeric(20,4) NOT NULL CHECK(tier_amount>=0 AND tier_amount<>'NaN'::numeric),
 PRIMARY KEY(tenant_id,tier_id),
 FOREIGN KEY(tenant_id,price_id) REFERENCES catalog.price_entries(tenant_id,price_id),
 CONSTRAINT tier_ranges_cannot_overlap EXCLUDE USING gist
 (tenant_id WITH =,price_id WITH =,quantity_range WITH &&)
);
CREATE INDEX price_tiers_entry_idx ON catalog.price_quantity_tiers(tenant_id,price_id);

DO $$
DECLARE rel regclass; p_write text;
BEGIN
 FOREACH rel IN ARRAY ARRAY[
  'catalog.brands'::regclass,'catalog.measure_units'::regclass,
  'catalog.product_media'::regclass,'catalog.product_warranties'::regclass,
  'catalog.product_reviews'::regclass,'catalog.price_quantity_tiers'::regclass] LOOP
  p_write:=CASE WHEN rel='catalog.price_quantity_tiers'::regclass
    THEN 'catalog.price.write' ELSE 'catalog.write' END;
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY',rel);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY',rel);
  EXECUTE format('CREATE POLICY catalog_detail_read ON %s FOR SELECT TO upc_runtime USING(tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND platform.module_enabled(''catalog''))',rel);
  EXECUTE format('CREATE POLICY catalog_detail_insert ON %s FOR INSERT TO upc_runtime WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission(''catalog.read'') AND iam.has_permission(%L) AND platform.module_enabled(''catalog''))',rel,p_write);
 END LOOP;
END $$;
CREATE POLICY brand_edit ON catalog.brands FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY unit_edit ON catalog.measure_units FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY review_moderation ON catalog.product_reviews FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));
CREATE POLICY media_edit ON catalog.product_media FOR UPDATE TO upc_runtime
 USING(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'))
 WITH CHECK(tenant_id=iam.current_tenant_id() AND iam.has_permission('catalog.write') AND iam.has_permission('catalog.read') AND platform.module_enabled('catalog'));

GRANT SELECT,INSERT ON catalog.brands,catalog.measure_units,catalog.product_media,
 catalog.product_warranties,catalog.product_reviews,catalog.price_quantity_tiers TO upc_runtime;
GRANT UPDATE(name) ON catalog.brands TO upc_runtime;
GRANT UPDATE(name,quantity_precision) ON catalog.measure_units TO upc_runtime;
GRANT UPDATE(alt_text,display_order) ON catalog.product_media TO upc_runtime;
GRANT UPDATE(is_approved) ON catalog.product_reviews TO upc_runtime;
GRANT UPDATE(brand_id,unit_id) ON catalog.products TO upc_runtime;

-- Tier-aware quote for a *pre-authorized* price list; the caller must decide
-- what list the customer is permitted to use. This function never selects
-- wholesale/VIP access for a user. Checkout integration still pending.
CREATE FUNCTION catalog.price_for_quantity(p_variant uuid,p_list uuid,p_quantity bigint,
 p_at timestamptz DEFAULT statement_timestamp())
RETURNS TABLE(price_id uuid, amount numeric, currency text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
 WITH source AS (
   SELECT p.price_id,p.amount,p.currency
   FROM catalog.price_at(p_variant,p_list,p_at) p
 )
 SELECT source.price_id,COALESCE(t.tier_amount,source.amount),source.currency
 FROM source
 LEFT JOIN LATERAL (
  SELECT tier_amount FROM catalog.price_quantity_tiers t
  WHERE t.tenant_id=iam.current_tenant_id()
  AND t.price_id=source.price_id AND t.quantity_range @> p_quantity
  LIMIT 1
 ) t ON true
 WHERE p_quantity>=1
$$;
REVOKE ALL ON FUNCTION catalog.price_for_quantity(uuid,uuid,bigint,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catalog.price_for_quantity(uuid,uuid,bigint,timestamptz) TO upc_runtime;
COMMIT;

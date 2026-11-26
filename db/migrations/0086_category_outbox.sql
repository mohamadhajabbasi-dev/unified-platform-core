-- 0086: extend the single transactional outbox to canonical categories and product category links.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test database required'; END IF; END $$;
ALTER TABLE ops.outbox_events DROP CONSTRAINT outbox_events_event_kind_check;
ALTER TABLE ops.outbox_events ADD CONSTRAINT outbox_events_event_kind_check
 CHECK(event_kind IN ('catalog.price_entry.changed','inventory.stock_ledger.changed','inventory.reservation.changed','catalog.price_list.changed','catalog.price_tier.changed','catalog.price_eligibility.changed','catalog.product.changed','catalog.variant.changed','catalog.category.changed','catalog.product_category.changed'));
-- Retain the historical function name and OID for 0078 compatibility.
-- No second writer, event store, payload or consumer is introduced.
CREATE OR REPLACE FUNCTION ops.capture_price_entry_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE k text;
BEGIN
 IF TG_WHEN<>'AFTER' OR TG_LEVEL<>'ROW' OR TG_OP NOT IN ('INSERT','UPDATE','DELETE') THEN
  RAISE EXCEPTION 'Invalid outbox trigger source' USING ERRCODE='42501';
 END IF;
 CASE TG_RELID
 WHEN 'catalog.price_entries'::regclass THEN k:='catalog.price_entry.changed';
 WHEN 'inventory.stock_ledger'::regclass THEN k:='inventory.stock_ledger.changed';
 WHEN 'inventory.reservations'::regclass THEN k:='inventory.reservation.changed';
 WHEN 'catalog.price_lists'::regclass THEN k:='catalog.price_list.changed';
 WHEN 'catalog.price_quantity_tiers'::regclass THEN k:='catalog.price_tier.changed';
 WHEN 'catalog.customer_price_decisions'::regclass THEN k:='catalog.price_eligibility.changed';
 WHEN 'catalog.products'::regclass THEN k:='catalog.product.changed';
 WHEN 'catalog.variants'::regclass THEN k:='catalog.variant.changed';
 WHEN 'catalog.categories'::regclass THEN k:='catalog.category.changed';
 WHEN 'catalog.product_categories'::regclass THEN k:='catalog.product_category.changed';
 ELSE RAISE EXCEPTION 'Invalid outbox trigger source' USING ERRCODE='42501';
 END CASE;
 IF TG_OP='UPDATE' THEN
  IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NULL; END IF;
  IF OLD.tenant_id IS DISTINCT FROM NEW.tenant_id THEN
   INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(OLD.tenant_id,k);
  END IF;
 END IF;
 IF TG_OP='DELETE' THEN
  INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(OLD.tenant_id,k);
 ELSE
  INSERT INTO ops.outbox_events(tenant_id,event_kind) VALUES(NEW.tenant_id,k);
 END IF;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION ops.capture_price_entry_change() FROM PUBLIC,upc_runtime,upc_platform_approver;
CREATE TRIGGER category_outbox AFTER INSERT OR UPDATE OR DELETE ON catalog.categories
 FOR EACH ROW EXECUTE FUNCTION ops.capture_price_entry_change();
CREATE TRIGGER product_category_outbox AFTER INSERT OR UPDATE OR DELETE ON catalog.product_categories
 FOR EACH ROW EXECUTE FUNCTION ops.capture_price_entry_change();
COMMIT;

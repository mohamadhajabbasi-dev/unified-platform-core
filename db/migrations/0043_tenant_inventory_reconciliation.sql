-- 0043: tenant-wide inventory reconciliation; no cross-currency summation, no period closure.
BEGIN;
DO $$ BEGIN IF current_database()<>'upc_greenfield_test' THEN RAISE EXCEPTION 'Test DB required'; END IF; END $$;
CREATE FUNCTION finance.tenant_inventory_asset_activity()
RETURNS TABLE(account_id uuid,currency text,inventory_net numeric,other_net numeric,other_line_count bigint,ledger_net numeric)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Tenant inventory reconciliation access denied' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 WITH classified AS (
 SELECT l.account_id AS aid,l.currency AS curr,l.amount AS amt,
 (j.supplier_invoice_id IS NOT NULL OR j.cogs_movement_id IS NOT NULL OR j.cogs_return_movement_id IS NOT NULL) AS is_inventory
 FROM finance.journal_lines l JOIN finance.journal_entries j USING(tenant_id,entry_id,currency)
 JOIN finance.accounts a ON a.tenant_id=l.tenant_id AND a.account_id=l.account_id AND a.currency=l.currency
 WHERE l.tenant_id=t AND a.account_type='asset'
 )
 SELECT c.aid,c.curr,COALESCE(sum(c.amt) FILTER(WHERE c.is_inventory),0),
 COALESCE(sum(c.amt) FILTER(WHERE NOT c.is_inventory),0),count(*) FILTER(WHERE NOT c.is_inventory),sum(c.amt)
 FROM classified c GROUP BY c.aid,c.curr HAVING bool_or(c.is_inventory)
 ORDER BY c.curr,c.aid;
END $$;
REVOKE ALL ON FUNCTION finance.tenant_inventory_asset_activity() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.tenant_inventory_asset_activity() TO upc_runtime;

CREATE FUNCTION finance.tenant_inventory_cost_totals()
RETURNS TABLE(currency text,captured_value numeric,inventory_journal_net numeric,other_asset_net numeric,ledger_net numeric,value_difference numeric)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id();
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Tenant inventory reconciliation access denied' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 WITH facts AS (
 SELECT vp.currency AS curr,sum(cf.value_delta) AS val
 FROM finance.movement_cost_facts cf JOIN finance.valuation_policies vp ON vp.tenant_id=cf.tenant_id AND vp.variant_id=cf.variant_id
 WHERE cf.tenant_id=t GROUP BY vp.currency
 ), posted AS (
 SELECT aa.currency AS curr,sum(aa.inventory_net) AS inv_net,sum(aa.other_net) AS outside_net,sum(aa.ledger_net) AS all_net
 FROM finance.tenant_inventory_asset_activity() aa GROUP BY aa.currency
 )
 SELECT COALESCE(f.curr,p.curr),COALESCE(f.val,0),COALESCE(p.inv_net,0),COALESCE(p.outside_net,0),COALESCE(p.all_net,0),
 COALESCE(f.val,0)-COALESCE(p.inv_net,0)
 FROM facts f FULL JOIN posted p ON f.curr=p.curr ORDER BY 1;
END $$;
REVOKE ALL ON FUNCTION finance.tenant_inventory_cost_totals() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.tenant_inventory_cost_totals() TO upc_runtime;

CREATE FUNCTION finance.tenant_inventory_cost_issues()
RETURNS TABLE(warehouse_id uuid,variant_id uuid,movement_id uuid,account_id uuid,currency text,issue_code text)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE t uuid:=iam.current_tenant_id(); scope record;
BEGIN
 IF t IS NULL OR NOT iam.has_permission('finance.read') OR NOT platform.module_enabled('finance')
 OR NOT iam.has_permission('inventory.read') OR NOT platform.module_enabled('inventory')
 OR NOT iam.has_permission('procurement.read') OR NOT platform.module_enabled('procurement')
 OR NOT iam.has_permission('sales.read') OR NOT platform.module_enabled('sales')
 THEN RAISE EXCEPTION 'Tenant inventory reconciliation access denied' USING ERRCODE='42501'; END IF;
 -- Enumerate from the canonical ledger, not just captured facts: missing policies cannot disappear.
 FOR scope IN SELECT DISTINCT l.warehouse_id AS wid,l.variant_id AS vid,p.currency AS curr
 FROM inventory.stock_ledger l LEFT JOIN finance.valuation_policies p ON p.tenant_id=l.tenant_id AND p.variant_id=l.variant_id
 WHERE l.tenant_id=t ORDER BY 1,2 LOOP
 IF scope.curr IS NULL THEN
 RETURN QUERY SELECT scope.wid,scope.vid,NULL::uuid,NULL::uuid,NULL::text,'valuation_policy_missing'::text;
 ELSE
 RETURN QUERY SELECT scope.wid,scope.vid,i.movement_id,NULL::uuid,scope.curr,i.issue_code
 FROM finance.inventory_cost_issues(scope.wid,scope.vid) i;
 END IF;
 END LOOP;
 RETURN QUERY SELECT NULL::uuid,NULL::uuid,NULL::uuid,NULL::uuid,a.currency,'tenant_inventory_value_mismatch'::text
 FROM finance.tenant_inventory_cost_totals() a WHERE a.value_difference<>0;
 -- Other postings may be legitimate but lack an inventory subledger attribution. Even net-zero
 -- outside activity requires review; don't silently treat it as inventory cost.
 RETURN QUERY SELECT NULL::uuid,NULL::uuid,NULL::uuid,a.account_id,a.currency,'inventory_asset_other_activity'::text
 FROM finance.tenant_inventory_asset_activity() a WHERE a.other_line_count>0;
END $$;
REVOKE ALL ON FUNCTION finance.tenant_inventory_cost_issues() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.tenant_inventory_cost_issues() TO upc_runtime;
CREATE FUNCTION finance.assert_tenant_inventory_cost_ready() RETURNS void
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $$
DECLARE first_issue record;
BEGIN
 SELECT * INTO first_issue FROM finance.tenant_inventory_cost_issues() LIMIT 1;
 IF FOUND THEN RAISE EXCEPTION 'Tenant inventory reconciliation incomplete: %',first_issue.issue_code USING ERRCODE='23514'; END IF;
END $$;
REVOKE ALL ON FUNCTION finance.assert_tenant_inventory_cost_ready() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION finance.assert_tenant_inventory_cost_ready() TO upc_runtime;
COMMIT;

# Migration numbering normalization — pre-production only

Baseline: 86deadf3f95edda175168eda605774546300e4ee. The previous CI used lexical full-filename order. This mapping preserves the exact order. Renamed SQL/test blobs retain original contents except the delimiter fix in the last migration. Historical logs, SQL comments and older documentation retain previous numbers. This map is authoritative. No deployed database or migration-history table is modified. Only the disposable greenfield database may be rebuilt; persistent migration runner requires a reviewed checksum/version baseline before use.

| Previous migration | Canonical migration | Previous test | Canonical test |
|---|---|---|---|
| `0001_core_crm.sql` | `0001_core_crm.sql` | `0001_core_crm.sql` | `0001_core_crm.sql` |
| `0002_iam_modules.sql` | `0002_iam_modules.sql` | `0002_iam_modules.sql` | `0002_iam_modules.sql` |
| `0003_crm_authorization.sql` | `0003_crm_authorization.sql` | `0003_crm_authorization.sql` | `0003_crm_authorization.sql` |
| `0004_catalog_pricing.sql` | `0004_catalog_pricing.sql` | `0004_catalog_pricing.sql` | `0004_catalog_pricing.sql` |
| `0005_inventory.sql` | `0005_inventory.sql` | `0005_inventory.sql` | `0005_inventory.sql` |
| `0006_sales.sql` | `0006_sales.sql` | `0006_sales.sql` | `0006_sales.sql` |
| `0007_returns_refunds.sql` | `0007_returns_refunds.sql` | `0007_returns_refunds.sql` | `0007_returns_refunds.sql` |
| `0008_finance.sql` | `0008_finance.sql` | `0008_finance.sql` | `0008_finance.sql` |
| `0009_finance_lifecycle.sql` | `0009_finance_lifecycle.sql` | `0009_finance_lifecycle.sql` | `0009_finance_lifecycle.sql` |
| `0010_platform_billing.sql` | `0010_platform_billing.sql` | `0010_platform_billing.sql` | `0010_platform_billing.sql` |
| `0011_tenant_dossier.sql` | `0011_tenant_dossier.sql` | `0011_tenant_dossier.sql` | `0011_tenant_dossier.sql` |
| `0012_commerce_entitlement.sql` | `0012_commerce_entitlement.sql` | `0012_commerce_entitlement.sql` | `0012_commerce_entitlement.sql` |
| `0013_content_crm_engagement.sql` | `0013_content_crm_engagement.sql` | `0013_content_crm_engagement.sql` | `0013_content_crm_engagement.sql` |
| `0013_web_analytics.sql` | `0014_web_analytics.sql` | `0013_web_analytics.sql` | `0014_web_analytics.sql` |
| `0014_catalog_details_price_tiers.sql` | `0015_catalog_details_price_tiers.sql` | `0014_catalog_details_price_tiers.sql` | `0015_catalog_details_price_tiers.sql` |
| `0014_shared_analytics.sql` | `0016_shared_analytics.sql` | `0014_shared_analytics.sql` | `0016_shared_analytics.sql` |
| `0015_app_distribution.sql` | `0017_app_distribution.sql` | `0015_app_distribution.sql` | `0017_app_distribution.sql` |
| `0015_hr_payroll_commissions.sql` | `0018_hr_payroll_commissions.sql` | `0015_hr_payroll_commissions.sql` | `0018_hr_payroll_commissions.sql` |
| `0016_customer_attribution.sql` | `0019_customer_attribution.sql` | `0016_customer_attribution.sql` | `0019_customer_attribution.sql` |
| `0017_four_prices.sql` | `0020_four_prices.sql` | `0017_four_prices.sql` | `0020_four_prices.sql` |
| `0018_pricing_hardening.sql` | `0021_pricing_hardening.sql` | `0018_pricing_hardening.sql` | `0021_pricing_hardening.sql` |
| `0019_procurement.sql` | `0022_procurement.sql` | `0019_procurement.sql` | `0022_procurement.sql` |
| `0020_supplier_finance.sql` | `0023_supplier_finance.sql` | `0020_supplier_finance.sql` | `0023_supplier_finance.sql` |
| `0021_inventory_transfers.sql` | `0024_inventory_transfers.sql` | `0021_inventory_transfers.sql` | `0024_inventory_transfers.sql` |
| `0022_inventory_trace.sql` | `0025_inventory_trace.sql` | `0022_inventory_trace.sql` | `0025_inventory_trace.sql` |
| `0023_trace_receipt_transfer.sql` | `0026_trace_receipt_transfer.sql` | `0023_trace_receipt_transfer.sql` | `0026_trace_receipt_transfer.sql` |
| `0024_tracked_sales.sql` | `0027_tracked_sales.sql` | `0024_tracked_sales.sql` | `0027_tracked_sales.sql` |
| `0025_allocation_cap_cost_basis.sql` | `0028_allocation_cap_cost_basis.sql` | `0025_allocation_cap.sql` | `0028_allocation_cap.sql` |
| `0026_valuation_preview.sql` | `0029_valuation_preview.sql` | `0026_valuation_preview.sql` | `0029_valuation_preview.sql` |
| `0027_valuation_policy.sql` | `0030_valuation_policy.sql` | `0027_valuation_policy.sql` | `0030_valuation_policy.sql` |
| `0028_movement_cost_facts.sql` | `0031_movement_cost_facts.sql` | `0028_movement_cost_facts.sql` | `0031_movement_cost_facts.sql` |
| `0029_fifo_cost_allocations.sql` | `0032_fifo_cost_allocations.sql` | `0029_fifo_cost_allocations.sql` | `0032_fifo_cost_allocations.sql` |
| `0030_fifo_cogs.sql` | `0033_fifo_cogs.sql` | `0030_fifo_cogs.sql` | `0033_fifo_cogs.sql` |

Next unused ID: **0034**. CI rejects invalid names, duplicates, gaps and mismatched migration/test ID sets before SQL application. Accounting rules remain provisional; no production approval implied.

Read-back correction FIX-008: actual one-character delimiter fix is committed separately after MIG-ID-001; both numbering and original SQL order were verified unchanged.

## Current continuation checkpoint (2026-11-25)
The original normalization table above is historical. Current canonical IDs 0001–0053 are contiguous and verified at run 45601424659. Next unused ID: **0054**; recheck tree and guard before allocating. TEST-063 adds no migration.

## BUILD-026Z candidate
0054_order_return_capacity.sql and matching acceptance test added; CI pending. Next unused ID 0055, verify tree first.

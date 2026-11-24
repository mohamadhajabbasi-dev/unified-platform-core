# Canonical target table dictionary v1 — requirements-first, not a legacy schema copy
**Evidence date**: 2026-11-24 | **Phase**: greenfield isolated build | **Status**: DRAFT/REVIEW, not full implementation.
Use with [complete 234-DbSet inventory](LEGACY_DBSET_COVERAGE_2026-11-24.md) and [source field evidence](SOURCE_FIELD_EVIDENCE_FA.md).

**Invariant:** one physical PostgreSQL operational database; canonical customer/product/tenant/user/order/ledger; composite tenant FKs + RLS; separate normalized 1:N tables for genuinely distinct facts; documented eligibility and audits. Do not create all candidates blindly: check existing migrations and entity responsibilities first.

| Area | Canonical tables / subordinate relations | Current greenfield status | Legacy evidence / business reason |
|---|---|---|---|
| core / tenancy | `tenants` | **EXISTING 0001** | Tenants / legal organization identity; One tenant per org; identity scope |
| core / tenancy | `tenant_profiles, tenant_stakeholders, tenant_addresses, tenant_settings` | **EXISTING 0011** | Legal, investor/partners, business addresses, typed config; Dependencies of tenants, NOT second organizations |
| core / tenancy | `business_locations (branches/stores)` | **DESIGN_REQUIRED** | ERP Branches; Commerce Stores; physical/online branches; Branch/store is a tenant child; don't promote to new tenant |
| core / tenancy | `sites_and_domains` | **DESIGN_REQUIRED** | Storefront channels, shop domains, web/app handoff; Tenant-owned site/app associations |
| core / tenancy | `external_parties` | **REVIEW_REQUIRED** | Companies, Suppliers, BusinessPartners; Separate corporate suppliers from own tenant and customer master without duplicating persons |
| iam / security | `users` | **EXISTING 0001** | ERP/Commerce Users; One global account identity |
| iam / security | `memberships, roles, permissions, role_grants, membership_roles` | **EXISTING 0001–0002** | Tenant staff access, platform IAM; Reused by every domain |
| iam / security | `membership_settings, platform_staff_assignments` | **EXISTING 0002/0011** | User employment context/settings; platform role; Distinct membership vs global user |
| iam / security | `user_auth_sessions, oauth_clients, revoked_tokens, device_authorizations` | **DESIGN_REQUIRED** | ERP/Commerce RefreshTokens, UserSessions, OAuth tokens, devices; Use hashed tokens, revocation, no raw secrets |
| iam / security | `security_policies, api_credentials_metadata, webhook_registrations` | **DESIGN_REQUIRED** | Allowed IP/country, API clients, webhooks; Secrets in vault; DB only scope and references |
| platform / subscription | `modules, tenant_module_grants, subscription_modules` | **EXISTING 0002/0012** | AppModule/tenant modules, purchased Commerce; Approval and purchased entitlement independent |
| platform / subscription | `subscriptions, subscription_invoices, billing_payments` | **EXISTING 0010** | Platform subscription billing; No mixing with tenant sales ledger |
| platform / subscription | `licenses, license_activations, licensed_devices, subscription_plans` | **DESIGN_REQUIRED** | ERP license/devices/plan records; Canonical licensing under platform |
| platform / subscription | `reseller_accounts, reseller_contracts, reseller_sales` | **DESIGN_REQUIRED** | ERP Resellers / ResellerSales; Platform distributors distinct from tenant sales |
| platform / subscription | `app_registry, app_releases, app_distribution_reports` | **DESIGN_REQUIRED** | ERP AppVersions/packages, Android installs, channel downloads; App telemetry not customer master |
| crm / party / support | `customers, customer_identifiers, customer_addresses` | **EXISTING 0001** | Both Customers, Commerce CustomerAddress; One tenant customer across all channels |
| crm / party / support | `conversations, conversation_messages, support_tickets, customer_consent_events` | **AUTHORED 0013 / TEST PENDING** | ERP CRM Service + Helpdesk; Commerce CustomerSupportMessages; CRM consent; No second customer; message body encrypted by application before storage |
| crm / party / support | `customer_tags, customer_tag_links, customer_merge_reviews` | **DESIGN_REQUIRED** | ERP CrmTags/MergeRecords, Commerce favorites; Controlled verified customer merge |
| crm / party / support | `counterparties and counterparty_roles` | **DESIGN_REQUIRED** | Suppliers, BusinessPartners, buyers/sellers; Propose FK/role design; don't force unrelated persons into customer table |
| crm / party / support | `customer_wallet_ledger, loyalty_transactions, credit_terms` | **DESIGN_REQUIRED** | Commerce wallets/loyalty, ERP credit limits/balances; Derived balances; no writable balance master |
| crm / party / support | `service_queues, sla_policies, support_feedback` | **DESIGN_REQUIRED** | ERP CRM service queues/SLA/feedback; Linked to existing support_tickets |
| catalog / pricing | `products, variants, categories, product_categories` | **EXISTING 0004** | ERP/Commerce products, variants, categories; Only tenant product master |
| catalog / pricing | `price_lists, price_entries` | **EXISTING 0004** | ERP Sale/Wholesale/Colleague/Promo prices; Commerce store prices; Single price source; multi-list and effective periods |
| catalog / pricing | `price_assignments, quantity_tiers, pricing_rules` | **DESIGN_REQUIRED** | ERP wholesale min qty; tenant VIP/colleague; app/site pricing; Rules refer to existing price entries not new pricing master |
| catalog / pricing | `brands, units, product_media, warranties` | **DESIGN_REQUIRED** | ERP product images/warranties/units/brands; Commerce product media; Product FK; object storage for large binaries |
| catalog / pricing | `product_reviews, product_favorites, stock_alert_subscriptions` | **DESIGN_REQUIRED** | Commerce ProductReviews, CustomerFavorites, ProductStockAlerts; Customer/product composite tenant FKs |
| catalog / pricing | `category_hierarchy, item_attributes, barcodes/labels` | **DESIGN_REQUIRED** | ERP product barcodes/prints/templates; Localized labels and derived code, no second product master |
| inventory / procurement | `warehouses, stock_ledger, reservations` | **EXISTING 0005** | ERP StockTransactions, Commerce InventoryMovements; Ledger source; balance view derived |
| inventory / procurement | `warehouse_transfers, transfer_lines, stock_adjustments` | **DESIGN_REQUIRED** | ERP WarehouseTransfer, InventoryAdjustment; Stock effects via stock_ledger only |
| inventory / procurement | `inventory_lots, serial_numbers, expiry_events, cost_layers` | **DESIGN_REQUIRED** | ERP serial, batch, expiry and cost layer; Distinct traceability/costing child data |
| inventory / procurement | `reorder_policies, procurement_requests, procurement_request_items` | **DESIGN_REQUIRED** | ERP InventoryReorderRule/PurchaseSuggestion; Planning is not physical stock |
| inventory / procurement | `purchase_orders, purchase_order_items, goods_receipts` | **DESIGN_REQUIRED** | ERP purchase invoice lines and suppliers; Supplier relation linked to payable financial document |
| inventory / procurement | `stock_assets, asset_movements` | **DESIGN_REQUIRED** | ERP StoreAsset/StoreAssetMovement; Asset register separate from sellable product stock |
| sales / shipping / tax / payments | `orders, order_items, verified_captures` | **EXISTING 0006** | ERP sales invoices, Commerce orders; Single canonical order, immutable snapshots |
| sales / shipping / tax / payments | `return_events, refund_events` | **EXISTING 0007** | ERP ReturnOrder/Commerce ReturnRequest/Refund; Distinct return/refund events linked to same order |
| sales / shipping / tax / payments | `promotions, coupons, rule_usage` | **DESIGN_REQUIRED** | Commerce Promotion, ERP discounts; Discounts and campaign eligibility, no alternative price master |
| sales / shipping / tax / payments | `shipping_methods, zones, rates, fulfillments, shipments` | **DESIGN_REQUIRED** | Commerce Shipping/fulfillments; ERP delivery tracking; One order shipping fulfillment lifecycle |
| sales / shipping / tax / payments | `fiscal_invoices, fiscal_invoice_lines, tax_rules, tax_submissions` | **DESIGN_REQUIRED** | ERP SaleInvoice, TaxInvoiceSubmission, ERP tax gateway; Commerce StoreTaxConfig; Fiscal invoice is distinct document linked 1:1/N to canonical order |
| sales / shipping / tax / payments | `payment_provider_events, reconciliation_inbox, installments` | **DESIGN_REQUIRED** | Commerce PaymentProviderEvent/DigitalCheck; ERP InstallmentContract; Idempotency, trusted gateway evidence |
| sales / shipping / tax / payments | `bank_accounts, cheques, bank_transactions, bank_reconciliations` | **DESIGN_REQUIRED** | ERP cash/cheque/bank accounting; Protected bank identifiers, derived balances |
| finance / payroll | `accounts, journal_entries, journal_lines, fiscal_periods` | **EXISTING 0008–0009** | ERP Account, AccountingDocuments and items, FiscalYear; Tenant double-entry ledger |
| finance / payroll | `receivables, payables, credit_limits, settlements` | **DESIGN_REQUIRED** | ERP customer debt, invoices, bills, employee advances; Financial obligations separated from balances |
| finance / payroll | `employees, employment_contracts, payroll_periods, payroll_lines` | **DESIGN_REQUIRED** | ERP Employees/EmployeeContracts/PayrollItems; Tenant HR with optional user FK, encrypted PII |
| finance / payroll | `employee_loans, advances, commission_plans, commission_entries` | **DESIGN_REQUIRED** | ERP loan, advance, commissions; Link to one employee and journal, not duplicated balances |
| finance / payroll | `tax_filing_jobs, e_invoice_submissions` | **DESIGN_REQUIRED** | ERP e-invoice, tax returns; External gateway submissions with audit |
| content / messaging / ai | `articles` | **AUTHORED 0013 / TEST PENDING** | Commerce Articles, ERP knowledge articles; One tenant article/content identity; separate KB type if needed |
| content / messaging / ai | `article_revisions, editorial_workflows, seo_settings` | **DESIGN_REQUIRED** | Commerce SeoAgentSetting/ArticleAutomationSettings; Version history and scheduling; not duplicate article master |
| content / messaging / ai | `content_assets, theme_packages, theme_assignments` | **DESIGN_REQUIRED** | ERP TenantTheme/ThemePackage/CDN assets; Central object storage metadata; no binary duplication |
| content / messaging / ai | `notifications, delivery_attempts, email_inboxes` | **DESIGN_REQUIRED** | Both Notifications, Commerce EmailMessages; Messages use existing conversation/message if same semantic; outbound delivery distinct |
| content / messaging / ai | `ai_jobs, ai_credits_ledger, ai_usage, provider_settings` | **DESIGN_REQUIRED** | Commerce AI wallets/jobs/provider; ERP AI messages/usage; A job/usage domain, provider credentials from vault |
| content / messaging / ai | `workflow_definitions, workflow_steps, workflow_runs` | **DESIGN_REQUIRED** | ERP workflow definitions/instances/action logs; References canonical entities, not shadow copies |
| market / operations / analytics | `integration_connections, external_id_mappings, delivery_outbox, inbound_inbox` | **DESIGN_REQUIRED** | ERP WooCommerce/Torob/SyncQueue, Commerce ERPPlus sync; External adapters only; no duplicate product/customer master |
| market / operations / analytics | `market_scans, offers, recommendations, competitor_prices` | **DESIGN_REQUIRED** | ERP BazaarYar/Market/Torob models; Tenant research/price snapshots distinct from actual sale price |
| market / operations / analytics | `audit_events` | **EXISTING 0011 (PARTIAL)** | ERP audit logs, security audit, Commerce AI audit; One extensible audit source, reliable actor and scope |
| market / operations / analytics | `health_metrics, incidents, app_crashes, job_runs` | **DESIGN_REQUIRED** | ERP server health, crash, logs and queues; Retention/aggregate/offline telemetry, not huge logs in OLTP |
| market / operations / analytics | `tenant_backup_jobs, backup_snapshots, restore_requests` | **DESIGN_REQUIRED** | ERP BackupJob/RestoreJob; Tenant restore without reverting other tenants |
| market / operations / analytics | `analytics.sessions, analytics.events, app_installations, distribution_reports, attribution` | **DESIGN_REQUIRED** | Commerce traffic, app activity, referrer, UTM; Anonymous sessions distinct from CRM customers, web/app shared model |

## Important architectural rules
- **Never create a `Customers` table for CRM, website, app, messenger or branch again.** Link sources and verified identities to `crm.customers` with tenant ID.
- **Do not create Product mirroring in an integration schema**: Torob/WooCommerce supplier/marketplace entities are external mapping/source observations with canonical variant/product FKs, not alternate price/inventory masters.
- **Price cardinality:** the existing `catalog.price_entries` supports concurrent price lists; group/channel/contract/volume rules are child policies and should not replicate price amounts.
- **Financial documents:** a sale order, fiscal invoice, payment capture, refund, accounting journal, payable, cheque and tax submission are *different legal/accounting records*; each has independent lifecycle and FK to canonical order/counterparty. That is normalization, not duplication.
- **Platform billing and tenant business accounting must remain distinct**; employees may have a user login, but the user's IAM account must not be duplicated as an HR identity.
- **Customer relationships:** suppliers/partners/third parties may have overlapping identities and distinct business roles; identity reconciliation must follow verified rules and approved scope. Do not auto-merge tenant users, CRM customers, suppliers and legal owners.
- **Device/app events:** visitor/session/download/first-open are distinct facts and all tenant data access must be isolated; web and app reuse one analytics event/session backbone.
- **Large files, secrets and oversized telemetry** belong in protected storage/aggregators. PostgreSQL retains authoritative IDs, ACLs and metadata; no raw secrets or actual private data in GitHub.
- **Legacy sources** are read-only from GitHub, used for migration field mapping only. No old DB changes/reads in the current phase.

## Coverage accounting
There are **57 canonical table groups** above; each group may represent one or more *distinct necessary physical tables*. The count does NOT equal number of deployed tables. Status labels show what exists in the **new isolated prototype** vs what requires clean design and implementation. Existing 0001–0012 include ~42 provisional tables if 0012 applies; migration 0013 adds 5 **if applied**. Full database remains unfinished.

## Execution checkpoints
1. Verify current migrations/test status and avoid concurrent schema duplication; check latest GitHub main.
2. Complete/verify 0013 (tenant content, CRM conversations/messages/support/consent) with synthetic regression + privacy review.
3. Develop missing canonical domains incrementally: catalog media/reviews/brands, purchasing+stock movements/lot-cost, shipping/promotions/fiscal tax, HR/payroll and bank reconciliation, licensing, messaging/AI/market/workflows/ops, app analytics and advanced pricing.
4. For each domain: detailed dictionary with PK/FK, RLS, encryption/privacy, lifecycle, validations, idempotency, indexes, migration/test, and owner decisions. Never migrate real data until new DB tested and separately authorized.
5. Handoff: append WORK_LOG and update PROJECT_STATE/NEXT_ACTIONS and commit actual SHA.

**Limit:** exact field-level parity for all 234 source DbSets is still a multi-pass task; the complete names and proposed domains are inventoried, not all class properties or deployed physical DB metadata checked. Don't claim otherwise.

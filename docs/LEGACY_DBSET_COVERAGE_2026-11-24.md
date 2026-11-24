# Legacy source DbSet coverage inventory — NOT the target database
Date: 2026-11-24 | Action: SOURCE-004 | Evidence: checked repository code only; **no existing live databases accessed or changed**.
These are **EF Core DbSet declarations, not verified physical SQL tables**. Names/types, ignored entities, table mappings, owned entities, migrations and production snapshots can differ. Counts indicate coverage of declarations; target new database must **not** contain one table per DbSet.

- ERPPlus: 182 DbSet declarations in [AppDbContext](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/master/ERPPlus.Infrastructure/Data/AppDbContext.cs); git blob `1117f7f6cc65911774e2f48a9ddd4065060615ab`.
- CommerceAI: 52 DbSet declarations in [ApplicationDbContext](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/main/backend/src/CommerceAI.Infrastructure/Persistence/ApplicationDbContext.cs); git blob `da55a081ec7caec99eb4d658f44c533dcd978718`.
- Combined declaration count **234** (some same concept; not necessarily 234 separate tables).
- Repository sources were read **only via GitHub**. Source repos, production DBs, server remain unchanged.

## Coverage and canonical target domains
Domain classification is an **initial semantic proposal based on name**, not a claim of verified field compatibility. Check actual entity classes and foreign keys before final SQL mapping.

| Canonical domain | ERPPlus DbSets | CommerceAI DbSets | Reuse/build decision (requirements-first) |
|---|---:|---:|---|
| Tenant / Organization | 9 | 3 | core.tenants, core.tenant_profiles, core.tenant_stakeholders, core.tenant_settings; ADD branches/stores/legal entities only as distinct relationships |
| Identity / Access | 14 | 2 | core.users, iam.memberships, iam.roles/permissions; ADD secure sessions, OAuth client grants, device posture (not duplicate users) |
| Modules / Licenses / Billing | 17 | 7 | platform.modules, module grants, subscription billing, purchased modules; ADD licenses, packages, AI wallet/credits, resale/channel contracts |
| CRM / Customers / Support | 20 | 3 | crm.customers + identifiers + addresses; ADD partner roles, CRM tickets/conversations/consents/communications without new Customer master |
| Catalog / Merchandise | 11 | 8 | catalog.products + variants/categories/price_lists/entries; ADD media/reviews/warranties/brand/unit/price rules using child FK |
| Inventory / Procurement | 16 | 1 | inventory.warehouses, stock_ledger, reservations; ADD purchase requests/invoices, transfers, valuation/lot/serial as necessary |
| Orders / Fulfillment / Promotion | 4 | 10 | sales.orders + order_items + returns/refunds; ADD fulfillment, shipping, coupons/discount rules, delivery/fulfillment events |
| Payments / Accounting / Tax | 17 | 7 | finance.accounts/journals, sales verified payments, platform billing; ADD tax/invoicing/reconciliation/installments/banking with separate legally distinct records |
| HR / Payroll / Commissions | 10 | 0 | NEW hr.employees/contracts/payroll/loans/commission plans as relations to core.users when login exists |
| Content / SEO / Theme | 4 | 4 | NEW content.articles/assets/revisions/seo settings; map themes/files to asset registry, not copied binary |
| Messaging / Notifications | 3 | 4 | NEW comm.channels/conversations/messages/inbox/notifications; CRM customer referenced when verified |
| AI / Automation | 6 | 3 | NEW ai.operations/jobs/usage/credits; provider config secrets external vault, distinct from customer/order/tenant masters |
| Integrations / Marketplace | 21 | 0 | NEW integration.connections/external_identity_mapping/jobs/events; legacy sync queues NOT new master records |
| Operations / Security | 23 | 0 | ops.audit_events and optional scoped monitoring, restore jobs; large logs/time series external storage or retention |
| Workflow / Rules | 4 | 0 | NEW workflow.definitions/steps/runs/actions; any entity reference links canonical table |
| REVIEW_OTHER | 3 | 0 | Needs entity-specific code verification; never auto-create mirrored table |

## Exact DbSet register (complete)
The `Legacy Entity Type` is the EF model and `Set` is the C# DbSet property, **not a promise of SQL table name**.


### ERPPlus — 182 entries

| # | DbSet property | Legacy entity type | Proposed logical domain |
|---:|---|---|---|
| 1 | `ElectronicCommercialExportHistories` | `ElectronicCommercialExportHistory` | Payments / Accounting / Tax |
| 2 | `InventoryCostLayers` | `InventoryCostLayer` | Inventory / Procurement |
| 3 | `TaxInvoiceSubmissions` | `TaxInvoiceSubmission` | Payments / Accounting / Tax |
| 4 | `TaxGatewaySettings` | `TaxGatewaySetting` | Payments / Accounting / Tax |
| 5 | `TaxProductMappings` | `TaxProductMapping` | Payments / Accounting / Tax |
| 6 | `ProductImages` | `ProductImage` | Catalog / Merchandise |
| 7 | `ProductPriceHistories` | `ProductPriceHistory` | Catalog / Merchandise |
| 8 | `AuditTrails` | `AuditTrail` | Operations / Security |
| 9 | `UserSessions` | `UserSession` | Identity / Access |
| 10 | `SecurityAuditLogs` | `SecurityAuditLog` | Operations / Security |
| 11 | `CdnAssets` | `CdnAsset` | Content / SEO / Theme |
| 12 | `FileStorageItems` | `FileStorageItem` | Content / SEO / Theme |
| 13 | `QueueJobs` | `QueueJob` | Operations / Security |
| 14 | `PluginPackages` | `PluginPackage` | Modules / Licenses / Billing |
| 15 | `ModulePackages` | `ModulePackage` | Modules / Licenses / Billing |
| 16 | `RedisStatuses` | `RedisStatus` | Operations / Security |
| 17 | `TenantModuleInstalls` | `TenantModuleInstall` | Modules / Licenses / Billing |
| 18 | `TenantPlugins` | `TenantPlugin` | Modules / Licenses / Billing |
| 19 | `UpdateClients` | `UpdateClient` | Operations / Security |
| 20 | `UpdatePackages` | `UpdatePackage` | Operations / Security |
| 21 | `SystemVersions` | `SystemVersion` | Operations / Security |
| 22 | `RestoreJobs` | `RestoreJob` | Operations / Security |
| 23 | `OAuthClients` | `OAuthClient` | Identity / Access |
| 24 | `BlacklistedDevices` | `BlacklistedDevice` | Identity / Access |
| 25 | `OAuthTokens` | `OAuthToken` | Identity / Access |
| 26 | `WebhookEndpoints` | `WebhookEndpoint` | REVIEW_OTHER |
| 27 | `AiConversations` | `AiConversation` | AI / Automation |
| 28 | `DeveloperApplications` | `DeveloperApplication` | REVIEW_OTHER |
| 29 | `AiMessages` | `AiMessage` | AI / Automation |
| 30 | `WhiteLabelBrands` | `WhiteLabelBrand` | Tenant / Organization |
| 31 | `PluginInstalls` | `PluginInstall` | Modules / Licenses / Billing |
| 32 | `CrashReports` | `CrashReport` | Operations / Security |
| 33 | `SystemHealths` | `SystemHealth` | Operations / Security |
| 34 | `SystemLogs` | `SystemLog` | Operations / Security |
| 35 | `AppUpdatePackages` | `AppUpdatePackage` | Operations / Security |
| 36 | `ThemePackages` | `ThemePackage` | Content / SEO / Theme |
| 37 | `SystemErrorLogs` | `SystemErrorLog` | Operations / Security |
| 38 | `TenantThemes` | `TenantTheme` | Content / SEO / Theme |
| 39 | `Permissions` | `Permission` | Identity / Access |
| 40 | `RolePermissions` | `RolePermission` | Identity / Access |
| 41 | `SubscriptionInvoices` | `SubscriptionInvoice` | Modules / Licenses / Billing |
| 42 | `AppVersions` | `AppVersion` | Operations / Security |
| 43 | `TenantLicenses` | `TenantLicense` | Modules / Licenses / Billing |
| 44 | `ActivityLogs` | `ActivityLog` | Operations / Security |
| 45 | `Notifications` | `Notification` | Messaging / Notifications |
| 46 | `HelpDeskTickets` | `HelpDeskTicket` | CRM / Customers / Support |
| 47 | `HelpDeskMessages` | `HelpDeskMessage` | CRM / Customers / Support |
| 48 | `HelpDeskAttachments` | `HelpDeskAttachment` | CRM / Customers / Support |
| 49 | `HelpDeskAudits` | `HelpDeskAudit` | CRM / Customers / Support |
| 50 | `BusinessInsights` | `BusinessInsight` | AI / Automation |
| 51 | `Tenants` | `Tenant` | Tenant / Organization |
| 52 | `SyncQueues` | `SyncQueue` | Integrations / Marketplace |
| 53 | `SubscriptionPlans` | `SubscriptionPlan` | Modules / Licenses / Billing |
| 54 | `PublicSiteContentSettings` | `PublicSiteContentSetting` | Tenant / Organization |
| 55 | `TenantSubscriptions` | `TenantSubscription` | Modules / Licenses / Billing |
| 56 | `StoreSettings` | `StoreSetting` | Tenant / Organization |
| 57 | `WooCommerceProductMappings` | `WooCommerceProductMapping` | Integrations / Marketplace |
| 58 | `WooCommerceOrderImports` | `WooCommerceOrderImport` | Integrations / Marketplace |
| 59 | `AiInsights` | `AiInsight` | AI / Automation |
| 60 | `Companies` | `Company` | Tenant / Organization |
| 61 | `BusinessPartners` | `BusinessPartner` | CRM / Customers / Support |
| 62 | `InvestorProfiles` | `InvestorProfile` | Tenant / Organization |
| 63 | `CrmContactPersons` | `CrmContactPerson` | CRM / Customers / Support |
| 64 | `CrmCommunicationPoints` | `CrmCommunicationPoint` | CRM / Customers / Support |
| 65 | `CrmPartnerAddresses` | `CrmPartnerAddress` | CRM / Customers / Support |
| 66 | `CrmTags` | `CrmTag` | CRM / Customers / Support |
| 67 | `CrmBusinessPartnerTags` | `CrmBusinessPartnerTag` | CRM / Customers / Support |
| 68 | `CrmConsentRecords` | `CrmConsentRecord` | CRM / Customers / Support |
| 69 | `CrmPartnerMergeRecords` | `CrmPartnerMergeRecord` | CRM / Customers / Support |
| 70 | `CrmPartnerAuditEvents` | `CrmPartnerAuditEvent` | CRM / Customers / Support |
| 71 | `CrmServiceQueues` | `CrmServiceQueue` | CRM / Customers / Support |
| 72 | `CrmSlaPolicies` | `CrmSlaPolicy` | CRM / Customers / Support |
| 73 | `CrmKnowledgeArticles` | `CrmKnowledgeArticle` | CRM / Customers / Support |
| 74 | `CrmServiceFeedbacks` | `CrmServiceFeedback` | CRM / Customers / Support |
| 75 | `CrmServiceAuditEvents` | `CrmServiceAuditEvent` | CRM / Customers / Support |
| 76 | `AuditLogs` | `AuditLog` | Operations / Security |
| 77 | `Branches` | `Branch` | Tenant / Organization |
| 78 | `FiscalYears` | `FiscalYear` | Payments / Accounting / Tax |
| 79 | `Users` | `User` | Identity / Access |
| 80 | `Roles` | `Role` | Identity / Access |
| 81 | `UserRoles` | `UserRole` | Identity / Access |
| 82 | `SubscriptionPayments` | `SubscriptionPayment` | Modules / Licenses / Billing |
| 83 | `Products` | `Product` | Catalog / Merchandise |
| 84 | `ProductVariants` | `ProductVariant` | Catalog / Merchandise |
| 85 | `ProductWarranties` | `ProductWarranty` | Catalog / Merchandise |
| 86 | `ProductLabelTemplates` | `ProductLabelTemplate` | Catalog / Merchandise |
| 87 | `ProductBarcodeTemplates` | `ProductBarcodeTemplate` | Catalog / Merchandise |
| 88 | `ProductPrintJobs` | `ProductPrintJob` | Catalog / Merchandise |
| 89 | `Categories` | `Category` | Catalog / Merchandise |
| 90 | `Brands` | `Brand` | Catalog / Merchandise |
| 91 | `Units` | `Unit` | Catalog / Merchandise |
| 92 | `SqlPerformanceLogs` | `SqlPerformanceLog` | Operations / Security |
| 93 | `ApiPerformanceLogs` | `ApiPerformanceLog` | Operations / Security |
| 94 | `StockTransactions` | `StockTransaction` | Inventory / Procurement |
| 95 | `InventoryAdjustments` | `InventoryAdjustment` | Inventory / Procurement |
| 96 | `InventoryAdjustmentItems` | `InventoryAdjustmentItem` | Inventory / Procurement |
| 97 | `StockReservations` | `StockReservation` | Inventory / Procurement |
| 98 | `StockReservationItems` | `StockReservationItem` | Inventory / Procurement |
| 99 | `InventoryReorderRules` | `InventoryReorderRule` | Inventory / Procurement |
| 100 | `Warehouses` | `Warehouse` | Inventory / Procurement |
| 101 | `WarehouseTransfers` | `WarehouseTransfer` | Inventory / Procurement |
| 102 | `WarehouseTransferItems` | `WarehouseTransferItem` | Inventory / Procurement |
| 103 | `BackgroundJobLogs` | `BackgroundJobLog` | Operations / Security |
| 104 | `Customers` | `Customer` | CRM / Customers / Support |
| 105 | `Suppliers` | `Supplier` | CRM / Customers / Support |
| 106 | `SaleInvoices` | `SaleInvoice` | Orders / Fulfillment / Promotion |
| 107 | `SalesOrigins` | `SaleOrigin` | REVIEW_OTHER |
| 108 | `SaleInvoiceItems` | `SaleInvoiceItem` | Orders / Fulfillment / Promotion |
| 109 | `InstallmentContracts` | `InstallmentContract` | Payments / Accounting / Tax |
| 110 | `SaleInstallments` | `SaleInstallment` | Payments / Accounting / Tax |
| 111 | `PurchaseInvoices` | `PurchaseInvoice` | Inventory / Procurement |
| 112 | `PurchaseInvoiceItems` | `PurchaseInvoiceItem` | Inventory / Procurement |
| 113 | `ReturnOrders` | `ReturnOrder` | Orders / Fulfillment / Promotion |
| 114 | `ReturnOrderItems` | `ReturnOrderItem` | Orders / Fulfillment / Promotion |
| 115 | `Payments` | `Payment` | Payments / Accounting / Tax |
| 116 | `Cheques` | `Cheque` | Payments / Accounting / Tax |
| 117 | `CashBoxes` | `CashBox` | Payments / Accounting / Tax |
| 118 | `BankAccounts` | `BankAccount` | Payments / Accounting / Tax |
| 119 | `BankCheckbooks` | `BankCheckbook` | Payments / Accounting / Tax |
| 120 | `BankReconciliations` | `BankReconciliation` | Payments / Accounting / Tax |
| 121 | `Employees` | `Employee` | HR / Payroll / Commissions |
| 122 | `PayrollPeriods` | `PayrollPeriod` | HR / Payroll / Commissions |
| 123 | `PayrollItems` | `PayrollItem` | HR / Payroll / Commissions |
| 124 | `EmployeeContracts` | `EmployeeContract` | HR / Payroll / Commissions |
| 125 | `EmployeeLoans` | `EmployeeLoan` | HR / Payroll / Commissions |
| 126 | `EmployeeAdvances` | `EmployeeAdvance` | HR / Payroll / Commissions |
| 127 | `CommissionPlans` | `CommissionPlan` | HR / Payroll / Commissions |
| 128 | `CommissionRules` | `CommissionRule` | HR / Payroll / Commissions |
| 129 | `SalesCommissions` | `SalesCommission` | HR / Payroll / Commissions |
| 130 | `CommissionSettlements` | `CommissionSettlement` | HR / Payroll / Commissions |
| 131 | `Accounts` | `Account` | Payments / Accounting / Tax |
| 132 | `AccountingDocuments` | `AccountingDocument` | Payments / Accounting / Tax |
| 133 | `AccountingDocumentItems` | `AccountingDocumentItem` | Payments / Accounting / Tax |
| 134 | `LicenseKeys` | `LicenseKey` | Modules / Licenses / Billing |
| 135 | `AppModules` | `AppModule` | Modules / Licenses / Billing |
| 136 | `TenantFeatures` | `TenantFeature` | Modules / Licenses / Billing |
| 137 | `RegisteredDevices` | `RegisteredDevice` | Identity / Access |
| 138 | `TenantModules` | `TenantModule` | Modules / Licenses / Billing |
| 139 | `AiUsageLogs` | `AiUsageLog` | AI / Automation |
| 140 | `RefreshTokens` | `RefreshToken` | Identity / Access |
| 141 | `DeviceLicenses` | `DeviceLicense` | Modules / Licenses / Billing |
| 142 | `SyncHistories` | `SyncHistory` | Integrations / Marketplace |
| 143 | `SyncConflicts` | `SyncConflict` | Integrations / Marketplace |
| 144 | `AiPlugins` | `AiPlugin` | AI / Automation |
| 145 | `LicenseActivations` | `LicenseActivation` | Modules / Licenses / Billing |
| 146 | `ServerNodes` | `ServerNode` | Operations / Security |
| 147 | `SystemAnnouncements` | `SystemAnnouncement` | Messaging / Notifications |
| 148 | `ApiClients` | `ApiClient` | Identity / Access |
| 149 | `AllowedCountries` | `AllowedCountry` | Identity / Access |
| 150 | `LicenseAuditLogs` | `LicenseAuditLog` | Modules / Licenses / Billing |
| 151 | `AllowedIps` | `AllowedIp` | Identity / Access |
| 152 | `NotificationMessages` | `NotificationMessage` | Messaging / Notifications |
| 153 | `Resellers` | `Reseller` | Tenant / Organization |
| 154 | `PaymentGatewaySettings` | `PaymentGatewaySetting` | Payments / Accounting / Tax |
| 155 | `ServerHealthLogs` | `ServerHealthLog` | Operations / Security |
| 156 | `ResellerSales` | `ResellerSale` | Tenant / Organization |
| 157 | `ApiRequestLogs` | `ApiRequestLog` | Operations / Security |
| 158 | `BackupJobs` | `BackupJob` | Operations / Security |
| 159 | `PurchaseSuggestions` | `PurchaseSuggestion` | Inventory / Procurement |
| 160 | `PurchaseSuggestionItems` | `PurchaseSuggestionItem` | Inventory / Procurement |
| 161 | `TorobStores` | `TorobStore` | Integrations / Marketplace |
| 162 | `TorobProductMappings` | `TorobProductMapping` | Integrations / Marketplace |
| 163 | `TorobMonitoringRuns` | `TorobMonitoringRun` | Integrations / Marketplace |
| 164 | `TorobPriceSnapshots` | `TorobPriceSnapshot` | Integrations / Marketplace |
| 165 | `TorobProducts` | `TorobProduct` | Integrations / Marketplace |
| 166 | `TorobYarSettings` | `TorobYarSetting` | Integrations / Marketplace |
| 167 | `TorobStoreReportItems` | `TorobStoreReportItem` | Integrations / Marketplace |
| 168 | `MarketScans` | `MarketScan` | Integrations / Marketplace |
| 169 | `MarketScanItems` | `MarketScanItem` | Integrations / Marketplace |
| 170 | `MarketOffers` | `MarketOffer` | Integrations / Marketplace |
| 171 | `MarketRecommendations` | `MarketRecommendation` | Integrations / Marketplace |
| 172 | `BazaarYarCompetitorSites` | `BazaarYarCompetitorSite` | Integrations / Marketplace |
| 173 | `MarketDiagnosticReviews` | `MarketDiagnosticReview` | Integrations / Marketplace |
| 174 | `BazaarYarTenantSettings` | `BazaarYarTenantSettings` | Integrations / Marketplace |
| 175 | `BazaarYarScanJobs` | `BazaarYarScanJob` | Integrations / Marketplace |
| 176 | `BazaarYarScanJobItems` | `BazaarYarScanJobItem` | Integrations / Marketplace |
| 177 | `WorkflowDefinitions` | `WorkflowDefinition` | Workflow / Rules |
| 178 | `WorkflowInstances` | `WorkflowInstance` | Workflow / Rules |
| 179 | `WorkflowActionLogs` | `WorkflowActionLog` | Workflow / Rules |
| 180 | `WorkflowSteps` | `WorkflowStep` | Workflow / Rules |
| 181 | `StoreAssets` | `StoreAsset` | Inventory / Procurement |
| 182 | `StoreAssetMovements` | `StoreAssetMovement` | Inventory / Procurement |

### CommerceAI — 52 entries

| # | DbSet property | Legacy entity type | Proposed logical domain |
|---:|---|---|---|
| 1 | `Tenants` | `Tenant` | Tenant / Organization |
| 2 | `TenantModuleAssignments` | `TenantModuleAssignment` | Modules / Licenses / Billing |
| 3 | `TenantAiWallets` | `TenantAiWallet` | Modules / Licenses / Billing |
| 4 | `TenantAiCreditTransactions` | `TenantAiCreditTransaction` | Modules / Licenses / Billing |
| 5 | `AiCreditPackages` | `AiCreditPackage` | Modules / Licenses / Billing |
| 6 | `AiOperationPricing` | `AiOperationPricing` | Modules / Licenses / Billing |
| 7 | `AiCreditPurchases` | `AiCreditPurchase` | Modules / Licenses / Billing |
| 8 | `AiCreditPurchaseSettings` | `AiCreditPurchaseSettings` | Modules / Licenses / Billing |
| 9 | `AiProviderSettings` | `AiProviderSettings` | AI / Automation |
| 10 | `Stores` | `Store` | Tenant / Organization |
| 11 | `Users` | `User` | Identity / Access |
| 12 | `RefreshTokens` | `RefreshToken` | Identity / Access |
| 13 | `Categories` | `Category` | Catalog / Merchandise |
| 14 | `Products` | `Product` | Catalog / Merchandise |
| 15 | `ProductCategories` | `ProductCategory` | Catalog / Merchandise |
| 16 | `ProductAiJobs` | `ProductAiJob` | AI / Automation |
| 17 | `ProductAiAuditEvents` | `ProductAiAuditEvent` | AI / Automation |
| 18 | `ProductReviews` | `ProductReview` | Catalog / Merchandise |
| 19 | `ProductVariants` | `ProductVariant` | Catalog / Merchandise |
| 20 | `StoreProductVariants` | `StoreProductVariant` | Catalog / Merchandise |
| 21 | `InventoryMovements` | `InventoryMovement` | Inventory / Procurement |
| 22 | `Customers` | `Customer` | CRM / Customers / Support |
| 23 | `Articles` | `Article` | Content / SEO / Theme |
| 24 | `ArticleAutomationSettings` | `ArticleAutomationSetting` | Content / SEO / Theme |
| 25 | `SeoAgentSettings` | `SeoAgentSetting` | Content / SEO / Theme |
| 26 | `ArticleFavorites` | `ArticleFavorite` | Content / SEO / Theme |
| 27 | `CustomerFavorites` | `CustomerFavorite` | Catalog / Merchandise |
| 28 | `CustomerSupportMessages` | `CustomerSupportMessage` | CRM / Customers / Support |
| 29 | `CustomerAddresses` | `CustomerAddress` | CRM / Customers / Support |
| 30 | `WalletTransactions` | `WalletTransaction` | Payments / Accounting / Tax |
| 31 | `LoyaltyTransactions` | `LoyaltyTransaction` | Payments / Accounting / Tax |
| 32 | `ProductStockAlerts` | `ProductStockAlert` | Catalog / Merchandise |
| 33 | `Notifications` | `Notification` | Messaging / Notifications |
| 34 | `EmailMailboxes` | `EmailMailbox` | Messaging / Notifications |
| 35 | `EmailMessages` | `EmailMessage` | Messaging / Notifications |
| 36 | `EmailAttachments` | `EmailAttachment` | Messaging / Notifications |
| 37 | `Orders` | `Order` | Orders / Fulfillment / Promotion |
| 38 | `OrderItems` | `OrderItem` | Orders / Fulfillment / Promotion |
| 39 | `Payments` | `Payment` | Payments / Accounting / Tax |
| 40 | `DigitalCheckPlans` | `DigitalCheckPlan` | Payments / Accounting / Tax |
| 41 | `DigitalCheckInstallments` | `DigitalCheckInstallment` | Payments / Accounting / Tax |
| 42 | `PaymentProviderEvents` | `PaymentProviderEvent` | Payments / Accounting / Tax |
| 43 | `Refunds` | `Refund` | Payments / Accounting / Tax |
| 44 | `Promotions` | `Promotion` | Orders / Fulfillment / Promotion |
| 45 | `ShippingMethods` | `ShippingMethod` | Orders / Fulfillment / Promotion |
| 46 | `ShippingZones` | `ShippingZone` | Orders / Fulfillment / Promotion |
| 47 | `ShippingZoneRates` | `ShippingZoneRate` | Orders / Fulfillment / Promotion |
| 48 | `StoreTaxConfigurations` | `StoreTaxConfiguration` | Tenant / Organization |
| 49 | `ReturnRequests` | `ReturnRequest` | Orders / Fulfillment / Promotion |
| 50 | `ReturnItems` | `ReturnItem` | Orders / Fulfillment / Promotion |
| 51 | `Fulfillments` | `Fulfillment` | Orders / Fulfillment / Promotion |
| 52 | `FulfillmentItems` | `FulfillmentItem` | Orders / Fulfillment / Promotion |

## Evidence from representative real entity fields (not guesses)
- ERPPlus `Product`: name, code/barcode, purchase/sale/wholesale/colleague prices, wholesale minimum quantity, variants, warranties, brand/unit, tax, discount, stock, serial/batch/expiry, reorder/safety stock and media. Target uses **one product/variant master + existing multiple price lists + inventory ledger**; the existing prototype still lacks several rules.
- ERPPlus `Customer`: name, mobile, contact, personal/legal IDs, pricing type, credit limits, balances, business partner link, external references. Target preserves one tenant customer and models credit/financial ledger separately.
- ERPPlus `Employee`: personnel code, contract/pay, insurance, bank and dependent information. These are **sensitive HR data**, never put in this GitHub repo; keep HR as tenant domain.
- ERPPlus `SaleInvoice`: channel, external order reference, sales person, customer, discount/tax/shipping, line items, branch/warehouse. Sales order vs fiscal invoice are distinct business obligations, but should share one canonical transaction reference.
- CommerceAI `Article`: store+tenant, slug, title/body, cover image, tags, SEO title/description, published flags/times; needs tenant content domain without separate duplicated article master.
- CommerceAI `Order`: customer address snapshots, subtotal/tax/shipping/discount, promotion, shipping method/zone, order source and payment/sync lifecycle; order snapshots are immutable historical records, not duplicated live entities.
- CommerceAI `Promotion`, `ShippingMethod`, `Payment`: eligibility/limits/periods, delivery rates, provider transaction ids; require separate child-domain records linked to existing canonical order/payment.
- Source entity field evidence is version-pinned in `docs/SOURCE_FIELD_EVIDENCE_FA.md` (to be maintained); **do not store any real personal/financial data here**.

## Required mapping process
For each legacy DbSet, record target canonical entity, `REUSE | DEPENDENT | NEW | CONFIG_OR_TELEMETRY | RETIRE_SYNC | UNKNOWN`, field-level transformation, key/tenant mapping, lifecycle and data retention. Where the current target already has a canonical table, **reuse/extend** it; never create another master. Never interpret name-only inference as complete parity. For 234 declarations, complete class-by-class properties and relationships in later evidence passes before any actual migration of old data.

## Priority candidates from gaps (not 234 CREATE TABLE commands)
1. Content/SEO and CRM conversations/messages/consent, commerce customer support and notifications.
2. Purchasing/supplier/returns, warehouses transfers/cost/lot/serial, sales fulfillment/shipping/promotions/tax.
3. Finance banking/cheques/installments, HR/payroll/commission, tax filing, platform licenses/subscriptions.
4. AI jobs/usage/wallet/credits, integrations, ERP workflows, audit/backup and app telemetry.
5. Commerce app sessions/visits/download reports and multi-price rules **using the current canonical models**.

**This inventory is sourced from actual code but the target grouping is design inference**. No claim that all underlying data is implemented in the new schema.

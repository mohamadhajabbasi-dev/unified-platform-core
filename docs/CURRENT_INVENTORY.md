# CURRENT_INVENTORY — فاز 01 / شواهد کد، نه دیتابیس زنده
تاریخ: 2026-11-24 | Action: INV-002 | وضعیت: PARTIAL / LIVE_SCHEMA_BLOCKED

## منابع ثابت
- ERPPlus master: `52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049`؛ درخت کامل، 2875 فایل.
- CommerceAI main: `e7ae9b09f21c042e56407f593b99258fe280b20a`؛ درخت کامل، 952 فایل.
- هیچ فایل تنظیمات محرمانه، connection string واقعی، رکورد مشتری یا دامپ خوانده/منتشر نشده.
- Desktop Commander: هر دو دستگاه Offline؛ اتصال به موتور عملیاتی و اجرای SQL انجام نشد.

## مغایرت موتور
| پروژه | ادعای اولیه | شواهد کد | موتور عملیاتی |
|---|---|---|---|
| ERPPlus | MySQL | Microsoft.EntityFrameworkCore.SqlServer 10.0.9، UseSqlServer در Program و AppDbContextFactory | UNKNOWN؛ نیازمند تأیید metadata |
| CommerceAI | PostgreSQL | Npgsql.EntityFrameworkCore.PostgreSQL 10.0.3 و UseNpgsql در DependencyInjection | UNKNOWN؛ نیازمند تأیید metadata |

منابع: [ERP csproj](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Infrastructure/ERPPlus.Infrastructure.csproj#L25-L30)، [ERP Program](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Api/Program.cs#L91)، [ERP factory](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Infrastructure/Data/AppDbContextFactory.cs#L13)، [Commerce csproj](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/CommerceAI.Infrastructure.csproj#L19)، [Commerce DI](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/DependencyInjection.cs#L67).

## مدل‌های موجود در EF (نمونه اولویت‌دار؛ نام DbSet لزوماً نام جدول فیزیکی نیست)
| دامنه | ERPPlus | CommerceAI |
|---|---|---|
| تننت/فروشگاه | Tenants, Companies, Branches, StoreSettings | Tenants, Stores |
| IAM | Users, Roles, UserRoles, Permissions, RolePermissions, RefreshTokens | Users, RefreshTokens |
| ماژول | AppModules, TenantModules, TenantModuleInstalls, TenantFeatures | TenantModuleAssignments |
| مشتری/CRM | Customers, BusinessPartners, CrmContactPersons, CrmCommunicationPoints, CrmPartnerAddresses | Customers, CustomerAddresses, CustomerFavorites, CustomerSupportMessages |
| کالا | Products, ProductVariants, Categories, Brands, ProductImages | Products, ProductVariants, Categories, ProductCategories, StoreProductVariants |
| قیمت | ProductPriceHistories, Product.SalePrice | StoreProductVariant.Price |
| انبار | Warehouses, StockTransactions, StockReservations, InventoryCostLayers, WarehouseTransfers | InventoryMovements, StoreProductVariant.StockQuantity |
| فروش | SaleInvoices, SaleInvoiceItems, SalesOrigins, ReturnOrders | Orders, OrderItems, ReturnRequests, Fulfillments |
| مالی | Payments, Cheques, AccountingDocuments, Accounts | Payments, Refunds, WalletTransactions, DigitalCheckPlans, DigitalCheckInstallments |
| عملیات | SyncQueues, SyncHistories, SyncConflicts, WebhookEndpoints, AuditTrails | Notifications, ProductAiAuditEvents, TenantAiWallets |

منابع: [ERP AppDbContext](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Infrastructure/Data/AppDbContext.cs#L35-L199)، [Commerce ApplicationDbContext](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Persistence/ApplicationDbContext.cs#L36-L87). این فهرست کامل جداول نیست.

## Gate قبل از تکمیل
از replica/backup موجود یا حساب از قبل مجاز و فقط‌خواندنی (بدون ساخت حساب روی production) موتور/نسخه و database هدف را تأیید کن؛ سپس metadata schema, tables, columns/types/nullability, PK/FK, unique/index, views, triggers, jobs, RLS/policies, grants و حجم تقریبی را جمع کن. SQL Server: sys.* catalog و در صورت مجوز metadata مربوط به jobs؛ PostgreSQL: pg_catalog/information_schema؛ اگر MySQL واقعاً تأیید شد information_schema. از SELECT روی جداول کسب‌وکار، COUNT سنگین، استخراج متن حاوی secret، dump و DDL/DML خودداری کن. محدودیت زمان/بار و خروجی پاک‌سازی‌شده لازم است. وضعیت هر قلم UNKNOWN تا دریافت شواهد؛ مخزن فقط metadata غیرحساس.

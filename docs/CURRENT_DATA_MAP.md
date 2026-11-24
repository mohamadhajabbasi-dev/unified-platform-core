# CURRENT_DATA_MAP — ماتریس اولیه همپوشانی (غیرنهایی)
Action INV-002 | 2026-11-24 | CODE_EVIDENCE_ONLY
هیچ جدول مقصد یا مالکیت نهایی تصویب نشده است. هم‌نام بودن به معنای تکرار رکورد یا یکسان بودن semantics نیست.

| مفهوم | ERPPlus | CommerceAI | شاهد و جهت/ریسک | قاعده پیشنهادی برای بررسی |
|---|---|---|---|---|
| تننت | Tenants, Companies, Branches | Tenants, Stores | رابطه واقعی شناسه‌ها نامعلوم | نگاشت تننت/فروشگاه/شعبه؛ عدم ادغام بین تننت‌ها |
| مشتری | Customers + BusinessPartners | Customers | Commerce pushes upsert؛ ERP ابتدا ExternalCustomerId سپس mobile/email؛ ERP هم Customer و هم BusinessPartner را می‌نویسد | یک پرونده هویت تأییدشده در هر تننت؛ روابط CRM حفظ؛ تعارض‌ها دستی |
| مشتری چندفروشگاهی | Customers | Customers | Commerce unique(TenantId, StoreId, Phone/Email/ExternalId) جداگانه؛ ErpPlusCustomerId index غیر unique در مدل | خطر چند پرونده در فروشگاه‌های یک تننت؛ اول بررسی همه روابط و هویت؛ StoreId ارتباط کانال است نه مرز هویت نهایی |
| محصول | Products, ProductVariants | Products, ProductVariants | Pull ERP ExternalProductId scoped by TenantId؛ variant پیش‌فرض از ERP product id | تطبیق external id + tenant، SKU/barcode به‌تنهایی کافی نیست؛ حفظ variants |
| قیمت | Product.SalePrice, ProductPriceHistories | StoreProductVariant.Price | catalog pull؛ ERP price update endpoint؛ تغییر تازه Commerce در برابر snapshot محافظت می‌شود | ownership فیلدی و قیمت فروشگاه؛ ارز/گرد کردن و snapshot سفارش بررسی شود |
| موجودی | StockTransactions, Warehouses, Reservations | InventoryMovements, StoreProductVariant.StockQuantity | ERP stock pull به listing | تفکیک ledger/reservation/balance؛ بررسی انبار و جلوگیری از کسر دوباره |
| فروش | SaleInvoices, SaleInvoiceItems | Orders, OrderItems | سفارش eligible به ERP sales ارسال می‌شود | سفارش و سند حسابداری نقش متفاوت دارند؛ نگاشت و idempotency، نه حذف کور |
| پرداخت | Payments, Cheques | Payments, Refunds, DigitalCheckInstallments | همپوشانی مفهومی؛ مرجع فعلی اثبات نشده | حفظ شناسه درگاه، تسویه، اقساط، ledger؛ عدم ثبت دوباره |
| ماژول و IAM | AppModules, TenantModules, Users, Roles, Permissions | TenantModuleAssignments, Users | دو مدل فعلی؛ تطبیق واقعی نامعلوم | مجوز مرکزی، scope و تأیید مدیر کل؛ RLS نیازمند طراحی/تست |
| محتوا | ProductImages, Product description | Product description, SEO/AI, images | ERP توضیح فقط seed در صورت شرایط، محتوای نوشته‌شده Commerce متعلق به تننت | حفظ محتوای اختصاصی؛ overwrite ممنوع |

منابع ثابت:
- [Commerce customer unique keys](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Persistence/Configurations/CustomerConfiguration.cs)
- [ERP customer upsert](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Api/Controllers/CommerceSyncController.cs#L520-L640)
- [Commerce catalog import](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Integrations/ErpPlusSyncService.cs#L140-L280)
- [Commerce order selection](https://github.com/mohamadhajabbasi-dev/CommerceAI/blob/e7ae9b09f21c042e56407f593b99258fe280b20a/backend/src/CommerceAI.Infrastructure/Integrations/ErpPlusSyncService.cs#L384-L430)
- [ERP price endpoint](https://github.com/mohamadhajabbasi-dev/ERPPlus/blob/52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049/ERPPlus.Api/Controllers/CommerceSyncController.cs#L451-L483)

## نقشه انتقال پیشنهادی برای فازهای بعد (نه دستور اجرا)
1. تأیید metadata و tenant/store/branch identity map؛ ثبت mapping source system + scope + legacy key، بدون ذخیره داده واقعی در GitHub.
2. فهرست مالکیت هر فیلد و وابستگی FK؛ بررسی تعارض‌ها و موارد ambiguous؛ تأیید مالک.
3. در staging جدا بعد از تأیید ERD/ADR: مرجع tenant/IAM/module، مشتری و روابط، catalog/variant، price/inventory، order/payment/finance و dependent data به ترتیب واقعی FK. حفظ شناسه‌های قدیمی، سوابق و snapshot مالی؛ reconciliation و تست isolation/idempotency.
4. cutover/rollback با بکاپ قابل بازیابی، تطبیق totals و آزمون رگرسیون؛ هیچ sync فعلی قبل از اثبات صحت و تأیید خاموش نشود.

هیچ تعداد رکورد تکراری، PK/FK فیزیکی، حجم واقعی، ترتیب نهایی یا زمان مهاجرت تأیید نشده است.

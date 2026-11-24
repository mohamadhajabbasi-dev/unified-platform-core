# GITHUB_ONLY_DISCOVERY_PLAN — ادامه بدون نیاز به Desktop Commander

تاریخ: 2026-11-24 | Phase 01 | Status: SOURCE_ONLY / NO_LIVE_DB_ACCESS
این برنامه با استفاده از GitHub قابل ادامه است؛ دسترسی به سرور/دیتابیس برای این فاز **شرط شروع کار نیست**. تفاوت source vs deployed schema همیشه صریح اعلام شود.

## شواهد تازه راستی‌آزمایی‌شده
- CommerceAI: `backend/src/CommerceAI.Infrastructure/Persistence/Configurations/CustomerConfiguration.cs` (blob SHA `a1deec9944bff2a8f9093a5bdd07ffadebd998e9`): جدول Customers، کلید ID، ایندکس غیریکتای (TenantId,StoreId) و سه ایندکس یکتای (TenantId,StoreId,Email / Phone / ExternalId) مشروط به NOT NULL. اندیس (TenantId,StoreId,ErpPlusCustomerId) یکتا **نیست**. FK به Store با Cascade. این **تنها قانون مدل فعلی** است، نه اثبات اجرای migration در تولید.
- ERPPlus: `ERPPlus.Infrastructure/Data/AppDbContext.cs` (blob SHA `1117f7f6cc65911774e2f48a9ddd4065060615ab`) هم `Customers` و هم `BusinessPartners` را به‌عنوان DbSet اعلام می‌کند، همراه با `CrmContactPersons`، `CrmCommunicationPoints`، `CrmPartnerAddresses` و `CrmPartnerMergeRecords`. نگاشت و قواعد ادغام باید پیش از طراحی جدید بررسی شوند. در OnModelCreating ایندکس یکتایی بر (TenantId, ExternalSource, ExternalCustomerId) برای Customer مشروط به not deleted وجود دارد. این به تنهایی تضمین یکتایی مشتری در سطح Tenant با phone نیست.

## ادامه کار با GitHub فقط، بدون تماس با سرور
1. **کشف کامل کد مشتری** در هر دو repo: entity/DTO، API endpoint، upsert، normalization، duplicate merge، migrationهای EF، خواندنِ customer از سفارش، store scope و mapping بین مشتری و business partner.
2. **جدول منبع واحد پیشنهادی** برای مشتری بنویس، نه SQL عملیاتی: tenant-owned customer identity، شماره‌های تماس تأییدشده، آدرس‌ها، source identities، store/channel link، provenance و audit؛ قواعد تعارض و شناسه قدیمی.
3. **کشف محصول**: entity/variant/SKU/barcode، pricing/stock، نگاشت tenant/store و ownership فیلدها. شواهد را از کد واقعی همراه با GitHub path/SHA ثبت کن.
4. **کشف IAM و Module Registry**: کد کنونی tenant، user, role, permission, module، flow تأیید و سطح host؛ تفاوت بین موجود و هدف.
5. **کشف سفارش و مالی**: paid order، invoice، payment، refund، idempotency و ledger؛ اشتباه نگرفتن سند تجاری با سند حسابداری.
6. **گزارش گپ‌های کشف**: هر رفتار موجود را با برچسب CODE_EVIDENCE و هر پدیده غیرقابل‌اثبات بدون دیتابیس با UNKNOWN مشخص کن.
7. **ADR/ERD اولیه فقط برای بازبینی** پس از تکمیل source inventory؛ بدون کدنویسی مخرب و بدون migration production.

## قاعده حساس مشتری
مقصد: یک پرونده Customer برای هر تننت در هر هویت تأییدشده؛ یک مشتری در تننت A و B می‌تواند پرونده مجزا داشته باشد. شماره‌ها را استانداردسازی کن؛ برای شماره‌های مشترک خانوادگی/تغییرمالکیت، merge خودکار انجام نده؛ نیازمند سیاست احراز هویت/تعارض مصوب. `StoreId` جایگزین `TenantId` برای مرز هویت نیست.

## توقف‌ها و حدود
- GitHub به‌تنهایی تعداد رکورد تکراری، نسخه واقعاً deploy شده، engine تولید، فعال بودن sync و integrity واقعی DB را تأیید نمی‌کند؛ این بخش‌ها تا مرحله pre-cutover باز می‌مانند.
- GitHub Actions حق ندارد بدون تأیید مشخص‌شده به production DB متصل شود یا mutation انجام دهد.
- اطلاعات شخصی، password، connection string، secret و دامپ را commit نکن.
- در هیچ وضعی کاربر مجبور به اتصال مکرر Desktop Commander برای ادامه **بررسی کد** نیست.

## اولین اقدام دقیق بعدی
بازخوانی `AGENTS.md` و `ai-handoff/PROJECT_STATE.md`؛ سپس بررسی فایل‌های مشتری و migrationهای دو مخزن در GitHub و ثبت ماتریس دقیقِ field-level در `docs/CUSTOMER_SOURCE_AUDIT.md`. بعد از هر اقدام `WORK_LOG` append، `PROJECT_STATE` و `NEXT_ACTIONS` آپدیت و commit واقعی.

# طرح آزمایشی شعب و سایت‌های تننت — REVIEW-029A
تاریخ 2026-11-25 | مبنای کد: aaf1bf5e490e36b6412b513f1956d32b0f9a8612 | فقط طراحی، بدون DDL یا استقرار.

## شواهد ساختار موجود
- 0001: core.tenants تنها هویت سازمان، core.users و iam.memberships تنها هویت/عضویت. crm.customers در سطح تننت، نه شعبه.
- 0011: core.tenant_addresses دارای PK مرکب (tenant_id,address_id) و address_kind در registered/billing/operating؛ متن، کشور و کد پستی فقط در همین مرجع. core.tenant_settings دارای website_host (nullable، الگوی ساده lowercase) است. ثبت مستقیم runtime با مجوز tenant.settings.write و audit وجود دارد. این فیلد هنوز مالکیت DNS/مسیر درخواست را ثابت نمی‌کند.
- 0005: inventory.warehouses دارای PK مرکب و UNIQUE(tenant_id,warehouse_key)، مستقل از آدرس و شعبه؛ نام/هویت انبار تکرار نشود. جریان‌های 0005–0060 بر warehouse_id استوارند.
- 0014/0016: نشست و رویداد به analytics.sessions/events منتقل شده‌اند؛ web eligibility تابع platform.commerce_eligible (0012) است. هیچ master مستقل وب/موبایل ایجاد نشود.
- 0016: platform.applications/app_releases موجودند؛ اپلیکیشن یک سایت یا شعبه نیست.
- 0011: ops.audit_events مشترک است. ops.record_dossier_change فعلاً stakeholder_id/address_id/user_id/tenant_id را برای entity_id می‌شناسد؛ برای location_id باید دقیق و سازگار توسعه یابد. مقدار آدرس یا دامنه نباید در audit تکثیر شود.
- 0002/0055: RLS و module_enabled/has_permission موجود؛ هیچ مدل نقش یا مجوز موازی.
- TARGET_ERD_V0_FA و TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA صریحاً نیاز به چند فروشگاه/سایت و ارتباط با مرجع واحد مشتری/رویداد را دارند. بررسی definitions فوق و scan ساختاری 60 migration در REVIEW-029؛ جستجوی indexed برای website_host/business_locations نتیجه نداد، این امر اثبات نبود caller نیست. قبل از تغییر website_host بررسی literal تمام فایل‌های SQL/test لازم است.

## 0061 — پیشنهاد حداقلی، بدون تخصیص قطعی شماره
یک جدول core.business_locations فقط برای هویت واحد عملیاتی فیزیکی (شعبه/فروشگاه)، نه انبار یا tenant دیگر:
- tenant_id UUID NOT NULL REFERENCES core.tenants; location_id UUID NOT NULL DEFAULT gen_random_uuid(); PRIMARY KEY(tenant_id,location_id).
- location_key text NOT NULL، کلید پایدار tenant-scoped محدود به lowercase ASCII letters/digits/_.- با طول 1..80 و UNIQUE(tenant_id,location_key)؛ display_name text NOT NULL، nonblank 1..200.
- location_kind text NOT NULL CHECK IN ('branch','store')؛ address_id UUID NULL به core.tenant_addresses با FK مرکب (tenant_id,address_id)؛ بدون متن آدرس تکراری. NULL برای draft/عدم تکمیل داده؛ این جدول فعال‌سازی فروشگاه عملیاتی را انجام نمی‌دهد. is_active فقط وضعیت اداری رکورد است، نه entitlement یا مجوز فروش.
- زمان created_at server-owned؛ key/id/tenant/created_at immutable در runtime؛ NO DELETE یا TRUNCATE برای runtime. نوع قابل تغییر یا ثابت بودن باید در تست و قرارداد مشخص شود (پیشنهاد ثابت برای شناسه کسب‌وکار). index روی (tenant_id,address_id) برای FK.
- مجوزهای پیشنهادی tenant.locations.read و tenant.locations.write در iam.permissions؛ RLS ENABLE+FORCE؛ SELECT نیاز به tenant scope و read؛ INSERT/UPDATE هر دو read/write و tenant scope در USING/WITH CHECK. از module gate موجود برای capability-specific استفاده شود؛ خود شناسنامه شعبه تابع ماژول فروش/انبار نیست و هیچ دسترسی به داده‌های آن‌ها نمی‌دهد. هیچ grant به PUBLIC؛ عدم دسترسی به آدرس حساس از طریق این جدول (فقط FK، خواندن آدرس همچنان tenant.legal.read). grant column-specific INSERT بدون created_at؛ UPDATE فقط display_name/address_id/is_active.
- audit از ops.record_dossier_change با افزودن location_id در مسیر انتخاب target (حفظ همه اولویت‌های قبلی و ownership/search_path). AFTER INSERT/UPDATE؛ mapped actor و tenant scope، ثبت entity_id واقعی؛ هیچ audit table/trigger function موازی. اگر audit یا timestamp غیرقابل جعل با مسیر existing ACL ممکن نیست، بررسی و اصلاح محدود قبل از CI.
- اتصال انبار به شعبه فعلاً ممنوع: یک انبار ممکن است به چند فروشگاه خدمت دهد و رابطه یک به چند/چند به چند هنوز تعیین نشده؛ هیچ ستون warehouse_id در شعبه، و هیچ تغییر در stock_ledger/reservations/orders در 0061. سایت ممکن است فروشگاه فیزیکی نداشته باشد؛ هیچ site master در 0061.

## تست‌های لازم 0061
1. دو تننت و سه runtime نقش: writer/read-only/بدون مجوز. ایجاد دو شعبه در A با یک آدرس مرجع، B همان location_key مجاز؛ duplicate در A رد؛ invalid key/kind/name رد. FK آدرس خارجی یا ناموجود رد؛ FK same tenant معتبر؛ index و FORCE RLS/ACL بررسی.
2. SELECT/INSERT/UPDATE cross-tenant رد یا صفر ردیف طبق RLS؛ read-only UPDATE/INSERT رد، بدون مجوز SELECT صفر؛ tenant/key/id/created_at UPDATE و created_at explicit INSERT با runtime denied؛ DELETE/TRUNCATE و audit مستقیم رد.
3. audit دقیق برای insert/update با location_id/actor/tenant؛ rollback و rejected request بدون audit اضافی؛ no sensitive value copied؛ آزمون 0011 unchanged.
4. همان location_key دو درخواست واقعی همزمان برای یک تننت: unique serialization؛ یکی commit و دیگری unique violation، بدون audit اضافی. اگر SQL-only fixture قادر به اثبات رقابت نیست، تست دو session واقعی اضافه شود و در workflow اجرا گردد. retry semantics صرفاً uniqueness conflict تا زمان API contract؛ ادعای idempotent write نکن.
5. همه baseline SQL و concurrency و actual return upgrade؛ no financial effect, no stock/order changes. هیچ new migration تا CI دقیق 45641015000 موفق نشده.

## سایت و دامنه — طرح مرحله پس از شعب
- مسئله اصلی: website_host موجود را نباید در registry دوباره ذخیره کرد. اول inventory تمام reference/caller/test و semantics (اطلاع تماس در برابر authoritative routing). Registry پیشنهادی یک site tenant child مستقل از customer/product؛ host به‌صورت canonical یک‌بار، یک host می‌تواند alias یک سایت باشد؛ multi-site distinct from domain.
- انتخاب الگوی مهاجرت website_host (تبدیل به FK/derived view یا حذف بعد از migration امن) هنوز تصویب نشده؛ dual-write یا synchronization ممنوع. تاریخچه 0011 تغییر نکند؛ migration افزایشی و تست واقعی committed pre-registry settings (NULL/valid/invalid legacy host/duplicate across tenants)، بدون silently dropping/claiming host یا ساخت سایت از آدرس اطلاع‌رسانی.
- host normalization: ASCII DNS/A-label، lowercase، بدون scheme/path/port/userinfo/whitespace/leading/trailing dot، حدود 63 هر label و 253 کل؛ IDNA از لایه معتبر خارج DB، بدون auto claim؛ exact globally unique verified routing ownership فقط پس از اثبات مالکیت و approval policy. نام رزروشده/مالکیت/expiry/reassignment و side-channel از uniqueness در طراحی جدا بررسی شود. هیچ credential/DNS secret/verification token واقعی در GitHub. هیچ routing یا DNS فعال نمی‌شود.
- entitlement platform.commerce_eligible و permission gate قبل از فعال‌سازی storefront/collector؛ حفظ shared analytics.sessions/events. در مرحله آینده nullable tenant-aware site_id برای history بدون site؛ ثبت جدید از trusted server-resolved site, نه host/tenant ارسالی کلاینت؛ عدم دسترسی cross-tenant و disabled/revoked site. Existing web analytics without site remains compatible until explicit approved transition. سایت و app master نباید merge شوند.
- تصمیم‌های تجاری/امنیتی: مالکیت دامنه و reassignment، shared host/path routing و شعبه-انبار cardinality، activation/expiry؛ نهایی نشده و عملیات خارجی مجاز نیست.

## مسائل باز حفظ‌شده
commit-time module expiry و pre-barrier recorded_at در 0055 و تست‌های قبلی حل نشده‌اند؛ partial/damaged/expired receipt، quarantine، refund/valuation هم بدون سیاست مصوب فعال نشوند. هیچ دسترسی به ERPPlus/CommerceAI یا production.


## TEST-082 / BUILD-029B — 2026-11-25
- Verified exact 0060 checkpoint SHA aaf1bf5e490e36b6412b513f1956d32b0f9a8612, run 45641015000 SUCCESS, foundation 139299347881 and return-upgrade 139299347939 SUCCESS; logs 60 contiguous pairs, 86 tables, 69 PASS suites, 24 COGS races. Reviewed current HEAD c88c0afd092089987915a67a749641ae21090339.
- Authored 0061_business_locations.sql with one physical business-location child, tenant-scoped immutable identity and composite existing address FK, RLS/ACL, exact existing audit writer target extension. No warehouse/host/site/stock/order changes. Address binding additionally requires existing tenant.legal.read; server generates ID/timestamp; location_kind immutable. Explicit location-key conflict, not silent retry or API idempotency; runtime create retry requires future reviewed exact-payload contract. Non-null address on UPDATE requires legal read (including other field updates); address text remains protected. No grant to new permissions except synthetic tests. Metadata only; no module or sales activation.
- Matching rollback SQL test and real competing unique-index write shell test added; workflow adds one step before COGS, existing suites unchanged. Candidate expected 61 migration/test pairs, 87 tables, 71 PASS (61 SQL + 10 concurrent), plus independent return history upgrade. Runtime CI PENDING. No production or legacy access. Temporal expiry/pre-barrier timing, partial/quarantine/refund policy unchanged.

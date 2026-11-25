# DECISIONS — مصوبات و ابهام‌ها

## توافق‌های قطعی مالک
- D-001: یک دیتابیس عملیاتی واحد؛ PostgreSQL هدف اولیه، مشروط به بررسی و تست.
- D-002: هر مشتری فقط یک پرونده **برای همان تننت**؛ در تننت‌های دیگر پرونده مستقل مجاز.
- D-003: تمام کانال‌ها اطلاعات مشتری همان تننت را تکمیل کنند؛ بدون ثبت تکراری.
- D-004: محصول مرجع واحد؛ قیمت، موجودی و تنظیمات اختصاصی هر تننت.
- D-005: مدیر کل نظارت و دسترسی سراسری ثبت‌شده دارد؛ کارمندان پلتفرم و تننت‌ها نقش مستقل.
- D-006: فعال‌سازی ماژول برای تننت با تأیید مدیر کل.
- D-007: حسابداری هر تننت از درآمد و مالی خود پلتفرم جدا است.
- D-008: بکاپ داده تننتی و بکاپ کل پروژه با سیاست‌های دسترسی متفاوت.
- D-009: API همگام‌سازی بین **دو منبع داده تکراری** حذف شود؛ API امن مرکزی حفظ شود.
- D-010: هیچ کار یا جدول تکراری؛ همه تغییراتِ واقعی باید فوری در GitHub ثبت شوند.
- D-011: بدون اجازه و برنامه بازگشت، تغییر در تولید ممنوع.
## موارد باز و نیازمند تأیید
- O-001: الگوی دقیق identity / RLS / granularity دسترسی فیلدی.
- O-002: قواعد هویت‌سنجی شماره و ادغام مشتریان قدیمی در هر تننت.
- O-003: global catalog یا catalog tenant-owned، تعارض شناسه و SKU.
- O-004: سازوکار قیمت، مالیات، ارز، چندانبار و snapshot سفارش.
- O-005: پیاده‌سازی backup تک‌تننت، RPO/RTO و retention.
- O-006: بار کاری واقعی، الزامات SLO و زیرساخت staging/production.
- O-007: تطبیق ساختار واقعی دیتابیس‌ها و ترتیب cutover.
**قانون:** تصمیم جدید تنها با ADR و تأیید مالک نهایی می‌شود؛ پیشنهاد را قطعی معرفی نکن.

## D-012 — معماری مقصد مستقل از طراحی‌های قدیمی
مالک صریحاً اصلاح کرد: هدف ایجاد یک دیتابیس **نو، تمیز، بدون تکرار و مبتنی بر نیازهای گفته‌شده** است؛ **نه** استخراج و تقلید کامل جدول‌های ERPPlus و CommerceAI. بررسی legacy فقط برای نگاشت و مهاجرت داده‌ها و شناخت وابستگی‌هاست. نقشه هدف با نیازهای کاربری شروع می‌شود، سپس صحت قابلیت انتقال داده قدیمی سنجیده می‌شود. مرجع: `docs/TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA.md`. بدون تأیید مالک به تولید تغییری اعمال نکن.

## D-013 — مسیر قطعی توسعه مستقل (دستور مالک 2026-11-24)
- فقط مخزن unified-platform-core؛ درخواست Desktop Commander و اتصال به ERPPlus/CommerceAI/سرور یا دیتابیس‌های فعلی در فاز فعلی ممنوع، حتی برای خواندن. هیچ تنظیم، داده، سورس یا سرویس legacy تغییر نکند.
- PostgreSQL کاملاً جدید بر پایه نیازمندی‌ها؛ توسعه و DDL نسخه‌بندی‌شده و تست روی محیط آزمایشی دورریختنی مستقل GitHub مجاز است. برای کار عادی در این محدوده توقف جهت تأیید جداگانه لازم نیست.
- تصمیم‌های باز را به صورت فرضیه فنی آزمایشی، قابل بازنگری، ثبت کن؛ تصمیم نهایی معماری/انتقال داده/استقرار یا اتصال هر برنامه عملیاتی صرفاً پس از تأیید صریح مالک و برنامه مهاجرت و rollback.
- قبل از هر مرحله AGENTS، PROJECT_STATE، WORK_LOG، NEXT_ACTIONS، TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA و TARGET_ERD_V0_FA را بخوان؛ گزارش و نتیجه تست را commit و SHA را بررسی کن.


## D-014 — داده کامل تننت و انتساب مشتری/بازدید (تصریح جدید مالک)
- هر تننت یک شناسنامه واحد شامل مشخصات فردی/حقوقی، شرکا/سهامداران/نمایندگان، آدرس‌ها و تنظیمات دارد؛ با حفظ `core.tenants` به‌عنوان مرجع سازمان، نه جدول Tenant تکراری.
- کاربران تننت و تنظیماتشان به حساب `core.users` و عضویت `iam.memberships` مرتبط هستند؛ User موازی ممنوع.
- اگر تننت Commerce را خریداری کرده و مجوز فعال‌سازی مدیر کل را دارد، بازدیدکننده‌ها، نشست‌ها، منابع و کمپین‌های ورودی ثبت و جداگانه برای همان تننت گزارش شوند.
- ثبت منبع جذب مشتری از هر کانال به `crm.customers` مرجع همان تننت متصل باشد و برای هر کانال مشتری دوم نسازد. Visitor ناشناس مستقل از Customer شناسایی‌شده است.
- جزییات طراحی و آزمون: `docs/TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA.md`. انتخاب تعداد/نام جداول و قواعد حقوقی/حریم‌خصوصی همچنان پیشنهادی و نیازمند بازبینی است.


## D-015 — اپلیکیشن‌ها و چندقیمتی (نیازمندی مالک، اجرای فنی تدریجی)
- ثبت جداگانه دانلودهای رسمی، نصب/اولین اجرا، نشست/بازدید، تعامل، نسخه و پایداری، منبع جذب و فروش اپ هر تننت؛ وابسته به مجوز معتبر محصول/ماژول و RLS.
- از یک مرجع اصلی تحلیلی مشترک برای session و event وب و اپ استفاده کن؛ مشتری و سفارش اصلی فقط در crm و sales بمانند. اسناد analytics نمایه/رویداد هستند نه master دوباره.
- **چندقیمتی با `catalog.price_lists`/`price_entries` موجود** باید برای خرده، عمده، همکاری، VIP، کانال فروش، ارز، تعداد و بازه تکمیل شود؛ ساخت جدول قیمت مستقل تکراری ممنوع. قیمت نهایی سرور و snapshot سفارش الزامی.
- قوانین دقیق اولویت، واجدشرایط بودن، تخفیف و مالیات هنوز برای مصوبه مالک/سیاست مالی باز هستند؛ تحت نام «تست‌شده» یا «انجام‌شده» گزارش نشوند.
- مرجع: `docs/APP_ANALYTICS_MULTI_PRICE_FA.md`. دسترسی به هر دیتابیس/سورس عملیاتی یا درخواست Desktop Commander در این فاز ممنوع.


## D-016 — پوشش کامل دامنه‌های داده و طراحی استاندارد به جای کپی
- طبق دستور جدید مالک، اطلاعات قابل ذخیره هر دو برنامه ERPPlus و CommerceAI باید در مدل جدید پوشش داده شوند؛ موجودیت‌های تکراری فقط یک مرجع مرکزی دارند.
- استخراج سورس ۱۸۲ DbSet در ERPPlus و ۵۲ DbSet در CommerceAI را نشان داد. این رقم «فهرست اعلان EF Core» است، نه شمارش جدول فیزیکی یا تمام اطلاعات استقرار.
- در `docs/LEGACY_DBSET_COVERAGE_2026-11-24.md` فهرست دقیق نام‌ها و در `docs/CANONICAL_TARGET_TABLE_DICTIONARY_V1_FA.md` دامنه‌های مقصد و وضعیت پیاده‌سازی ثبت شد. فیلدهای نمونه با سند `SOURCE_FIELD_EVIDENCE_FA.md` مستند شدند.
- اسکریپت‌های `0013`, `0014`, `0015` فقط برای دیتابیس جدید و تست مستقل نوشته شده‌اند؛ موفقیت آزمون و مصوبه نهایی هنوز لازم است. قبل از ساخت هر جدول دیگر، این‌ها را دوباره بررسی کن.
- تمام اطلاعات موجود در کدها از جمله HR، بانک، تامین‌کننده، انبار، نقدی/اقساط، محتوا، هوش مصنوعی، سئو، مارکت، رویداد و یکپارچه‌سازی باید به‌صورت دامنه جدا ولی با FK معتبر به همان مرجع مرکزی طراحی شوند؛ هیچ داده واقعی یا سری از گذشته اکنون منتقل نشود.


### Scope clarification — D-016 supersedes only the source-read part of D-013
Owner's latest request **explicitly permits read-only inspection of GitHub source files in ERPPlus and CommerceAI** to inventory their data models. This **does not** permit altering either source repository, accessing either operational database, running migrations there, connecting to the original server, or requesting Desktop Commander. All new code and documentation writes remain confined to `unified-platform-core`.


## D-017 — چهار نوع قیمت اصلی کالا (2026-11-24)
مالک چهار نوع قیمت پایه برای هر محصول/تنوع در تننت مشخص کرد: ۱) اصلی، ۲) تخفیف‌خورده، ۳) همکار، ۴) عمده. چند فهرست قیمت در `catalog.price_lists`/`catalog.price_entries` فعلی امکان ذخیره هر چهار مقدار را دارد؛ `price_quantity_tiers` به قیمت موجود وابسته است. انتخاب قیمت/تخفیف معتبر/صلاحیت همکار و عمده نیازمند تکمیل SQL، API و تست است؛ نقش‌ها و تخفیف نباید به‌صورت خودکار برای مشتری عمومی افشا شوند. متن تصمیم و تست‌ها: `docs/FOUR_PRODUCT_PRICE_TYPES_FA.md`.


## D-018 — migration identity normalization (owner-directed)
- Canonical unique contiguous four-digit numeric prefix plus snake_case suffix; corresponding SQL acceptance test shares numeric ID. Historical sequence preserved by one-to-one filename mapping in db/MIGRATION_ID_MAP.md. Do not rewrite SQL solely to change historical comments. CI preflight mandatory. Disposable greenfield only; production migration tracking/checksums require separate review. Accounting policy remains unapproved for production.

### D-018 / TEST-063 — review note (not a new approved accounting decision)
- No change to owner-approved policy. Retain 0053 conservative fail-closed behavior; test the existing module-decision API and real history before considering new SQL. Historical as-of, expiry during a statement and privileged bypass are open design/security review items, not certified. No new canonical entity or parallel close API.

### TEST-064 — temporal review (open, not approved)
- 0051 explicitly checks recorded_at and posted_at cutoff, not captured_at; whether documented late costing may be finalized at close is unapproved. Statement-time module expiry is not reevaluated by repeating same statement-time check. Privileged DB operations require separate trust boundary. Synthetic historical fixture projection is not runtime policy; no migration changes.

### TEST-065 — temporal characterization only (no new policy approval)
- Preserve 0053 runtime code. Late cost capture and within-statement module expiry observations are characterization tests, not desired accounting/security policy; if behavior changes, review and update the observation rather than treating current behavior as an invariant. Privileged login/grant checks cover only selected synthetic roles/relations, not all production operations. Owner approval remains required for final effective-date, cutoff and entitlement semantics.

### DESIGN-0054 — return design proposal (not owner-approved)
- Reuse canonical return/refund headers, order/items, stock ledger, cost facts, allocations and journal. Per-return line fact candidate only for independent receipt/disposition; validate all existing structures first. Preserve cap/identity/availability and legacy full-return retries. Final disposition, partial cost allocation/rounding, effective date and refund policies remain open; no runtime or production change.

### BUILD-026Z — provisional read-only evidence
- Reuse existing tracked evidence and full-return keys; no new storage or write API. Derived remaining quantity is evidence of current legacy physical return capacity only, not financial approval, inspection result, or guarantee of eligible return. No owner-approved change to financial policy.

### BUILD-027A — provisional conservative safeguards, not final policy
- Late capture of pre-cutoff movements blocks close rather than inventing accounting effective dates or rewriting facts. Module decision lookup shared, ordinary statement-time RLS unchanged; live validity for new close is checked under existing locks and before/after write. No claim of transaction-commit validation, global expiry semantics, or historical as-of. Owner to decide late adjustments and whether entitlement must persist through commit, plus return financial/disposition policies.

### REVIEW-027A — open, no policy change
- A live check at function return is not a durable commit-time guarantee. Do not rely on a deferred trigger alone or change global RLS semantics. The proposed deterministic tests distinguish real timestamp ordering from synthetic cutoff projection. No changes to runtime behavior; approval needed for final financial and commit entitlement policy.

### FIX-027A — synthetic fixture isolation
- Role keys are tenant-local, not globally unique. All committed concurrency fixture bootstrap queries must explicitly restrict tenant/user scope, even when names are namespaced. Preserve uniqueness constraints; do not suppress duplicate-grant failures. No runtime decision or policy change.

### REVIEW-027B — independent event gap confirmed; proposal only
- No current equivalent to a physical return receipt/disposition line was found in all 55 migrations. sales.return_items is a justified candidate dependent fact, not a new master; no table or writer added. Existing unique order/payment constraints and full-return/refund/replay semantics remain unchanged pending tested compatibility; final financial and quarantine policies still require approval.

### TEST-069 / TEST-070 — confirmed 0055 and characterization boundary
- 0055 verified against exact corrected fixture. The two new tests document behavior after close function return and before shared barrier; no global entitlement or effective-date change. Final commit-time validity and timestamp semantics remain owner decisions; no operational approval implied.

### REVIEW-027C — candidate normalized return line keys
- Prefer deriving item/variant/warehouse/lot/serial/allocation from existing reservation and original sale movement. Exact three composite FK targets bind header, order item and sold movement; do not store redundant derived identity or totals. No new table or write permissions in this checkpoint. Final disposition and valuation policy open.

### BUILD-027B — dormant dependent fact, not financial policy
- TEST-070 demonstrates commit expiry and pre-barrier DEFAULT ordering; neither resolves final policy. 0056 adds only the independent receipt line structure, with normalized original sale identity and no runtime/executor DML. Keep old unique constraints and all existing full-return/refund/valuation semantics. Aggregate cap and physical disposition writer are mandatory future gates; no production or final policy approval.

### BUILD-027C — provisional quantity fact guard, no operational writer
- Use existing order lock and READ COMMITTED for receipt-line aggregate. Cap is per original sale movement across dispositions, not a policy for legacy plus partial receipts. Append-only; no new grants. Keep existing receipt/valuation APIs. A future writer must have complete tenant-scoped evidence visibility, same locks, validate consumed reservation and exact sale/return evidence, and treat prior legacy rows as the same event, never count twice. No approval of final cutoff, entitlement or disposition/refund policy.

### REVIEW-027E — proposed limited writer privileges
- No executor role elevation or blanket cross-domain write grant; use exact required evidence reads and tenant-scoped append-only receipt insertion for existing writer. Test structural cap separately from actual full-return runtime and preserve all negative assertions. Historical upgrade compatibility requires actual pre-upgrade fixture. No executable or financial policy change yet.

### BUILD-027D — one existing full-return writer only
- New full sellable receipt lines represent the same event as legacy ledger and are not added to ledger quantity. Private sales executor gets exact evidence reads and append-only sellable fact INSERT, no role elevation or other new DML. Retry with lines validates evidence; zero-line legacy retry read-only, actual upgrade test pending. No final financial or disposition policy change.

## FIX-028A — 2026-11-25
- TEST-073 / FIX-028A: exact 0058 run 45627260327 job 139250654541 at cad159104e2d70c7d01e568993ae9e279b373f36 failed only at pricing concurrency after all 58 migrations, SQL suites and identity/inventory/sales races passed. Logs show PASS canonical full-return writer, RETURN_WRITER_RACE, RETURN_CAP_RACE, both stale price checkouts rejected; pricing.sh final count still expected one order/reservation but preceding expanded sales fixture creates three. Fix only pricing test fixture expectation: assert exact three before and after, compare full ordered order and reservation snapshots after each race, retain actual lock wait, SQLSTATE 23514 and rejection checks. No migration, runtime, ACL, RLS or financial change; later concurrency suites skipped, overall CI not yet verified. Rerun full CI, then actual pre-0058 upgrade fixture and 0059. No operational access.

### TEST-075 — independent upgrade evidence
- Real old return history must be created before applying 0058, not fabricated by disabling constraints. Separate disposable CI service; reuse existing fixture with final commit only in temporary copy. Compare all row data before/after exact legacy retry; no automatic backfill. No runtime or financial change.

## FIX-028B — 2026-11-25
- TEST-076 / FIX-028B: exact TEST-075 run 45630535075 at 5ff26ddc69c7db6821362136b1a9670cd17f3156: foundation job 139262191015 completed SUCCESS (58 contiguous pairs, 86 tables, 67 PASS, all nine concurrency suites, 24 COGS races); independent return-upgrade job 139262189394 failed after UPGRADE_BASELINE committed actual pre-0058 ordinary/traced returns and passed header/movement/empty-line assertions. Snapshot generated SQL referenced to_jsonb(t) without FROM alias; ERROR column t does not exist, before migration 0058. Fix exactly one line by adding AS t to generated SELECT FROM clause. Preserve full all-table comparison, legacy retries, negative tests and new-writer coexistence; no migration/runtime/ACL/policy change. Both jobs must pass before 0059. No production access.

### REVIEW-027F — distinguish receipt evidence from stock quantity
- Zero-line legacy fallback is necessary and upgrade-tested; when any lines exist require complete exact sellable evidence. Receipt rows and ledger movements are same event, never additive. Privileged total deletion is indistinguishable from legacy absence without a trusted marker; do not claim complete corruption detection. No new table or final policy.

### BUILD-027E — exact receipt reconciliation, no new quantity source
- Keep existing capacity API and its read gates. New line-bearing receipts must exactly match validated return movements, legacy zero-line receipts retain ledger fallback. No double count, no new writer or financial rule. Total privileged deletion remains a known limit; no independent marker added.

### REVIEW-028C — do not equate quarantine with warehouse naming
- Reuse existing return header/line and movement identities; one-order/one-payment unique constraints not relaxed before all readers and writers are safe. Non-sellable physical receipt cannot increase available stock or silently reverse COGS/refund. Existing expiry/serial guards stay. Quarantine representation and independent event necessity require evaluation, no new table or final policy.

### REVIEW-028D — lifecycle contract, not operational authorization
- Derive physical receipt capacity from existing immutable receipt events and original sale movement; historical exact ledger fallback is exclusive, not additive. Custody, saleable admission, cost reversal and refund are distinct effects. Preserve all existing constraints until compatible callers and approved policy. 0059 verified; no 0060 SQL in this checkpoint.

### BUILD-028E — reject undeclared return allocation semantics
- Return-specific strict JSON allowlist before normalization or idempotent replay. Unknown metadata cannot be silently interpreted as sellable. No shared normalizer change, no new API, no new grants or policy. Existing documented four keys supported; formerly ignored keys now rejected. No partial writer or financial activation.

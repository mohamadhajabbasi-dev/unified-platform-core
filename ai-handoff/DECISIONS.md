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


## REVIEW-029 — scope and sequencing, technical checkpoint (not new owner policy)
57 groups: 22 verified prototype, 12 partial, 23 not implemented. Counts classify groups, not percentage of database completion; some groups overlap (e.g. parties, distribution, tax submissions), and verified means relevant structures and baseline CI exist, not every field, policy or operation is validated. All 60 migration texts scanned for CREATE TABLE, ALTER move/rename, DROP, functions/views; selected definitions and 0060 acceptance/logs reviewed. No independent exhaustive column/ACL/call graph or load audit.
Next: REVIEW-029A — core dependency design for tenant business locations and site/domain registry: compare core tenant addresses/settings, inventory warehouses, analytics sessions/events and platform applications, canonical relationship/uniqueness/RLS/ACL and tests; design one tenant child per genuinely distinct concept, no duplicate store/warehouse/site master. Only then allocate 0061 if justified. Parallel policy-gated backlog (not implement concurrently): counterparty roles and identity before bank/cheques/AR/settlement/installments; shipping and delivery; fiscal invoice/tax (owner approved legal/financial policy); CRM tags/queues/favorites/alerts, licensing/auth security (owner policy), analytics/notification/outbox/workflow/AI/ops backup/restore/load. No new table solely on dictionary label.
Open gates: module entitlement expiry after function returns and before COMMIT; inventory recorded_at before period barrier acquisition (0055 and actual COGS observations, not fixed). Retain exact existing tests; resolve only with owner-approved temporal policy and deterministic transaction/lock tests. Partial/non-sellable physical custody, quarantine, refund/valuation policy remain blocked; full return path unchanged. No production, legacy access, or final policy activation.


## REVIEW-029A — provisional technical design only
- Physical location is not a tenant, warehouse, site or address master; reuse tenant/address composite identity, existing IAM and ops.audit_events. Do not infer warehouse cardinality or allow site activation. Separate site/domain lifecycle pending website_host compatibility and approved ownership/routing policy. See docs/BUSINESS_LOCATION_SITE_DESIGN_FA.md; no financial/security policy activation.


## TEST-082 / BUILD-029B — 2026-11-25
- Verified exact 0060 checkpoint SHA aaf1bf5e490e36b6412b513f1956d32b0f9a8612, run 45641015000 SUCCESS, foundation 139299347881 and return-upgrade 139299347939 SUCCESS; logs 60 contiguous pairs, 86 tables, 69 PASS suites, 24 COGS races. Reviewed current HEAD c88c0afd092089987915a67a749641ae21090339.
- Authored 0061_business_locations.sql with one physical business-location child, tenant-scoped immutable identity and composite existing address FK, RLS/ACL, exact existing audit writer target extension. No warehouse/host/site/stock/order changes. Address binding additionally requires existing tenant.legal.read; server generates ID/timestamp; location_kind immutable. Explicit location-key conflict, not silent retry or API idempotency; runtime create retry requires future reviewed exact-payload contract. Non-null address on UPDATE requires legal read (including other field updates); address text remains protected. No grant to new permissions except synthetic tests. Metadata only; no module or sales activation.
- Matching rollback SQL test and real competing unique-index write shell test added; workflow adds one step before COGS, existing suites unchanged. Candidate expected 61 migration/test pairs, 87 tables, 71 PASS (61 SQL + 10 concurrent), plus independent return history upgrade. Runtime CI PENDING. No production or legacy access. Temporal expiry/pre-barrier timing, partial/quarantine/refund policy unchanged.


## TEST-083 / REVIEW-029B / BUILD-030A — 2026-11-25
- TEST-083: exact 0061 run 45643530975 at 27faa6a220cf327a2d60047c6b63cedd97aaca1a SUCCESS, foundation 139308257824 and return-upgrade 139308258268 SUCCESS; logs 61 contiguous pairs, 71 PASS suites (61 SQL + 10 concurrent), actual unique-index contention and SQLSTATE 23505, one location and one exact audit, 24 COGS races, actual return history upgrades. 87 base tables derived from DDL inventory (86 earlier + one location relation); prior log numeric 86 was a module decision ID, not a direct runtime table-count query. 0062 test adds explicit catalog count diagnostic.
- REVIEW-029B: literal scan of all 61 migration files and 74 SQL/shell test files at exact 27faa6a220cf327a2d60047c6b63cedd97aaca1a for website_host, site_id and domain_host: only website_host definition (0011 line 64) and UPDATE grant (line 149); no existing literal caller or site master in these files. Generic SELECT */row shapes and future external clients are not proven compatible. Existing informational host allows duplicates across tenants and cannot be trusted for routing. No automatic host import, claim, normalization, removal or dual-write. Domain ownership/verification/reassignment/activation/expiry/security policy remains owner-gated.
- BUILD-030A candidate: 0062 adds only immutable dormant core.sites identity (tenant, generated ID, stable tenant-key, display name, server timestamp), no host/domain, address, warehouse, application, order, event or active flag. Reuses existing IAM/RLS and ops.record_dossier_change; no runtime DML, non-login scoped executor and exact-payload idempotent registration under advisory lock, READ COMMITTED. Metadata does not require commerce entitlement, does not enable commerce, cannot route or collect data; any future activation/analytics must require approved policy and platform.commerce_eligible. No existing roles receive new permissions. SQL and actual two-waiter concurrency tests added; existing tests unchanged. Expected 62 pairs/73 PASS and 88 base tables, CI PENDING. No operational access.
- Open: module expiry after return before COMMIT; pre-barrier recorded_at; partial/quarantine/refund/valuation policy; location exact-retry API still pending. No production access. Next verify exact 0062 CI both jobs and update counts, then advance independent CRM/catalog favorites/tag or counterparty/financial design while domain security policy remains gated.


## FIX-030A — test correction only, no policy change
The 0062 acceptance test must snapshot complete canonical site and audit rows with explicitly named aliases before and after rejected/replayed operations. Correct unresolved alias references, not the assertion or implementation; no new domain or financial/security decision.


## REVIEW-030B provisional technical design
Tag metadata and unique customer-tag relationship are separate from customer identity, consent, pricing and customer merge. Reuse IAM/CRM module and shared audit; retain one link identity across state changes, no new commercial/security policy or production activation. Design: docs/CRM_CUSTOMER_TAG_DESIGN_FA.md.


## TEST-085 / BUILD-030B — 2026-11-25
- TEST-085: exact correction SHA 843483533613e7d577cb6953d4f0c51827cf3247 run 45649134004 SUCCESS; foundation 139328451364, return-upgrade 139328451042 both SUCCESS. Logs: 62 contiguous pairs, 73 PASS suites, direct catalog count 88 base tables, site exact retry with two actual advisory waiters, conflict 23505 and one audit; 24 COGS races. Site/domain group now PARTIAL, not complete domain lifecycle. 23 verified prototype, 13 partial, 21 not implemented.
- Prior design commit e4a7eb9f3852323322f0e14366c35be0721e359b existed in GitHub but main update repeatedly returned GraphQL server errors/ReadTimeout. Reuse that exact commit as parent (no duplicate design), advance main from verified ancestor only, no force. Verify ref after mutation. If not advanced, report NOT_PUSHED and retain candidate SHA.
- BUILD-030B: 0063 customer_tags/customer_tag_links candidate only, 2 normalized relations linked to existing customer PK, no duplicate customer/consent/pricing. Existing CRM module and crm.read plus dedicated tag ACL, nonlogin executor, no direct runtime DML, shared audit. Exact create and state replay, detach absent no tombstone, same relationship identity on reattach. Real duplicate create and attach contention test; no claim historical command exactly-once, no concurrent opposing-state test yet. 0052 period barrier protects financial paths and module decisions; tags have no financial effects and use existing statement-time permission/module checks, no commit-time policy change. Free-text name normalization limited to lower(btrim), no sensitive semantic classification/retention or operational activation. Expected 63 pairs, 75 PASS, 90 tables after CI; pending verification.
- Open: domain ownership/activation, location retry, merge review, customer-self authorization, module expiry after return/pre-COMMIT and pre-barrier recorded_at, partial/non-sellable custody/refund/valuation. No legacy or operational access. Next verify both exact 0063 jobs, then continue independent requirements (favorites or queues) only after success.


## FIX-030B — test sequencing only
Do not combine volatile tag mutations with snapshot reads or multiple state transitions inside one SQL boolean expression. Assert returned identity, persisted state and immutable full-row replay in separate statements; retain audit evidence. No change to business or access policy.


## REVIEW-031B — provisional technical queue design
One queue metadata identity per tenant; nullable tenant-aware FK on canonical support_tickets; preserve existing engagement read/write semantics and add dedicated queue write controls to prevent direct assignment bypass. No automatic assignment, queue access boundary or SLA/customer feedback policy. Design only, not owner-approved new policy. See docs/CRM_SERVICE_QUEUE_DESIGN_FA.md.


## TEST-088 / BUILD-031 — 2026-11-25
- TEST-088: PR #1 merged f583474cc72a42ece32c6ee0e039aaf5bda343dc, exact main run 45654059400 SUCCESS both jobs 139345880019/139345879319. Logs 63 contiguous pairs, 75 PASS suites, measured 90 base tables, actual tag contention and 24 COGS races. PR #2 documentation merged at 18ee2ad500b2713302440e8814dcde7dea7b947d with exact checkpoint tree. 23 verified/14 partial/20 not implemented; tag/merge partial. Main 0063 verified.
- BUILD-031: authored 0064 service_queues, nullable composite FK on existing support_tickets, 11-column legacy INSERT ACL preserved and protected queue_id, separate scoped nonlogin executor and shared audit. Exact state replay; ticket row lock for assignment, no routing or SLA/feedback policy. SQL test, real create/assign/opposing contention, separate committed pre-0064 upgrade job reusing 0013 fixture. No previous tests removed. Candidate expected 64 pairs, 77 foundation PASS suites, 91 base tables, separate upgrade proof; not yet verified. Preserve open ticket/customer-conversation consistency gap, privacy, queue access/closed-ticket lifecycle, temporal/financial/custody/domain gates. No production or legacy access.
- Next verify exact candidate SHA and all three CI jobs, inspect actual failure before any next migration. Main promotion only after PASS if candidate branch used. Next unused 0065 only after 0064 verification.


## TEST-089 / REVIEW-032B — 2026-11-25
- TEST-089: exact candidate c9db3f637d447d579c17df2f230f762907fe79ac run 45659699146 SUCCESS, foundation 139365900387, queue-upgrade 139365900844, return-upgrade 139365901017 all SUCCESS. Foundation logs: 64 contiguous migration/test pairs, 77 PASS suites (64 SQL + 13 concurrency), runtime catalog 91 base tables, actual create and ticket lock waits, exact queue retry and serialized opposing assignments, exact audit, 24 COGS races. Committed pre-0064 ticket upgrade independently proves exact old row preservation, nullable queue/no backfill and old runtime writes. Actual return-history upgrade passed. Coverage 23 verified prototype/14 partial/20 not implemented unchanged; service queue/SLA/feedback group remains PARTIAL. Main still 0063 63/75/90, not promoted.
- PR #3 head c9db3f637d447d579c17df2f230f762907fe79ac, base 18ee2ad500b2713302440e8814dcde7dea7b947d, state open, draft true; exact PR run 45661080855 status in_progress, conclusion pending. PR comment REVIEW-032A 7169006681 already recorded design. Documentation-only checkpoint; do not alter tested PR head or allocate 0065 before main verification. No operational or legacy access.
- New docs/CATALOG_CATEGORY_HIERARCHY_DESIGN_FA.md expands prior design: existing table self FK, preserve tenant-wide uniqueness and original column ACL, tenant-wide advisory transaction lock before graph reads, recursive cycle/root check, exact replay and shared audit, actual committed upgrade and opposing-edge contention. No additional table, no duplicate product/category master, no attributes/barcodes, no business/security policy change. 64 migration texts previously scanned for literal category references (only 0004), not a full caller/semantic audit. Queue lifecycle/SLA/feedback, temporal/custody/financial/domain gates remain open.
- Next: verify PR #3 exact checks, mark ready if needed and merge preserving history, verify resulting main tree equals tested candidate and exact main CI. Reconcile this checkpoint once (do not duplicate existing design/implementation). Then allocate 0065. If failures, fix actual cause only; no bypass or weakening tests.


## REVIEW-032D / CI-001 candidate — 2026-11-25
- 0064 main merge c12446cb405abd08ed1961ad9d2d5f8695d591f7, exact candidate tree; PR #3 run 45661080855 SUCCESS all three jobs. Main run 45663024472 still in progress at last check; queue/return upgrades PASS. PR #4 draft docs head 1484b1f0e9d332b8586753824e3fc2ec09e829fe.
- While main gate runs, independent CI-only experiment on checkpoint branch content: separate existing COGS concurrency step into fresh PostgreSQL16 job with same full migration sequence; factor identical ordered migration loop into db/ci/apply_migrations.sh plus disposable-DB guard. Foundation retains all 64 SQL and other 12 concurrency suites; COGS script/fixtures unchanged and exactly one execution; both upgrade jobs unchanged. Four jobs required for acceptance; no reduced assertion/timeout or migration/schema change. Previous candidate COGS wall time 253s; independence not yet proven and speedup not claimed until measured. Separate runner/setup may increase summed runner minutes. No production access.
- Next verify CI-only exact branch run all four jobs; prove 76 foundation PASS plus one COGS PASS (24 races and temporal observations), 91 measured tables, both upgrade passes. Compare actual timing against 45659699146. If failure investigate dependencies, retain existing main workflow. No merging before main 0064 gate and documentation reconciliation; incorporate successful workflow diff once, not duplicate scripts. 0065 remains unused pending main verification.


## TEST-090 / BUILD-032 — 2026-11-25
- TEST-090 / CI-001: exact main 0064 c12446cb405abd08ed1961ad9d2d5f8695d591f7 run 45663024472 SUCCESS all three jobs; foundation 139377631956 logs 64 contiguous pairs, 77 PASS, 91 measured tables, 24 COGS races. Parallel CI-only candidate 977b3f0507c22dcd4cd688a5b6aabadefa2b0826 run 45663490527 SUCCESS all four jobs: 76 foundation PASS and one COGS PASS, both upgrades, same 91 tables and 24 races plus temporal observations. All existing migration/test blobs unchanged. Observed span 273 vs 471 seconds, aggregate 569 vs 525 seconds. PR #5 exact checks still running; #4 superseded. Main gate satisfied; develop 0065 in separate descendant branch without changing PR #5 head. Merge PR #5 first after checks; then verify 0065 candidate ancestry and exact CI before promotion.
- BUILD-032: 0065 category hierarchy authored with nullable self-FK on existing categories, no new table or permission, preserved four original INSERT columns, protected graph mutation, tenant advisory lock and recursive cycle/root validation, audit exact changes only, SQL test plus real 2/3-edge contention and committed category upgrade. Existing active/name behavior, prices, product membership unchanged. Candidate expected 65 pairs, 78 foundation PASS + one COGS PASS =79 suites, 91 tables; separate three upgrade jobs. Counts pending actual CI. 23/14/20 verified groups unchanged until CI, then hierarchy group N→P only (attributes/barcodes absent). All policy gates remain. No legacy/production access.
- Next check PR #5, exact 0065 candidate all five jobs, verify logs/actual races and previous upgrade; fix actual failures, promote in ancestry order and verify exact main. No next migration until 0065 passes. No new table.


## TEST-092 / BUILD-033 — 2026-11-25
- TEST-092: exact main 0065 6bffe5297b6fa0a87223b775666e25384e8ae1f2 run 45666746489 all five jobs SUCCESS. Foundation 139390829241 78 PASS, 65 contiguous pairs, 91 catalog base tables, actual two/three-edge category cycle contention, exact replay and audit. COGS 139390829173 1 PASS/24 races; all three upgrades success. Verified coverage 23/15/19. Prior parallel CI main 45665762497 passed; span 273 vs 471 seconds observed, aggregate 569 vs 525. No production activity.
- BUILD-033 / REVIEW-033: authored 0066 one dependent catalog.variant_barcodes relation, tenant+variant FK, exact case-sensitive ASCII visible 1..128 code (prototype technical bound, not approved symbology), tenant+code unique, multiple aliases per variant, no SKU/serial/GTIN normalization, no auto backfill or label generation. Existing catalog.read/write and module gates, dedicated NOLOGIN executor, read-committed scoped advisory lock, exact replay, conflict, shared insert audit; no reassignment/delete. Synthetic acceptance, concurrency and committed pre-0066 upgrade. Expected 66 pairs, 80 foundation PASS + one COGS PASS, 92 tables, four upgrade jobs. Pending exact CI; group coverage stays 23/15/19 since attributes and labels absent. No activation or policy changes. Next verify all six jobs, fix failures only, promote after exact PR CI and verify main. No 0067 until complete.


## TEST-093 / REVIEW-034 — 2026-11-25
- Exact 0066 candidate e3c08d31d10e2c9fa062707a368ff29181ff48f5 run 45685697007 all six jobs SUCCESS. Foundation 139457610117 logs 66 contiguous pairs, 80 PASS, 92 base tables, actual advisory wait/replay/conflicting variant/one audit. COGS 139457610643 one PASS/24 races, both temporal observations unchanged. Actual committed pre-0066 barcode upgrade 139457610667 exact previous rows, prior category hierarchy, no backfill, existing variant registration; all four upgrade jobs pass. PR #7 created, exact PR run 45687821259 pending. Main remains 0065 6bffe5297b6fa0a87223b775666e25384e8ae1f2, run 45666746489 success 65/79/91. Candidate 66/81/92, group coverage 23 verified/15 partial/19 not implemented unchanged.
- REVIEW-034: read-only pinned legacy GitHub tree/source inspection (allowed D-016): ERPPlus ProductVariant fields Color, Size, AttributeName, AttributeValue, AttributesJson, SKU, Barcode, additional price and InitialStock. CommerceAI ProductVariant title/SKU/barcode/external ID; StoreProductVariant has per-store price/stock, not to copy. Prior scan all 65 migration texts found no named attribute structures; 0066 barcode reviewed and adds no attributes. Target requires normalized attributes. Proposed 0067 in docs/VARIANT_ATTRIBUTE_DESIGN_FA.md: only variant descriptive text definitions and values initially; use one tenant attribute definition per stable key, one assignment per variant+attribute, existing composite FKs, protected writes and exact replay, no price/stock/variant creation or combination-identity policy. Technical prototype decisions not final. Product-level fallback, typed options, variants generated from combinations, label lifecycle require later explicit design. No new 0067 DDL before exact main 0066 success.
- Documentation checkpoint only, separate descendant branch to avoid modifying tested PR #7. After PR #7 successful merge and main CI verification, use checkpoint design and reconcile docs once as part of 0067 (base current main; copy only checkpoint docs, no extra merge or repeated work). If PR CI fails fix actual cause. No legacy edits or operational access.


## TEST-094 / BUILD-034 — 2026-11-25
- Exact main 0066 922820c9feb4076879cb16b65de8b145405acfc7 run 45688931947 all six jobs SUCCESS; foundation 139468893410 66 contiguous pairs, 80 PASS, 92 base tables, actual barcode concurrency; COGS 139468895366 one PASS/24 races; four committed upgrades passed. PR #7 exact run 45687821259 SUCCESS; merge tree matched candidate. Coverage 23 verified/15 partial/19 not implemented. Reconciled checkpoint 9c57da8ef52913ebd02f121126a1da446492f114 once, no duplicate PR.
- BUILD-034: authored 0067 normalized tenant attribute definitions and one current descriptive textual assignment per variant+attribute. Stable key unique, display label NOT unique (translation/locale policy unresolved; no automatic merge). Explicit key bounds 1..80 and label/value nonblank/no controls 120/512 chars, exact text comparison, no normalization. Scoped executor, RLS, protected register/set, advisory locks, exact replay, serialized differing updates and shared entity/actor audit (not value-history). No new product/variant/price/stock master or permissions, no automatic variant creation, no typed/options/product-level fallback/delete/labels. Synthetic SQL, observed race tests and separate committed upgrade comparing prior rows even after writes; earlier tests unchanged. Expected 67 pairs, 82 foundation + 1 COGS PASS, 94 tables, five upgrades, seven jobs. Pending actual CI. Coverage unchanged pending CI and label lifecycle still absent. Next verify exact branch all jobs, fix actual failures, PR then main CI, no 0068 until complete. No legacy/production access.

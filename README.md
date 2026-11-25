# Unified Platform Core — پلتفرم واحد چندمستاجری

مخزن **در حال حاضر عمومی (Public)** برای طراحی و اجرای کنترل‌شده یک دیتابیس عملیاتی مرکزی PostgreSQL در آینده، به‌جای اطلاعات تکراری میان ERPPlus (MySQL) و CommerceAI (PostgreSQL). برنامه‌های ERPPlus، Commerce، CRM، اپ موبایل و کانال‌های آینده باید از یک منبع معتبر و سرویس امن مشترک استفاده کنند.

> **وضعیت تأییدشده شاخه اصلی (2026-11-25):** ۶۴ Migration، ۷۷ مجموعه تست و ۹۱ جدول؛ [CI موفق](https://github.com/mohamadhajabbasi-dev/unified-platform-core/actions/runs/45663024472). اجرای موازی در شاخه آزمایشی تأیید شده؛ ۰۰۶۵ نوشته شده و در انتظار CI است. بدون استقرار عملیاتی.

## شروع الزامی هر عامل هوش مصنوعی
1. [AGENTS.md](AGENTS.md) — دستورالعمل قطعی، ممنوعیت تکرار کار/جدول و اعمال ناامن
2. [سند مادر پروژه](docs/MASTER_PLAN_FA.md) — اهداف، نیازها، معماری و مراحل از آغاز تا استقرار
3. [پروتکل استمرار](ai-handoff/CONTINUITY_PROTOCOL_FA.md) — الزام ثبت هر اقدام و تحویل بین چت‌ها
4. [وضعیت واقعی](ai-handoff/PROJECT_STATE.md) — مرحله جاری و مرز برنامه/اجرا
5. [دفتر اقدامات](ai-handoff/WORK_LOG.md) — ثبت افزایشی کارهای موفق و ناموفق
6. [تصمیم‌ها و ابهامات](ai-handoff/DECISIONS.md)
7. [کارهای بعدی](ai-handoff/NEXT_ACTIONS.md)
8. [چارت معماری قابل نسخه‌بندی](docs/ARCHITECTURE_CHART.md)
9. [تاریخچه تغییر](ai-handoff/CHANGELOG.md)

## اصول محوری
- **یک مشتری در هر تننت فقط یک پرونده مرجع**؛ همان فرد می‌تواند در تننت‌های متفاوت پرونده مستقل داشته باشد. ارتباط کانال‌ها با هویت معتبر و سیاست تطبیق سنجیده شود.
- یک مرجع اصلی برای محصول و داده‌های تجاری؛ تنظیمات، قیمت، موجودی و رابطه مشتری با هر تننت به‌طور امن جداست.
- مدیر کل به اطلاعات مجاز سراسر پلتفرم با ردپای حسابرسی دسترسی دارد؛ کارکنان پلتفرم و کاربران تننت‌ها فقط نقش تأییدشده.
- فعال شدن ماژول برای تننت نیازمند تأیید مدیر کل است.
- حذف همگام‌سازی **بین نسخه‌های تکراری دیتابیس**؛ حفظ APIهای امن برای عملیات برنامه‌ها.
- بکاپ داده تننت جدا از بکاپ کد و کل پروژه؛ بازیابی یک تننت نباید سایر تننت‌ها را به عقب برگرداند.
- تغییرات تولیدی **صرفاً با تأیید، بکاپ قابل بازیابی، تست و برنامه rollback**.

## قانون استمرار
**پس از هر اقدام**، عامل موظف است WORK_LOG را append کند، PROJECT_STATE و NEXT_ACTIONS را به‌روز کند و این تغییرات را واقعاً در GitHub commit کند. در غیر این‌صورت نباید ادعا کند که کار برای چت بعدی ذخیره شده است.

**گام فنی فعلی:** توسعه PostgreSQL مستقل در همین GitHub و آزمون با داده مصنوعی؛ هیچ دسترسی به محیط legacy یا production. مرجع جاری: [NEXT_ACTIONS](ai-handoff/NEXT_ACTIONS.md).

**درباره بسته قبلی:** PDF و تصویرهای باینری در بسته تحویلی چت وجود دارند ولی حضور آن‌ها در GitHub را تا زمانی که واقعاً آپلود و تأیید نشده‌اند مفروض نگیرید. متن مرجع و راهنمای اجرا در این مخزن نگهداری می‌شود.


## پوشش کامل داده‌های قدیمی در طراحی جدید (GitHub-only)
برای پیگیری «تمام داده‌ها» ابتدا [فهرست ۲۳۴ مدل EF](docs/LEGACY_DBSET_COVERAGE_2026-11-24.md)، [شواهد فیلدهای واقعی](docs/SOURCE_FIELD_EVIDENCE_FA.md) و [ماتریس ۵۷ گروه جدول‌های مرجع مقصد](docs/CANONICAL_TARGET_TABLE_DICTIONARY_V1_FA.md) را بخوان. این فهرست‌ها برای **پوشش نیازها** هستند، نه کپی دیتابیس فعلی. اسکریپت‌ها و تست‌های مستقل با داده مصنوعی به مرحله تأییدشده 0064 در شاخه اصلی رسیده‌اند؛ آخرین وضعیت اجرای CI و مراحل بعد در PROJECT_STATE و NEXT_ACTIONS است. پایگاه‌داده/سرور/سورس پروژه‌های ERPPlus و CommerceAI دست‌نخورده‌اند. GitHub در حال حاضر **Public** است؛ فقط داده synthetic.


پوشش ۵۷ گروه داده: 23 گروه نمونه پیاده‌سازی و CI تأییدشده، 14 گروه ناقص، 20 گروه فاقد پیاده‌سازی شناسایی‌شده؛ این تعداد درصد تکمیل پروژه نیست. مرجع جاری ماتریس پوشش و NEXT_ACTIONS است.


## TEST-092 / BUILD-033 — 2026-11-25
- TEST-092: exact main 0065 6bffe5297b6fa0a87223b775666e25384e8ae1f2 run 45666746489 all five jobs SUCCESS. Foundation 139390829241 78 PASS, 65 contiguous pairs, 91 catalog base tables, actual two/three-edge category cycle contention, exact replay and audit. COGS 139390829173 1 PASS/24 races; all three upgrades success. Verified coverage 23/15/19. Prior parallel CI main 45665762497 passed; span 273 vs 471 seconds observed, aggregate 569 vs 525. No production activity.
- BUILD-033 / REVIEW-033: authored 0066 one dependent catalog.variant_barcodes relation, tenant+variant FK, exact case-sensitive ASCII visible 1..128 code (prototype technical bound, not approved symbology), tenant+code unique, multiple aliases per variant, no SKU/serial/GTIN normalization, no auto backfill or label generation. Existing catalog.read/write and module gates, dedicated NOLOGIN executor, read-committed scoped advisory lock, exact replay, conflict, shared insert audit; no reassignment/delete. Synthetic acceptance, concurrency and committed pre-0066 upgrade. Expected 66 pairs, 80 foundation PASS + one COGS PASS, 92 tables, four upgrade jobs. Pending exact CI; group coverage stays 23/15/19 since attributes and labels absent. No activation or policy changes. Next verify all six jobs, fix failures only, promote after exact PR CI and verify main. No 0067 until complete.


## TEST-093 / REVIEW-034 — 2026-11-25
- Exact 0066 candidate e3c08d31d10e2c9fa062707a368ff29181ff48f5 run 45685697007 all six jobs SUCCESS. Foundation 139457610117 logs 66 contiguous pairs, 80 PASS, 92 base tables, actual advisory wait/replay/conflicting variant/one audit. COGS 139457610643 one PASS/24 races, both temporal observations unchanged. Actual committed pre-0066 barcode upgrade 139457610667 exact previous rows, prior category hierarchy, no backfill, existing variant registration; all four upgrade jobs pass. PR #7 created, exact PR run 45687821259 pending. Main remains 0065 6bffe5297b6fa0a87223b775666e25384e8ae1f2, run 45666746489 success 65/79/91. Candidate 66/81/92, group coverage 23 verified/15 partial/19 not implemented unchanged.
- REVIEW-034: read-only pinned legacy GitHub tree/source inspection (allowed D-016): ERPPlus ProductVariant fields Color, Size, AttributeName, AttributeValue, AttributesJson, SKU, Barcode, additional price and InitialStock. CommerceAI ProductVariant title/SKU/barcode/external ID; StoreProductVariant has per-store price/stock, not to copy. Prior scan all 65 migration texts found no named attribute structures; 0066 barcode reviewed and adds no attributes. Target requires normalized attributes. Proposed 0067 in docs/VARIANT_ATTRIBUTE_DESIGN_FA.md: only variant descriptive text definitions and values initially; use one tenant attribute definition per stable key, one assignment per variant+attribute, existing composite FKs, protected writes and exact replay, no price/stock/variant creation or combination-identity policy. Technical prototype decisions not final. Product-level fallback, typed options, variants generated from combinations, label lifecycle require later explicit design. No new 0067 DDL before exact main 0066 success.
- Documentation checkpoint only, separate descendant branch to avoid modifying tested PR #7. After PR #7 successful merge and main CI verification, use checkpoint design and reconcile docs once as part of 0067 (base current main; copy only checkpoint docs, no extra merge or repeated work). If PR CI fails fix actual cause. No legacy edits or operational access.

# PROJECT_STATE — وضعیت واقعی پروژه

- تاریخ ثبت: 2026-11-24
- Phase: **00 — GitHub bootstrap / Documentation**
- وضعیت: **DOCUMENTATION_REMOTE_INITIALIZED / READ_ONLY_INVENTORY_NOT_STARTED**
- مخزن: `mohamadhajabbasi-dev/unified-platform-core` — **PRIVATE** (تأیید با GitHub).
- نتیجه عملی: ۱۱ فایل متنی شامل README، AGENTS، طرح مادر خلاصه، نمودار متنی و راهنمای تداوم/تصمیم/گزارش/گام بعد، در GitHub نوشته شدند. فایل‌های حیاتی دوباره از GitHub خوانده و تأیید شدند.
- آخرین log commit تأییدشده: `a817203f9ec52dbdcafd2ca5228f6f30a37f8634`
- وضعیت بسته قبلی: **فقط بخش متنی اصلی منتشر شد**؛ PDF/PNG/HTML و سایر فایل‌های کامل ZIP قبلی هنوز به مخزن وارد نشده‌اند. متن موجود یک نسخه خلاصه نگهداری‌پذیر است، نه فایل اصلی PDF ۱۴ صفحه‌ای.
- وضعیت ERPPlus/MySQL و Commerce/PostgreSQL: طبق گفته مالک، هنوز با دسترسی واقعی DB راستی‌آزمایی نشده.
- تغییر تولید (سرور، DB یا repos موجود): **NONE**.
- بررسی دیتابیس read-only: **NOT_STARTED**.
- DDL/migration/API جدید: **NONE**.
- بکاپ و restore-test مرتبط با این پروژه: **NONE**.
- آخرین اقدام کامل‌شده: DOC-005 / GitHub documentation bootstrap؛ جزئیات در WORK_LOG.
- گام دقیق بعد: بررسی وضعیت همین مخزن و مستندات؛ سپس برنامه‌ریزی و دریافت مجوز **فهرست‌برداری فقط‌خواندنی** از دیتابیس‌های فعلی.
- الزام استمرار: تمام عامل‌ها پس از هر اقدام، WORK_LOG را append و PROJECT_STATE و NEXT_ACTIONS را به‌روز و در GitHub commit کنند؛ در غیر این صورت `NOT_PUSHED` را گزارش کنند.

## Checkpoint INV-001 — 2026-11-24
- Phase: **01 — READ_ONLY_DISCOVERY_PREPARATION** (supersedes phase 00 above).
- Repository review: DONE; starting HEAD `503273567150bcf85893723085b145718956db37`, all 11 tracked text files and 14 commits reviewed/listed; all governance and handoff documents read. Private and push permissions confirmed.
- Owner approval: read-only inventory explicitly authorized; no authorization for production modifications.
- Actual database inventory: NOT_STARTED; access and engine/schema unverified. No table, code, migration, service or production change.
- Last completed action: INV-001 (repository preflight). Incomplete: obtain secure metadata-only access/evidence. First next action: check authorized sources for existing schema/migrations and available read-only DB connection. No PII/secrets in GitHub.

## Checkpoint INV-002 — 2026-11-24 (latest; supersedes earlier status)
- Phase: **01 — READ_ONLY_DISCOVERY_PARTIAL / LIVE_SCHEMA_BLOCKED**.
- Last completed: INV-002 source-code discovery and access check; actual DB inventory NOT_STARTED; no SQL executed.
- Evidence pinned: ERPPlus `52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049`; CommerceAI `e7ae9b09f21c042e56407f593b99258fe280b20a`. Code providers SQL Server and PostgreSQL respectively; live ERP engine unverified, so MySQL assumption must be checked. Both authorized remote devices offline.
- Preliminary documents: docs/CURRENT_INVENTORY.md, CURRENT_DATA_MAP.md, CURRENT_SYNC_MAP.md, OPEN_QUESTIONS.md. Code-based overlap only; customer uniqueness in Commerce is store-scoped; no duplicate-record counts or final ownership/ERD established.
- Production/server/DB/source repositories changes: NONE. New tables/code/DDL/migration/deployment: NONE. Tests: source/commit verification only. Decisions unchanged.
- First exact next action: bring authorized connection online or obtain sanitized metadata export; verify DB engines/versions and scope, then collect metadata-only schema inventory. Do not repeat verified GitHub bootstrap or source review unless source commits changed.


## Checkpoint INV-003 — 2026-11-24 (latest)
- Phase: **01 — GITHUB_ONLY_SOURCE_AUDIT_UNBLOCKED**.
- Action: source evidence reconfirmed for Commerce CustomerConfiguration and ERP AppDbContext; structured GitHub-only review plan committed at `05bff1977c2a8b61c18a1b8978fd80a8ef29fd90`.
- Confirmed design gap in **source model**: Commerce Customer uniqueness scopes by TenantId+StoreId+Phone/Email; target is one verified customer identity per tenant. ERP contains Customer and BusinessPartner models; merging semantics remains pending.
- Next exact action: inspect customer entities, upsert paths and migrations in source GitHub; produce field-level customer audit. No desktop connector required for this action.
- Live DB inspected: **NO**. Production changes, migrations or schema creation: **NONE**.
- Blocked work only: physical schema/row data/deployment validation, to be scheduled later with suitable access. Do not block code review on this.

## Checkpoint DESIGN-001 — 2026-11-24 (latest; supersedes source-audit-first ordering)
- Phase: **02 — GREENFIELD_TARGET_DESIGN / DOCUMENTATION_ONLY**.
- Owner clarification: copy of legacy databases is explicitly rejected; create a **new normalized PostgreSQL target** from requirements. Source inspection for migration compatibility only.
- New target brief committed: `docs/TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA.md` at `c5aee0b55f9efbb12af23855eb97507e31a32474`.
- First next action: draft independent target conceptual ERD and table responsibility dictionary for owner's review; no Desktop Commander necessary for design.
- Actual database creation/migration: NOT_STARTED. Production repos/server: UNCHANGED.

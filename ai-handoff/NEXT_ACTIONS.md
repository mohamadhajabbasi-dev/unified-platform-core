# NEXT_ACTIONS — مراحل بعدی به ترتیب

1. تأیید اینکه اسناد اولیه و گزارش اقدامات به مخزن خصوصی commit شده‌اند؛ بررسی SHA و فهرست فایل‌ها.
2. در صورت لزوم اضافه‌کردن فایل‌های binary PDF/نمودار به مخزن فقط پس از بررسی privacy و ممنوعیت داده حساس. صرف وجود فایل در ZIP به معنی push آن نیست.
3. گرفتن تأیید مالک برای **صرفاً بررسی read-only** و دسترسی امن به سرویس‌های موجود.
4. دریافت اطلاعات نسخه MySQL/PostgreSQL، schema، table، PK/FK، index، trigger، job، view، حجم داده، mapping و منبع حقیقی هر موجودیت؛ بدون داده محرمانه.
5. ترسیم نقشه producer/consumer در ERPPlus، CommerceAI، storefront، اپ موبایل، CRM، پیام‌رسان‌ها، agentها و taskهای sync.
6. تولید `docs/CURRENT_INVENTORY.md`، `docs/CURRENT_DATA_MAP.md`، `docs/CURRENT_SYNC_MAP.md` و `docs/OPEN_QUESTIONS.md` با شواهد.
7. نوشتن ADR و ERD نهایی برای بررسی و تأیید، **بدون ایجاد جدول یا تغییر تولید**.
8. بعد از تأیید طراحی، staging و تست مهاجرت و بازگشت مطابق MASTER_PLAN.

**بعد از هر اقدام**: WORK_LOG append، PROJECT_STATE و NEXT_ACTIONS به‌روز، و commit ثبت شود. از کار تکراری جلوگیری کن؛ پیش از هر عمل، وضعیت فعلی را دوباره بررسی کن.

## Current checkpoint INV-001 — supersedes items 1–3 status above
- [x] Verify initial GitHub files and commit history (starting HEAD `503273567150bcf85893723085b145718956db37`).
- [ ] Optional archive: deferred; not a prerequisite for read-only inventory.
- [x] Owner authorizes read-only discovery in current request; actual secure access still unverified.
- [ ] First exact action: discover authorized ERPPlus/CommerceAI source repositories and available read-only DB connection or sanitized metadata exports. Confirm target engines/databases and scope before querying; no production changes, no secrets/PII. Then proceed with items 4–8 in order. Do not create tables/code or finalize mappings without evidence and owner approval.

## Current checkpoint INV-002 (latest)
- [x] Repository verification and read-only authorization.
- [x] Source repo discovery and preliminary inventory/data/sync map at pinned source commits; docs under docs/CURRENT_*.md and OPEN_QUESTIONS.md.
- [ ] BLOCKED — both authorized remote devices offline. First exact next action: connect an authorized device with access or receive sanitized metadata exports; verify actual ERPPlus engine (code SQL Server, initial statement MySQL), Commerce engine/version and target DB; prefer existing replica/backup or existing read-only account. Do not change server/DB access settings without approval.
- [ ] Collect metadata only: table/column/type, PK/FK, unique/index, views/triggers/jobs, RLS/grants and estimated volume, no secrets or business rows; timeouts and load limits. Compare live evidence with pinned code and map source ownership, tenant/store and field semantics, then identify actual duplicate risk. Complete maps with evidence.
- [ ] Inventory remaining producers/consumers and active sync. Propose ADR/ERD for owner approval after inventory; staging/migration only after gates. Never disable sync or modify live systems in this phase.
- [ ] Original binary archive optional, deferred.


## Checkpoint INV-003 — GitHub-only work is unblocked
- [x] Read original code evidence directly from GitHub and write `docs/GITHUB_ONLY_DISCOVERY_PLAN.md` (`05bff1977c2a8b61c18a1b8978fd80a8ef29fd90`).
- [ ] **Next action now**: inspect Customer/BusinessPartner entities, Commerce Customer API/upsert, ERP CRM mapping, EF migrations; write `docs/CUSTOMER_SOURCE_AUDIT.md` with precise code anchors.
- [ ] Then catalog/variant/price/inventory source audit; IAM/modules; orders/accounting; conceptual ERD and decisions.
- [ ] Live database metadata verification remains a later gate before migration. **Do not require or repeatedly request Desktop Commander for source audit.**
- [ ] Update WORK_LOG, PROJECT_STATE and this file after every action; commit and verify SHA.

## Checkpoint DESIGN-001 — newest priority / owner correction
- [x] Registered requirement-first redesign brief `docs/TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA.md`; original legacy analysis remains **only migration evidence**.
- [ ] **NEXT ACTION**: create **new greenfield conceptual target ERD** from the approved business invariants, then draft table dictionary/tenant scope/PK-FK/RLS/uniqueness and ask owner to approve. Do NOT copy current EF tables by default.
- [ ] Legacy source audits may proceed as parallel **migration mapping**, not as gate for defining the proposed target. Live database inventory is required later for safe migration, not to start architecture design.
- [ ] Keep reports/decisions logged after every step. No actual DDL or production changes.

## Checkpoint DESIGN-002 — newest
- [x] Create **new requirements-first** proposed conceptual ERD: `docs/TARGET_ERD_V0_FA.md`.
- [ ] **NEXT:** review draft with owner; amend proposed schema and record choices. No legacy-schema cloning and no server dependency for this stage.
- [ ] Once approved, create precise PK/FK/unique/RLS table dictionary and first versioned staging migration code; legacy mapping, reconciliation and live metadata verification only as migration gates.

## Checkpoint DESIGN-003 — current; overrides prior sequence
- [x] Verify current repository and requirements; record owner D-013.
- [ ] Implement first isolated SQL migration (core tenant/user, membership, canonical customer + identifiers, tenant-aware FK/RLS) and tests. Use only disposable GitHub-hosted PostgreSQL, no legacy endpoints/secrets.
- [ ] Verify CI evidence; then IAM permissions/modules, catalog/pricing, stock ledger/reservations, order/payment/finance, content/outbox/audit/backup and integration tests in incremental migrations.
- [ ] Final design review, isolation/load/recovery tests, migration/rollback plan and owner approval before any legacy transfer. Do not access legacy now.

## Checkpoint BUILD-001 — current
- [x] Author first isolated foundation migration and synthetic acceptance tests; CI definition included if accepted by GitHub.
- [ ] First: verify actual GitHub Actions run and job logs for BUILD-001, record exact run/SHA and pass/fail; no PASS claim until evidence. Fix failures without touching legacy.
- [ ] Harden non-superuser function ownership, verified identity linking/ambiguity and concurrency, RLS write/permissions/audit; add IAM roles and approved module grants; then catalog/price, stock, order/payment/finance, content/outbox/backup and integration/recovery/load tests.
- [ ] Final review and owner approval only after isolated tests and migration/rollback plan; legacy remains entirely outside current scope.

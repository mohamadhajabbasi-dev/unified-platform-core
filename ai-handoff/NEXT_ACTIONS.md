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

## TEST-001 — current
- [x] Verify committed SQL and CI trigger, observe both unsuccessful runs.
- [ ] Inspect GitHub Actions run 45404619911 summary, fix confirmed issue, verify isolated PostgreSQL tests. No additional retry without evidence; no legacy or production access.
- [ ] After foundation passes, continue BUILD-001 domain checklist.

## TEST-002 — current
- [x] Retry after owner changed visibility; GitHub runner initialized.
- [ ] Read final run 45404619911 attempt 3 and job logs; fix demonstrated failures or proceed with foundation hardening and IAM on PASS.

## TEST-003 — current
- [x] Foundation CI passed; logs and code SHA verified.
- [ ] Next: harden SECURITY DEFINER ownership, add tenant IAM and module approvals with negative tests and rerun all migrations and tests. Then remaining domains as BUILD-001 checklist. Keep all data synthetic and CI isolated.

## BUILD-002 — current
- [x] Author incremental IAM/module approval SQL and tests; harden function owners.
- [ ] First: verify BUILD-002 CI logs for all migrations/tests; fix any failure and document result.
- [ ] Enforce IAM/module checks on CRM reads/writes and subsequent domains; add verified identity linking/concurrency and RLS write tests. Then catalog/price and remaining domains. Approval request workflow, delegated access and audited superadmin access remain open.

## TEST-004 — current
- [x] BUILD-002 CI confirmed PASS for both migrations and both test suites.
- [ ] Next: enforce permission and module gates on CRM and test allowed/denied calls, revocation, cross-tenant write; strengthen identity linking/concurrency. Then catalog/price and other domains. No legacy access.

## BUILD-003 — current
- [x] Implement CRM read/write module/permission gates and verified link; add two-session test.
- [ ] Verify all regression and concurrency tests in CI; fix demonstrated failures. Then catalog/product variants/price entries with tenant constraints and permissions. Audit, verification workflow and final security review remain open.

## FIX-001 — current
- [x] Correct observed test delimiter error.
- [ ] Verify new full CI run; do not claim PASS until logs confirmed. Then catalog as BUILD-003 checklist.

## TEST-005 — current
- [x] Verify full regression and concurrent resolution; all PASS.
- [ ] Next: implement catalog product, variants, categories, product-category and price model; test isolation, uniqueness, temporal non-overlap and IAM/module enforcement. Then inventory/sales and other domains; no legacy access.

## BUILD-004 — current
- [x] Implement canonical catalog and pricing SQL plus acceptance tests.
- [ ] Verify 0001–0004 regression and concurrency CI; fix observed failures. Then inventory warehouses, append-only stock ledger and reservations, derived balances; catalog media/hierarchy and pricing policy remain pending.

## TEST-006 — current
- [x] Verify full catalog, CRM, IAM, foundation and concurrent identity regression; all PASS.
- [ ] Next: implement inventory warehouses, append-only stock ledger, reservations and derived balances. Use tenant-aware FK to catalog. Test idempotency, oversell, concurrency and module/permission gates. Then orders/payment/finance and remaining domains; catalog hierarchy, media, pricing policies and final security review remain open. No legacy access.

## BUILD-005 — current
- [x] Author stock ledger, warehouses, reservations and derived balances; CI negative/concurrent tests.
- [ ] Verify full regression and inventory contention tests, fix demonstrated failures. Then implement sales order and payment core linked to canonical customer/catalog/reservations; finance/returns/transfer/valuation and other domains pending. No legacy access.

## TEST-007 — current
- [x] Verify all five migrations, regression suites and both concurrency suites; all PASS.
- [ ] Next: implement canonical sales order, order lines and payment records with tenant-aware customer/catalog/reservation FKs, price snapshots, atomic state transitions and idempotency; test checkout and duplicate payment. Then returns/finance, catalog media/hierarchy, inventory transfers/valuation and remaining domains. No legacy access or deployment.

## BUILD-006 — current
- [x] Author canonical physical checkout, order lines, capture records, derived totals and lifecycle tests.
- [ ] Verify full regression CI; fix demonstrated failures. Then concurrent checkout/capture tests, refund/late-capture recovery and finance; digital/service delivery, tax/shipping/discount and audit remain open. No legacy access.

## TEST-008 — current
- [x] Verify six migrations and eight regression suites; all PASS.
- [ ] Next: add concurrent checkout and capture duplicate tests; then design refund/late payment reconciliation and tenant finance journal; digital/service checkout, payment verification service and remaining domains pending. No legacy access or deployment.

## BUILD-007 — current
- [x] Author full return/refund, late full capture review and concurrent sales tests.
- [ ] Verify CI including actual sales contention. Fix demonstrated errors. Next tenant double-entry finance journal with canonical capture/refund source linkage; partial returns/refunds, reconciliation inbox and remaining domains pending.

## FIX-002 — current
- [x] Fix observed duplicate synthetic role grants in sales race setup.
- [ ] Verify full CI and actual checkout/capture contention; then finance journal.

## TEST-009 — current
- [x] Verify all seven migrations and ten test suites; actual sales concurrency PASS.
- [ ] Next: implement tenant chart of accounts, balanced immutable journals and verified capture/refund posting links. Preserve separation from platform billing. Then remaining finance workflows, reconciliation, content, ops and backup; no legacy access.

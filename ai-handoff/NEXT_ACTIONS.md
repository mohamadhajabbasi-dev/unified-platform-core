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

## BUILD-008 — current
- [x] Author chart of accounts, double-entry journals, source postings and negative tests.
- [ ] Verify full regression and finance test logs, fix demonstrated failures. Then fiscal period/recognition policy, platform subscription billing separate, remaining catalog/CRM/content/ops/backup/API domains. No legacy access.

## TEST-010 — current
- [x] Verify all eight migrations, eleven test suites and cleanup; all PASS.
- [ ] Next: extend accounting lifecycle with fiscal periods/closing and recognition policy as provisional, then independent platform subscription/invoice/payment billing; no posting tenant sales into platform revenue. Add relevant negative/concurrency tests. Then remaining CRM/catalog/content/ops/backup/API and production readiness gates. No legacy access or deployment.

## BUILD-009 — current
- [x] Implement period gate and recognition/refund lifecycle, tests.
- [ ] Verify CI then separate subscription billing. Fiscal policy and period closing workflow remain provisional.

## TEST-011 — current
- [x] Verify nine migrations and twelve suites; all PASS.
- [ ] Next: platform subscription terms, non-overlapping invoice service periods, verified payment and isolated billing permissions, tenant own read-only visibility. No automatic grant of modules; approved module decisions remain sole entitlement. Then remaining content/ops/backup/API domains. Accounting policies remain provisional.

## BUILD-010 — current
- [x] Implement separate subscription terms, invoices and verified billing receipts; tests.
- [ ] Verify full CI then complete CRM interactions, catalog media/category hierarchy and tenant content, before ops/outbox/backup/API. Platform billing lifecycle and accounting policy remain provisional.


## Checkpoint REQ-015 — newest next actions, supersedes previous priorities
- [x] Inspect latest repo (as of baseline BUILD-009) and existing prototypes for duplicate schema; add owner-requested legal/partners/org/user settings + Commerce-only visitor/source tracking design in `docs/TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA.md`.
- [x] Extend target ERD, master plan, AGENTS and decisions; note **public** repository and no real personal data allowed.
- [ ] **First** verify 0009 run on GitHub Actions and test logs (if workflow quota prevents, record blocker; do not label PASS).
- [ ] In next versioned migration after 0009, implement scoped tenant legal profile, partner/representative and organization/user setting entities with composite FK, RLS, permissions and negative tests; reuse existing Tenants/Users/Memberships.
- [ ] Implement real Commerce entitlement/purchase **AND** superadmin module approval check; source-of-truth for entitlement must be independent of a second module-enabled flag.
- [ ] Add visitor sessions/events (consent, privacy, retention, bot filtering, tenant-safe attribution) and link verified traffic/CRM channels to existing `crm.customers` without creating duplicate Customers. Add isolation, non-entitled tenant, cross-store same-customer, and conversion tests.
- [ ] Build eventual API/dashboard by tenant: visitor source/UTM/campaign, conversion, orders, legal info, partners, users and settings with auditable export.
- [ ] CI/load/security tests with synthetic data; no legacy/production modifications or access. After **each action** append WORK_LOG and update state/next actions with remote commits.

## TEST-012 — current (supersedes REQ-015 stale test status, not its scope)
- [x] Verify 0009 and 0010 CI: runs 45413678605 and 45414085343, all 13 suites PASS at latest tested code.
- [ ] Next migration 0011: implement D-014/REQ-015 legal tenant dossier, stakeholder/representative records, addresses and constrained tenant/membership settings with tenant-safe FK, RLS, synthetic tests; preserve existing canonical Tenants/Users/Customers.
- [ ] Explicit Commerce paid entitlement tied to verified billing and separately approved module; then consent-aware sessions/events, customer acquisition and order attribution. No inferred entitlement from generic subscription; no real personal data. Then CRM/catalog/content/ops/outbox/backup/API and performance/security review. No legacy access/deployment.

## BUILD-011 — current
- [x] Implement five dependent dossier/settings tables and shared audit metadata, tests.
- [ ] Verify full CI; then explicit Commerce purchase entitlement plus approved module, privacy-aware visits and attribution. Legal vault, platform audit access, ownership validation and complete audit coverage pending.

## TEST-013 — current
- [x] Verify full 11 migration/14 suite CI; all PASS.
- [ ] Next explicit paid Commerce entitlement sourced from verified platform billing and independent approved module gate. Then privacy-aware visitor sessions/events, verified customer source and order attribution. Complete legal dossier verification/vault/audit later; no real personal data, legacy access or deployment.

## BUILD-012 — current
- [x] Author explicit paid Commerce entitlement and approval gate, tests.
- [ ] Verify CI then add consent-aware visitor sessions/events and verified acquisition attribution using canonical CRM customer. No real tracking or legacy access.

## TEST-014 — current
- [x] Verify all 12 migrations and 15 suites; PASS.
- [ ] Next migration 0013: consent-aware visitor sessions/events with Commerce eligibility, trusted collector, tenant isolation, idempotency, retention and synthetic tests. Then verified customer acquisition and order attribution, no duplicate customers. No real data, legacy access or deployment.

## BUILD-013 — current
- [x] Author paid/approved consented visitor sessions/events and derived source reports.
- [ ] Verify CI then verified customer acquisition and order attribution; design privacy-safe retention and consent evidence, multi-site and load tests. No actual visitor tracking, legacy access or deployment.


## Checkpoint REQ-016 — most recent action list (supersedes earlier scope and old web-only plan)
- [x] Verify existing product pricing and app-model status in GitHub. Price lists/temporal entries exist; automatic multi-price customer/quantity/channel resolver not implemented. No app analytics SQL found in migrations reviewed.
- [x] Add complete app install/distribution/first-open/visitor/attribution/quality and cross-channel reporting requirements, plus multi-price scenarios in `docs/APP_ANALYTICS_MULTI_PRICE_FA.md`, with appendages to AGENTS, TARGET_ERD, MASTER_PLAN, WEB ATTRIBUTION design and D-015.
- [ ] **NEXT EXACT ACTION**: verify 0012 Commerce entitlement SQL tests and GitHub Actions evidence (do not claim PASS without it).
- [ ] Check for any newly added migrations before writing next numbered SQL; avoid duplicate schema under concurrent work.
- [ ] Implement unified `analytics.sessions` and `analytics.events` for web and apps, tenant/app eligibility, consent, first-open/install references, official marketplace aggregates and customer-source linkage (same CRM customer, no duplicate Users/Customers/Orders). Incremental migrations + synthetic tests and meaningful privacy limits.
- [ ] Add `platform.applications`/`app_releases` only after verifying no equivalent registry; consider multi-tenant application ownership with explicit scope.
- [ ] Build price selection from **existing** `catalog.price_lists` and `catalog.price_entries`: client groups, wholesale/VIP/retail, contract, channel/app/site, quantity tiers, valid periods, currency and checkout consistency. New rules/child relations only where necessary, no parallel price master.
- [ ] Report app/download/active user/conversion per tenant to superadmin and authorized tenant admin; downloads from stores as externally sourced aggregate, not inferred from app opens. Test cross-tenant denial, consent/retention, dedupe, pricing conflict and concurrent checkout. No real data, legacy access or deployment.
- [ ] Commit WORK_LOG, PROJECT_STATE and NEXT_ACTIONS after each action and verify SHA.

## TEST-015 — current (D-015/REQ-016)
- [x] Verify 13 migrations/16 suites, including 0012 and 0013; PASS.
- [ ] Read docs/APP_ANALYTICS_MULTI_PRICE_FA.md and migrate/generalize 0013 tables into shared analytics.sessions/events. Separate app paid entitlement plus approval, scoped registry/releases, installs/first_open and distribution reports; synthetic tests. No parallel masters.
- [ ] Verified customer/order attribution, consent and retention; extend existing catalog price lists/entries with audience/channel/quantity resolution and server checkout enforcement. No second price master. Then remaining CRM/catalog/content/ops/backup/API and security/performance. No real data or legacy access.

## BUILD-014 — current
- [x] Implement shared analytics and app installation/registry foundation, tests.
- [ ] Verify CI and actual logs; then official distribution reports with independent source metrics and idempotency; verified customer/order attribution and price resolver using existing price lists. Shared apps, privacy, quality metrics and load tests remain pending. No real data or legacy access.

## TEST-016 — current
- [x] Verify 14 migrations, 17 suites including shared analytics and previous concurrency tests; PASS.
- [ ] Next: official app distribution report ingestion with provider provenance, tenant/app/release scope, exact idempotency, explicit unknown vs zero and distinct market metric definitions. No fabricated download statistics or user-level inference. Then verified acquisition/order attribution and existing price list audience/channel/quantity resolution and checkout checks. Shared app assignment, quality telemetry, consent/retention scheduler and load tests remain pending. No legacy/production access.

## BUILD-015 — current
- [x] Author official distribution aggregate schema/import API and tests.
- [ ] Verify full CI including parallel content/CRM changes; resolve duplicate numeric migration prefix by coordination before deployment. Then verified customer/order attribution using existing CRM consent/session references; authorized price list resolution. Actual provider connectors, coverage and reconciliation pending. No real data or legacy access.

## TEST-017 — current
- [x] Verify distribution and integrated regression, including 0013_content_crm_engagement and all 3 concurrency suites; 19 suites PASS at af330fdd8dbc2b07175bea1e68ae1cb70a8e10f2.
- [ ] Reconcile unique migration identifiers with parallel work before production migration tracking; do not overwrite or delete other contributor changes.
- [ ] Implement verified customer acquisition and order attribution from shared analytics sessions, canonical CRM and sales, with consent/retention and no duplicate master; inspect current tree for overlapping parallel work first. Then existing price list audience/channel/quantity resolution and checkout enforcement. Provider adapters and ownership verification, coverage matrix, shared apps, quality metrics, privacy scheduling and load/security review remain pending. No real data or legacy access.


## Checkpoint SOURCE-004 / BUILD-013..015 — MOST RECENT (supersedes prior outdated TODOs)
- [x] GitHub-only read of source models from both legacy repos; **182 ERPPlus, 52 CommerceAI EF DbSets** inventoried. No old DB reads or writes.
- [x] Add full source declaration register, pinned sample field evidence and **57 canonical target table groups** in `docs/LEGACY_DBSET_COVERAGE_2026-11-24.md`, `docs/SOURCE_FIELD_EVIDENCE_FA.md`, `docs/CANONICAL_TARGET_TABLE_DICTIONARY_V1_FA.md`.
- [x] Author 0013 (content/CRM, 5 tables + tests), 0014 (catalog/media/volume pricing, 6 tables + tests), 0015 (HR/payroll/commission, 7 tables + tests). **No test PASS claim yet**.
- [ ] **IMMEDIATE ACTION:** read latest GitHub main/CI Actions results for **0012–0015**, obtain exact run/job/SHA evidence. Fix any observed migration/test failures before writing more overlapping SQL; don't assume public repo => Actions quota available. If CI inaccessible, label UNVERIFIED, not PASS.
- [ ] Verify security/tenant isolation, module authorization, FK, encrypted CRM messages, HR privacy, price-tier quote vs actual checkout. Check existing 0014 quantities selection does not implicitly authorize VIP/wholesale price list.
- [ ] Complete remaining source field/relationship inventory (the 234 DbSet enumeration is name coverage, not field completeness) and raw-SQL/file/job storage discovery from GitHub code only, no live database.
- [ ] Next independent canonical business domains (in order, not parallel duplications): supplier/purchasing & warehouse transfers/lot/serial/cost; shipping/promotion/tax/invoices; receivables/bank/cheques/installments; CRM knowledge/articles/SEO/notifications; AI jobs/usage credits; integration market price observations/workflow; app/web analytics, tenant backup/restore and admin metrics.
- [ ] After each domain, write versioned migration + synthetic acceptance/negative/concurrent tests, update mapping; preserve prior tables and do not copy legacy EF models blindly.
- [ ] Require final owner approval, migration/rollback and staging isolation/load/recovery tests before any transfer of old data. Don't touch existing servers or databases or request Desktop Commander.
- [ ] Update WORK_LOG, PROJECT_STATE, NEXT_ACTIONS, CHANGELOG after each action and verify GitHub commit SHAs.

## BUILD-016 — current
- [x] Verify parallel catalog/HR baseline runtime (21 suites PASS); implement verified acquisition and order attribution on current canonical masters.
- [ ] Verify current full CI, fix observed errors; then inspect existing price tiers and implement authorized list resolution and checkout integration, and remaining D-016 procurement/warehouse, banking, shipping, AI/ops domains. Coordinate migration prefix collisions and privacy scheduler; no operational access.


## Checkpoint PRICE-017 — LATEST, takes precedence on catalog pricing
- [x] Reopen source 0004, 0014 and handoff; confirm existing single canonical price list+entries and authored quantity tiers.
- [x] Register owner's 4 categories **original / discounted / colleague / wholesale** in new design `docs/FOUR_PRODUCT_PRICE_TYPES_FA.md`, AGENTS D-017, DECISIONS, ERD and MASTER_PLAN. No price master duplication.
- [ ] **Immediate gate**: get exact GitHub Actions CI evidence for migrations 0012–0015 (including 0013–0015 tests) and fix demonstrated failures; if unable mark UNVERIFIED.
- [ ] Next incremental implementation: bootstrap 4 standard tenant price lists, validate discount <= original with identical currency/variant/validity, implement wholesale quantity threshold, colleague entitlement, deny public reading private price lists and prevent client-controlled list id escalation. Use only existing `catalog.price_lists`, `catalog.price_entries`, `catalog.price_quantity_tiers`.
- [ ] Test ordinary guest view (original struck-through when discount), colleague and wholesale authorization, expired discounts, invalid price, tenant isolation, quantity thresholds, concurrency and checkout server-side price recalculation + immutable order price snapshot.
- [ ] No Desktop Commander, old DB, old repos writes or production server changes; record actual tests/commits after every action.

## TEST-019 — current (D-017/PRICE-017)
- [x] Verify latest 19 migration files/22 suites including attribution, HR and catalog; PASS.
- [ ] Read docs/FOUR_PRODUCT_PRICE_TYPES_FA.md, D-017, and current pricing and checkout SQL; implement original, discounted, colleague, wholesale categories in existing price lists, authorization, discount consistency, deterministic quantity selection and server checkout snapshot; prevent direct private-price exposure. No duplicate price master. Recheck main before edits.
- [ ] Positive app attribution and end-to-end checkout, authenticated messenger sources, consent revocation when CRM disabled, privacy scheduler, anonymized aggregates; then remaining D-016 procurement, transfers, costing, fiscal invoices, banking, AI/integrations/ops. Coordinate duplicate migration prefixes before deployment. No production access or real data.

## BUILD-017 — current
- [x] Author four-price controls, resolver and line checkout snapshot, tests.
- [ ] Verify CI; add actual concurrency price/eligibility and mixed standard cart/paid channels tests, inspect private price bypasses and remove legacy retail compatibility before production. Then remaining D-016 domains.

## TEST-020 — current
- [x] Verify four-price migration and all 23 suites; PASS.
- [ ] Harden 0017: mixed-list carts, paid web/app checkout, discount and eligibility expiration/currency tests, direct private list/entry/tier access and service capability boundary, concurrent price/eligibility mutation vs checkout with lock-order review. Replace legacy retail fixtures and remove legacy fallback; validate bootstrap/upgrade constraints without relying on unmapped superuser. No customer-facing API until trusted authentication and row access review.
- [ ] Then suppliers and purchasing, warehouse transfers/lot/serial/cost, shipping/promotion/tax/invoicing, banking/installments, AI/ops/backup/API. Coordinate duplicate migration identifiers. No operational access or deployment.

## BUILD-018 — current
- [x] Author original-only checkout, separate channel capabilities, bootstrap validation, lock-first pricing, mixed cart/expiry and race tests.
- [ ] Verify all CI and fix observed failures; then canonical counterparties/supplier purchasing and goods receipt into existing stock ledger. Review payable accounting and remaining D-016 domains. No deployment.

## TEST-021 — current
- [x] Verify 0018 and complete regression: 25 suites PASS, actual two competing price/eligibility checkout locks observed. Removed retail checkout bypass; synthetic fixtures updated, paid app/web tested.
- [ ] Next inspect current tree and D-016 source evidence/dictionary, design one canonical tenant counterparty/supplier relationship without copying customer master; purchase orders and lines, idempotent goods receipts into existing inventory.stock_ledger. Provisional full receipt and explicit payable/accounting policy; test cross-tenant and concurrent receipts. Then transfers/lots/cost, shipping/tax/invoices, banking/AI/ops/backups/API. Coordinate duplicate migration IDs and production gates; no real data or operational access.

## BUILD-019 — current
- [x] Author counterparty/purchase commitment/full receipt, stock movement integration and actual receipt race test.
- [ ] Verify full CI, fix failures; then supplier invoice, payable/settlement accounting via existing journal, cost valuation and partial receipt lifecycle. No deployment, real data or legacy access.

## TEST-022 — current
- [x] Verify 0019 and full regression; 27 suites PASS, actual concurrent receipt lock and exactly one movement observed.
- [ ] Next inspect latest tree and D-016 dictionary/evidence. Implement verified supplier invoice linked to canonical received purchase, no duplicate party/product/stock master; unique invoice ref, derived payable balance and balanced journal recognition, idempotent settlement and period/account checks. Separate physical receipt from invoice/financial liability. Provisional single full invoice/payment if appropriate, no actual money or production access.
- [ ] Extend partial receipts/returns, cost valuation, transfers/lot/serial/expiry, shipping/promotions/tax/invoicing, bank/cheques/installments, AI/ops/backup/API. Coordinate migration IDs, authenticated service and full security/performance/rollback review.

## BUILD-020 — current
- [x] Author supplier invoice, settlement and derived payable, atomic journal tests.
- [ ] Verify CI, fix failures. Add concurrent settlement and closed-period settlement tests, then transfers and valuation/lot/serial, partial receipts and returns. Accounting policy, bank verification and real deployment remain pending.

## TEST-023 — current
- [x] Verify 0020 and all prior regressions: 28 suites PASS, including five previous concurrency suites.
- [ ] Add actual competing supplier settlement race (distinct refs, overpay denial, exact retry), closed-period settlement rollback and account mapping review. No actual disbursement. Then implement interwarehouse transfers through existing stock ledger, traceability and valuation, partial receipt/returns. Continue tax/shipping, banking/cheques/installments, AI/ops/backups/API and coordinated migration IDs, service authentication, security/performance and rollback review. No production access or real data.

## BUILD-021 — current
- [x] Author atomic interwarehouse transfer and supplier settlement hardening, tests.
- [ ] Verify all CI; then actual concurrent transfer vs reserve/transfer, cost valuation and lot/serial/expiry integration with all existing stock mutation paths. Transit/approval and bank account mapping remain pending. No deployment.

## TEST-024 — current
- [x] Verify 0021 and all previous regressions; 30 suites PASS including six actual concurrency suites. Competing supplier settlement rejected without duplicate payment/journal.
- [ ] Next exercise concurrent transfer versus reservation/transfer and opposite direction lock ordering. Then design canonical lot/serial/expiry traceability integrated with receipt, reservation, sale, return, adjustment and transfer; costing and COGS via existing journal. No second stock master. Transit/approval, partial receipts/returns, bank account semantic mapping, tax/shipping, banking/cheques/installments, AI/ops/backups/API and unique migration identifiers pending. No real data or deployment.

## BUILD-022 — current
- [x] Author traceability foundation and transfer/reserve concurrency tests.
- [ ] Verify CI; then integrate trace-aware receipts, reservations/fulfillment, return and transfer with same ledger; add expiry/FEFO and cost layers, actual serial contention and lock order tests. Tracked variants currently fail closed for unadapted paths. No real data or deployment.

## FIX-003 — current
- [ ] Verify rerun including inventory/transfer races; do not mark BUILD-022 passed until logs confirm. Trace-aware receipt/reservation/fulfillment/return/transfer still pending.

## TEST-025 — current
- [x] Verify 0022, FIX-003 and full regression; 32 suites PASS including competing transfer/reserve and reverse transfers.
- [ ] Next implement trace-aware purchase receipts and atomic transfers with exact lot/serial ledger provenance, then trace allocations in reservations/checkout/fulfillment and returns. Test expired stock, duplicate serial contention, rollback and lock order across variants. FEFO and costing/COGS follow; no parallel inventory master. Review tenant scoping, privileged bootstrap, transit, partial receiving and all remaining D-016 domains. No operational access, real data or deployment.

## BUILD-023 — current
- [x] Author trace-aware receipt and transfer allocation in existing relations.
- [ ] Verify full CI; then dedicated concurrent serial receipt/transfer and trace reservations, fulfillment/returns, FEFO and cost. No production changes.

## TEST-026 — current
- [x] Verify 0023 and all regressions: 33 suites PASS, seven previous concurrency suites.
- [ ] Next tracked reservation allocation, checkout/fulfillment and return with exact lot/serial movement provenance, expiry handling and FEFO. Add tracked serial contention tests. Then valuation/COGS and remaining D-016 domains; full receipt only, no transit/partial receiving or historical backfill yet. No operational access, real data or deployment.

## BUILD-024 — current
- [x] Author tracked allocation and sale/return lifecycle; update prior trace tests.
- [ ] Verify full CI, fix failures; add actual competing tracked serial reservation and receipt races, then valuation/COGS and remaining domains. No real data or deployment.

## FIX-004 — current
- [ ] Verify 0024 rerun, including tracked sales and prior regressions. First run failed before tests; not yet certified.

## FIX-005 — current
- [ ] Verify third full CI attempt including 0024 and previous return/refund tests. No production changes.

## TEST-027 — current
- [x] Verify 0024 with FIX-004/FIX-005; 34 suites PASS. FEFO and tracked sale/return lifecycle enabled in synthetic tests.
- [ ] Add actual competing tracked serial reservation and receipt/transfer races; align total order allocation limit with return normalization cap (1000 total vs per-reservation), cover expiry/permissions/rollback. Then implement cost layers and valuation FIFO/weighted average, journal COGS and reversal, without duplicate stock. Partial/damaged/expired returns, historical migration, transit, additional D-016 domains and unique migration IDs, production review remain pending. No operational access or real data.

## TEST-028 candidate — current
- [x] Author three tracked serial contention tests.
- [ ] Verify CI and fix failures; align total checkout allocation cap with return normalization (1000), then cost valuation and journal COGS; no duplicate inventory. Partial/damaged returns and production review pending.

## TEST-028 — current
- [x] Verify dedicated serial concurrency and full regression; 35 suites PASS.
- [ ] Align total tracked checkout allocation cap with return normalization cap (1000), with boundary regression. Then cost valuation using existing stock ledger and journal: explicit FIFO/weighted average policy, cost provenance, COGS and reversals. No duplicate inventory master. Partial/damaged/expired returns, historical migration, transit, remaining D-016 domains, unique migration IDs and production review pending. No real data or deployment.

## BUILD-025 — current
- [x] Author total checkout allocation cap, boundary and rollback test, receipt cost provenance view, provisional valuation design.
- [ ] Verify CI. Then implement actual opt-in FIFO and moving weighted-average cost layers/allocation and journal COGS, handling cost provenance and transfer/return. Do not equate receipt cost evidence with stock valuation. Review accounting policy, opening/adjustment costs, partial/damaged returns, security and concurrency; no operational access.

## TEST-029 — current
- [x] Verify allocation boundary and receipt cost evidence; all 36 suites PASS.
- [ ] Implement opt-in FIFO and moving weighted average using canonical stock movements and immutable cost provenance, staged synthetic tests. Address transfers, returns, invoice timing and balanced journal COGS, rounding and unknown cost; no duplicate inventory. Accounting policy provisional pending approval. Remaining lifecycle and D-016 domains, migration IDs and production security review pending. No real data or deployment.


## BUILD-026A — current
- [x] Author restricted valuation preview and synthetic acceptance test.
- [ ] Verify exact GitHub CI run; fix failures. Next persist opt-in policy and immutable cost allocations, integrate lifecycle and balanced COGS/reversal. Preview must not be treated as accounting truth. No production access.


## TEST-030 / BUILD-026B — current
- [x] Verify 0026 all 37 suites; author immutable experimental policy and tests.
- [ ] Verify 0027 CI and repair. Then implement immutable cost allocations with canonical movement FKs, actual opt-in lifecycle guards, transfer/return and balanced COGS. No production access.


## TEST-031 / BUILD-026C — current
- [x] Verify 0027 and 38 suites; author canonical movement cost capture and tests.
- [ ] Verify 0028 CI, repair failures. Next FIFO receipt-level allocation provenance and COGS journal/reversal with matched inventory accounts, lifecycle guards and concurrent capture tests. No production access.


## TEST-032 / BUILD-026D — current
- [x] Verify 0028 and 39 suites; author FIFO receipt provenance and tests.
- [ ] Verify 0029 CI, repair. Next explicit COGS journal with source FK, matched inventory account and fiscal gate, then reversal, transfers and concurrency. No production access.


## FIX-006 — current
- [x] Diagnose CI failure and correct conflicting fixture aliases without weakening assertions.
- [ ] Verify new CI SHA, all 32 SQL + eight concurrency suites; repair any failure before COGS migration. No operational access.


## TEST-033 / BUILD-026E — current
- [x] Verify FIX-006 and 40 suites; author FIFO COGS posting and tests.
- [ ] Verify 0030 CI, repair. Then full sellable return reversal (no unbalanced asset), moving average, transfer and concurrent posting; no production access.


## FIX-007 / MIG-ID-001 — current (canonical IDs supersede historical numbering)
- [x] Diagnose failed COGS migration, correct delimiter, normalize migration/test IDs and add CI guard.
- [ ] Verify exact new CI SHA: guard (4 unit tests), 33 SQL suites and 8 concurrency suites. Fix any failure first. COGS now 0033; next new migration 0034. Then continue return reversal, moving-average posting, transfer valuation and lifecycle/concurrency. No production access.


## FIX-008 — current
- [x] Verify renumbered tree and repair actual delimiter after read-back detected replacement escaping.
- [ ] Check CI for latest exact SHA (33 SQL, eight concurrency, four guard tests). Record outcome. Next 0034 only after full PASS.


## TEST-034 / TEST-035 candidate — current
- [x] Verify FIX-008, renumbering guard and all 41 SQL/concurrency suites; add dedicated concurrent cost capture/COGS posting tests.
- [ ] Verify exact new CI SHA (33 migrations, 33 SQL + nine concurrency suites, four guard unit tests); fix failures. Next canonical 0034: return cost and journal reversal, then moving-average posting, transfer valuation and lifecycle guard. No production access.


## TEST-035 / BUILD-026F — current
- [x] Verify concurrent cost capture/COGS; author canonical 0034 full return reversal and tests.
- [ ] Verify exact new CI (34 SQL, nine concurrency, four guard unit tests), fix failures. Next integrate returned stock cost into replay with original receipt provenance, moving average, transfers and lifecycle guards. No production access.


## FIX-009 — current
- [x] Diagnose failed return reversal test and remove ambiguous PL/pgSQL variable without weakening tests.
- [ ] Verify exact new CI SHA (34 SQL + nine concurrency, four guard tests). Then canonical 0035: integrate returned stock into replay with original cost provenance; moving average, transfer, lifecycle and policy approval remain pending. No production access.


## TEST-036 / BUILD-026G — current
- [x] Verify FIX-009, author 0035 FIFO return replay and resale tests.
- [ ] Verify exact new CI SHA (35 SQL + nine concurrency, four guard tests), repair. Next moving-average confirmed COGS and returns, transfer value, lifecycle guards and return concurrency. No production access.


## FIX-010 — current
- [x] Diagnose failed combined assertion and separate capture, retry and read statements with precise failure diagnostics.
- [ ] Verify exact CI SHA (35 SQL, nine concurrency, four guard tests). If still failing inspect specific assertion/count; fix before next migration. Next canonical 0036 moving-average COGS/return, transfer and lifecycle guards. No production access.


## TEST-037 / BUILD-026H — current
- [x] Verify FIX-010 and return replay; author 0036 shared moving-average COGS and tests.
- [ ] Verify exact new CI SHA (36 SQL + nine concurrency, four guard tests), fix failures. Next 0037 moving-average historical return, transfer cost, lifecycle and concurrency. No production access.


## TEST-038 / BUILD-026I — current
- [x] Verify 0036; author 0037 moving-average historical return and resale using shared APIs.
- [ ] Verify exact new CI SHA (37 SQL + nine concurrency, four guard tests); repair. Next 0038 transfer valuation with exact paired movements and account provenance, lifecycle gates and concurrent returns. No production access.


## TEST-039 / BUILD-026J — current
- [x] Verify 0037; author 0038 ordinary moving-average atomic transfer cost capture and conservation tests.
- [ ] Verify exact new CI SHA (38 SQL + nine concurrency, four guard tests), repair. Next transfer-in account provenance and downstream COGS, FIFO cross-warehouse receipt provenance, lifecycle and concurrency. No production access.


## TEST-040 / BUILD-026K — current
- [x] Verify 0038; author 0039 recursive same-asset transfer provenance and COGS tests.
- [ ] Verify exact new CI SHA (39 SQL + nine concurrency, four guard tests), repair. Next FIFO transfer provenance across warehouses (do not duplicate ledger or allocation table), lifecycle and concurrency. No production access.


## TEST-041 / BUILD-026L — current
- [x] Verify 0039; author 0040 ordinary FIFO paired transfers and remote receipt provenance.
- [ ] Verify exact new CI SHA (40 SQL + nine concurrency, four guard tests); repair. Next cost transfer/return concurrency and lifecycle guards, complex chain capture, tracked valuation and policy approval. No production access.


## TEST-042 / TEST-043 — current
- [x] Verify 0040; extend the existing COGS concurrency suite with actual transfer, reversal and restored cost capture contention.
- [ ] Verify exact CI SHA (40 SQL + nine concurrency, five COGS race cases, four guard unit tests). Repair any failures. Next lifecycle fail-closed checks for configured variants and unposted sale/return costs; moving-average concurrency, complex dependency chains and tracked valuation remain pending. No production access.


## TEST-043 / BUILD-026M — current
- [x] Verify five concurrency races; author 0041 explicit read-only inventory-cost readiness guard.
- [ ] Verify exact new CI SHA (41 SQL + nine concurrency, four guard tests), repair. Next broaden reconciliation and lifecycle enforcement only under approved design; moving-average races, complex transfer chains and tracked valuation pending. No production access.


## FIX-011 — current
- [x] Diagnose 0041 test syntax failure and repair literal delimiters, preserving assertions.
- [ ] Verify exact new CI SHA (41 SQL + nine concurrency, four guard tests); fix remaining failures before 0042 reconciliation of replay and posted journal amounts. No production access.


## TEST-044 / BUILD-026N — current
- [x] Verify FIX-011; extend readiness with replay and journal amount reconciliation.
- [ ] Verify exact new CI SHA (42 SQL + nine concurrency, four guard tests), repair before further migrations. Next moving-average cost contention, tenant-level account reconciliation design, tracked valuation and complex transfer chains. Policy/production approval still pending. No production access.


## TEST-045 / TEST-046 — current
- [x] Verify 0042; extend current COGS harness to ten actual lock races, five per method.
- [ ] Verify exact new CI SHA (42 SQL + nine concurrency, ten COGS race cases, four guard tests). Repair failures. Next canonical 0043 tenant-level inventory cost reconciliation, complex transfer chains and tracked valuation. No production access.


## TEST-047 / BUILD-026O — current
- [x] Verify ten COGS races; author 0043 tenant-level reconciliation.
- [ ] Verify exact new CI SHA (43 SQL + nine concurrency, ten COGS race cases, four guard tests). Repair failures. Next complex transfer dependency capture, tracked valuation, accounting policy and period-close review. No production access.


## FIX-012 — current
- [x] Diagnose failed 0043 test and remove alias collision from both assertions.
- [ ] Verify exact FIX-012 CI SHA (43 SQL + nine concurrency, ten COGS races, four guard tests). Repair any subsequent failures. Only after success proceed to 0044 complex transfer chain cost capture. No production access.


## TEST-048 / BUILD-026P — current
- [x] Verify FIX-012; author 0044 connected transfer capture for both methods.
- [ ] Verify exact new CI SHA (44 SQL + nine concurrency, ten COGS races, four guard tests), repair. Next chain-specific concurrency/performance and tracked valuation design; financial policy and period-close review pending. No production access.


## TEST-049 / TEST-050 — current
- [x] Verify 0044 and add two distinct-entry chain races and bounded timing sample to existing COGS suite.
- [ ] Verify exact new CI SHA (44 SQL + nine concurrency, twelve COGS races, four guard tests); record actual CHAIN_TIMING results, repair before proceeding. Next 0045 tracked inventory valuation design/implementation preserving canonical stock ledger and source facts. No production access.


## DESIGN-0045 — current
- [x] Review canonical tracked sources and document staged design, acceptance and limitations.
- [ ] Verify TEST-050 exact SHA 9410c90335794e4b2b27b04278315deca3e2bc67 (or repair) before writing migration 0045. First 0045A read-only evidence via existing joins and tenant/permission gates, then phased tracked policy/replay/COGS. No production access.


## TEST-051 / BUILD-026Q — current
- [x] Verify TEST-050, document invalid timing, author 0045 traced evidence and monotonic timing fix.
- [ ] Verify exact new CI SHA (45 SQL + nine concurrency, twelve COGS races, four guard tests); record valid timings; repair before proceeding to 0046 explicit tracked valuation policy and shared replay design. No production access.


## TEST-052 / BUILD-026R — current
- [x] Verify 0045 and valid timings; author explicit tracked policy methods and correct stale README.
- [ ] Verify exact new CI SHA (46 SQL + nine concurrency, twelve COGS races, four guard tests). Repair before 0047 shared trace-aware replay/prefix and receipt/sale cost capture. Multi-line transfer capture, tracked COGS/returns and final policy pending. No production access.


## TEST-053 / BUILD-026S — current
- [x] Verify 0046, implement shared 0047 traced receipt/sale cost replay and capture.
- [ ] Verify exact new CI SHA (47 SQL + nine concurrency, twelve COGS races, four guard tests), repair. Next 0048 exact traced multi-line transfers via connected component; then traced COGS, return reversal and readiness. Policy approval and load testing pending. No production access.


## TEST-054 / BUILD-026T — current
- [x] Verify 0047, author 0048 multi-line traced transfer capture.
- [ ] Verify exact CI SHA (48 SQL + nine concurrency, twelve COGS races, four guard tests), repair. Next 0049 traced COGS and then return reversal/replay/readiness. No production access.


## TEST-055 / BUILD-026U — current
- [x] Verify 0048, author 0049 shared traced COGS and scoped readiness.
- [ ] Verify exact CI SHA (49 SQL + nine concurrency, twelve COGS races, four guard tests), repair. Next 0050 tracked full-return reversal and historical cost replay, reconciliation and traced concurrency. No production access.


## TEST-056 / BUILD-026V — current
- [x] Verify 0049, author 0050 exact traced return reversal and replay.
- [ ] Verify exact CI SHA (50 SQL + nine concurrency, twelve COGS races, four guard tests), repair. Next tracked cost/transfer/COGS/reversal contention and period-close design. Partial/damaged/expired returns and financial policy approval pending. No production access.


## TEST-057 / TEST-058 — current
- [x] Verify 0050; add six traced cost races per method in existing COGS suite.
- [ ] Verify exact new CI SHA (50 SQL + nine concurrency, 24 COGS races, four guard tests); repair any failures. Next period-close invariant and policy review, partial/damaged/expired return design, then other outstanding domain coverage. No production access.


## TEST-059 / BUILD-026W — current
- [x] Verify all 24 contention cases, implement 0051 read-only conservative period preflight.
- [ ] Verify exact new CI SHA (51 SQL + nine concurrency, 24 COGS races, four guard tests), repair. Next atomic period closure with explicit cutoff semantics and tenant write barrier, preserve one close_period API and exact retries, review module coverage and historical as-of policy. No production access.


## DESIGN-0052 — current
- [x] Review existing mutation and lock paths; document tenant barrier and staged acceptance.
- [ ] Verify 0051 exact run 45596926623 / aa77ac75e4245c908dad2a9c2744f65cfc8511c7 before new DDL. Then implement 0052 private tenant mutation barrier with two-direction real contention, independent tenant and no-runtime-grant tests, no public close API duplication. Integrate guard in existing close_period only after explicit cutoff/module coverage policy and regression tests. No production access.


## TEST-060 / BUILD-026X — current
- [x] Verify 0051; author private 0052 barrier and bidirectional contention tests.
- [ ] Verify exact CI SHA (52 SQL + nine concurrency, 24 existing COGS races and new barrier assertions, four guard tests); fix first. Next 0053 guarded single close_period only after cutoff/module/no-inventory and lock upgrade/period lock order policy, admin paths and timestamp review. No production access.


## TEST-061 / BUILD-026Y — current
- [x] Verify 0052; author 0053 atomic close and actual contention tests; exact code SHA 36d261c1c1bb57a6e4bf012c52cc155325fea15f.
- [ ] Verify exact 0053 CI (53 SQL + nine concurrency; four guard tests; 24 COGS plus barrier and real close cases); repair before advancing. Check historical/as-of semantics, nonempty positive close fixture, disabled-module history, timestamp/backdating and privileged administrative boundaries, actual module decision race; assess lock overhead. Then partial/damaged/expired returns design and outstanding domains. No operational access.

## TEST-062 / TEST-063 — current
- [x] Verify 0053 at run 45601424659 / 36d261c1c1bb57a6e4bf012c52cc155325fea15f (62 suites); add targeted real module decision contention regression to existing harness.
- [ ] Verify exact new CI SHA, repair if needed; then prove positive nonempty historical close with explicitly synthetic historical fixtures, audit authoritative timestamps, module expiry and privileged/global identity changes. Historical as-of after later activity remains unsupported; partial/damaged/expired returns next only after period close limitations are documented and required decisions approved. Next unused migration 0054. No operational access.

## TEST-063 / TEST-064 — current
- [x] Verify TEST-063 exact CI; add synthetic positive nonempty historical close fixture to existing COGS harness.
- [ ] Verify new exact CI SHA and repair failures first. Then test/assess late cost capture relative to cutoff, time before row barrier, expiry and privileged administration boundaries; preserve conservative close until owner approves policy. Historical as-of with later activity remains unsupported. No new migration unless required; next unused ID 0054. Partial/damaged/expired return design afterward. No operational access.

## TEST-064 / TEST-065 — current
- [x] Verify exact TEST-064 CI; extend existing suite with rollback-only late capture and expiry observations, and targeted privileged role/grant assertions.
- [ ] Verify TEST-065 exact new CI SHA, repair failures first. Review timestamp-before-row-barrier risk with controlled synthetic test if necessary; document unresolved cutoff/as-of, late capture and expiry policy for owner rather than silently change accounting. Then design partial/damaged/expired returns from existing canonical sales/inventory/finance structures. Next unused migration ID 0054. No operational access.

## DESIGN-0054 — current
- [x] Review existing return/refund and cost sources; document staged partial/damaged/expired design, open policies, acceptance and no duplicate masters.
- [ ] Verify TEST-065 run 45606515589 at 7ad0480313c54bc7160f14786dccaa89e5859dbd; repair before executable changes.
- [ ] Audit full return/refund callers and constraints against latest migration tree, then first minimal 0054 read-only evidence or independently justified line fact; keep unapproved valuation/refund/disposition choices provisional and fail closed. Time-before-barrier risk remains unverified; as-of and temporal policy still open. Do not start financial activation or production access. Next unused migration 0054.

## TEST-065 / BUILD-026Z — current
- [x] Verify TEST-065; add 0054 read-only existing sale/return capacity evidence with ordinary and traced tests.
- [ ] Verify exact new CI SHA, fix before continuing. Then design minimal independent return-line relation only if needed and audit all full-return/refund callers and stock valuation/period gates; cap and disposition must fail closed until supported. Temporal observations documented, final policy unapproved. Next unused ID 0055 (after verifying 0054). No operational access.

## TEST-066 / BUILD-027A — current (owner priority)
- [x] Verify 0054; implement provisional 0055 guards and regressions for late cost and live close-time module expiry.
- [ ] Verify exact new CI SHA; fix any failure first. Review commit-time entitlement behavior, time-before-row-barrier boundary and lock/performance impact; final policy requires owner approval. After verified guard, return to DESIGN-0054 with independent line fact only if needed, cap/identity/non-sellable disposition; no financial activation. Next unused ID 0056; no operational access.

## REVIEW-027A — current
- [ ] Verify 0055 exact run 45610267991 / b321c2ddc975af47acf89337b234be4c48c0efdd; repair any failure first.
- [x] Specify deterministic commit-expiry and pre-barrier timestamp ordering tests in existing inventory valuation design; no runtime policy change.
- [ ] Implement observations in the existing synthetic concurrency fixture once 0055 is green, preserve all guards, verify actual CI. Then proceed with minimal physical return-line/cap design, no financial activation without approved policies. Next unused migration 0056. No operational access.

## TEST-067 / FIX-027A — current
- [x] Inspect exact 0055 failed CI, isolate role-grant and membership fixture namespace and tenant scope; preserve all guards.
- [ ] Verify exact new full CI SHA, especially independent committed late-cost close rejection. Repair further failure before any new migration. Then execute REVIEW-027A commit-expiry and pre-barrier timestamp observations and proceed with DESIGN-0054. No production or final financial policy changes. Next unused ID 0056.

## REVIEW-027B — current
- [x] Audit all 55 migration table declarations and return/refund dependencies; establish independent receipt/disposition line gap and compatibility matrix in inventory valuation design.
- [ ] Verify FIX-027A run 45618642657 at 0f0614a49dd5ce236e88528d43afddde42b62c59; repair any failure before advancing.
- [ ] Execute REVIEW-027A commit expiry and pre-barrier timing observations, then minimal 0056 only with exact composite FK/RLS/ACL/barrier and legacy compatibility. Keep existing unique order/payment constraints until cap and dependent paths are safe; no active partial valuation/refund or production access.

## TEST-069 / TEST-070 — current
- [x] Verify exact corrected 0055 CI (64 suites); add two remaining temporal observations in existing synthetic COGS harness.
- [ ] Verify exact new CI SHA and fix failures. Characterization only: if observed, document commit-expiry and pre-barrier ordering as limitations, not approved policy. Review mitigation for all relevant writers, then minimal 0056 according to REVIEW-027B, no new table unless necessary and no unapproved financial activation. Next unused migration 0056. No operational access.

## REVIEW-027C — current
- [x] Check exact canonical keys and reduce candidate return-line identity to reservation and original movement; document composite FK targets and negative tests.
- [ ] Verify TEST-070 run 45621026901 at df91393c97e5668b548975cdd21411eabb2458cb and fix any failure; record observed limitations. Then minimal 0056 structural implementation only with exact constraints, RLS/ACL/barrier, no runtime/executor DML before safe writer and cap. No policy activation or operational access.

## TEST-070 / BUILD-027B — current
- [x] Verify TEST-070 and record both unresolved temporal boundaries; add dormant 0056 structural relationship and rollback-only tests.
- [ ] Verify exact 0056 CI SHA, repair failures first. Next implement safe single canonical receipt writer/cap and legacy compatibility before enabling any partial/non-sellable receipt; review all writers for timing mitigation, retain no unapproved accounting/refund/disposition activation. Owner decisions: commit entitlement, effective cutoff and quarantine/financial policy. Next unused migration 0057; no operational access.

## TEST-071 / BUILD-027C — current
- [x] Verify 0056 and add locked aggregate receipt-line cap, append-only enforcement and actual privileged synthetic race with no write grants.
- [ ] Verify exact 0057 CI, fix failures. Next integrate existing receive_full_return_allocated only, preserve exact retry/old ledger fallback without counting lines twice, add minimal scoped writer privilege and actual runtime race. Evolve dormant-only tests explicitly without weakening negative assertions; no partial/non-sellable/refund/valuation activation until safe and approved. Next unused 0058. No operational access.

## REVIEW-027E — current
- [x] Audit exact writer grants and plan scoped evidence access and independent structural/runtime test fixtures, without removing old assertions.
- [ ] Verify 0057 exact CI run 45625448713 at aa1dd061853a028ce11d61bfc9a490130fefc4d6, fix failures first; then 0058 integrate same full-return writer and cap with actual runtime concurrency and legacy retry evidence. No partial/non-sellable/refund activation. No operational access.

## TEST-072 / BUILD-027D — current
- [x] Verify exact 0057 CI and integrate existing full-return writer with immutable lines and cap; extend SQL and concurrency tests.
- [ ] Verify exact 0058 CI SHA, repair failures without weakening checks. Then actual upgrade fixture pre-0058 legacy retry and read-only capacity exact line reconciliation; retain no partial/non-sellable/refund activation. Owner decisions for quarantine, valuation, late/commit expiry remain open. Next unused ID 0059. No operational access.

## FIX-028A — 2026-11-25
- TEST-073 / FIX-028A: exact 0058 run 45627260327 job 139250654541 at cad159104e2d70c7d01e568993ae9e279b373f36 failed only at pricing concurrency after all 58 migrations, SQL suites and identity/inventory/sales races passed. Logs show PASS canonical full-return writer, RETURN_WRITER_RACE, RETURN_CAP_RACE, both stale price checkouts rejected; pricing.sh final count still expected one order/reservation but preceding expanded sales fixture creates three. Fix only pricing test fixture expectation: assert exact three before and after, compare full ordered order and reservation snapshots after each race, retain actual lock wait, SQLSTATE 23514 and rejection checks. No migration, runtime, ACL, RLS or financial change; later concurrency suites skipped, overall CI not yet verified. Rerun full CI, then actual pre-0058 upgrade fixture and 0059. No operational access.

## TEST-074 / TEST-075 — current
- [x] Verify exact corrected 0058 full CI; add isolated actual 0057-to-0058 upgrade test job without altering existing migrations or foundation tests.
- [ ] Verify both jobs at exact TEST-075 SHA, fix any failure. Then 0059 read-only exact receipt line reconciliation in existing capacity API; keep zero-line legacy fallback and no double count. No partial/non-sellable/refund activation or final financial policy. Next unused migration 0059. No operational access.

## FIX-028B — 2026-11-25
- TEST-076 / FIX-028B: exact TEST-075 run 45630535075 at 5ff26ddc69c7db6821362136b1a9670cd17f3156: foundation job 139262191015 completed SUCCESS (58 contiguous pairs, 86 tables, 67 PASS, all nine concurrency suites, 24 COGS races); independent return-upgrade job 139262189394 failed after UPGRADE_BASELINE committed actual pre-0058 ordinary/traced returns and passed header/movement/empty-line assertions. Snapshot generated SQL referenced to_jsonb(t) without FROM alias; ERROR column t does not exist, before migration 0058. Fix exactly one line by adding AS t to generated SELECT FROM clause. Preserve full all-table comparison, legacy retries, negative tests and new-writer coexistence; no migration/runtime/ACL/policy change. Both jobs must pass before 0059. No production access.

## TEST-077 / REVIEW-027F — current
- [x] Verify actual pre-0058 committed history upgrade job and document read-only line reconciliation with zero-line legacy fallback limitation.
- [ ] Verify foundation job 139272048763 / full run 45633317796 at exact 42dd7ea102b417d4026f388dab5c45642cf3f9a9; then implement 0059 only on existing capacity function and matching tests, extend isolated upgrade test to prove actual legacy fallback and reject incomplete/non-sellable evidence. No new table, policy or operational access. Next unused ID 0059.

## TEST-078 / BUILD-027E — current
- [x] Verify both corrected 0058 jobs; implement 0059 exact read-only receipt reconciliation and extend actual upgrade evidence.
- [ ] Verify exact 0059 CI both jobs; fix any failures. Next review partial/damaged/expired physical receipt lifecycle, quarantine and independent facts without duplicates. Do not activate partial/non-sellable/valuation/refund without approved policy. Owner decisions for commit entitlement and temporal cutoff still open. Next unused ID 0060. No operational access.

## TEST-079 / REVIEW-028C — current
- [x] Verify 0059 actual upgrade job and inspect existing receipt/refund/warehouse/trace/valuation constraints. Record concrete gaps and preserve current controls.
- [ ] Verify foundation 139280341524 exact run 45635678490 before changing SQL; audit remaining latest callers and design safe partial receipt/custody lifecycle without duplicate tables; next unused 0060. No partial/non-sellable/refund/valuation activation before owner approval; unresolved temporal boundaries remain. No operational access.

## TEST-080 / REVIEW-028D — current
- [x] Verify both 0059 jobs and scan all 59 migrations for receipt/refund/availability dependencies; define read-only lifecycle contract and regression matrix.
- [ ] Next unused 0060: implement synthetic-only safety prerequisite if justified; verify live entrypoints fail closed for unsupported partial/non-sellable receipts and no effects, audit transitive dependencies. No partial/quarantine/financial policy activation before owner approval. No production access.

## BUILD-028E — current
- [x] Identify and close ignored disposition field on existing traced full-return entrypoint; add synthetic negative and exact replay tests.
- [ ] Verify both 0060 CI jobs at exact SHA, fix failures. Then evaluate partial receipt/custody and trusted history marker only with owner-approved business policy; preserve financial and temporal gates. Next unused ID 0061. No operational access.


## TEST-081 / REVIEW-029 — current (supersedes earlier next-action entries)
- [x] Verify exact 0060 baseline and both jobs; review strict return contract and test evidence.
- [x] Reconcile all 57 groups against 60 migration texts and update dictionary; 57 groups: 22 verified prototype, 12 partial, 23 not implemented. Counts classify groups, not percentage of database completion; some groups overlap (e.g. parties, distribution, tax submissions), and verified means relevant structures and baseline CI exist, not every field, policy or operation is validated. All 60 migration texts scanned for CREATE TABLE, ALTER move/rename, DROP, functions/views; selected definitions and 0060 acceptance/logs reviewed. No independent exhaustive column/ACL/call graph or load audit.
- [ ] Next: REVIEW-029A — core dependency design for tenant business locations and site/domain registry: compare core tenant addresses/settings, inventory warehouses, analytics sessions/events and platform applications, canonical relationship/uniqueness/RLS/ACL and tests; design one tenant child per genuinely distinct concept, no duplicate store/warehouse/site master. Only then allocate 0061 if justified. Parallel policy-gated backlog (not implement concurrently): counterparty roles and identity before bank/cheques/AR/settlement/installments; shipping and delivery; fiscal invoice/tax (owner approved legal/financial policy); CRM tags/queues/favorites/alerts, licensing/auth security (owner policy), analytics/notification/outbox/workflow/AI/ops backup/restore/load. No new table solely on dictionary label.
- [ ] Open gates: module entitlement expiry after function returns and before COMMIT; inventory recorded_at before period barrier acquisition (0055 and actual COGS observations, not fixed). Retain exact existing tests; resolve only with owner-approved temporal policy and deterministic transaction/lock tests. Partial/non-sellable physical custody, quarantine, refund/valuation policy remain blocked; full return path unchanged. No production, legacy access, or final policy activation.
- [ ] Verify checkpoint commit and associated CI if triggered; next unused migration 0061. No operational access.


## REVIEW-029A — current (supersedes previous next action)
- [x] Audit existing core addresses/settings, warehouse, app and analytics schema; identify existing website_host collision and audit target gap; draft minimal location design and test matrix in docs/BUSINESS_LOCATION_SITE_DESIGN_FA.md.
- [ ] Verify exact run 45641015000 both jobs at aaf1bf5e490e36b6412b513f1956d32b0f9a8612; if failed, fix root cause before development. If successful, implement minimal 0061 business locations and matched SQL acceptance plus actual competing-write test, run full CI and update coverage only after PASS. Keep site registry separate; complete all website_host caller/compatibility inventory and approved domain security policy before implementation. No new DDL until CI passes.
- [ ] Preserve all prior open temporal, custody, refund/valuation and production gates. Next unused migration 0061.


## TEST-082 / BUILD-029B — current
- [x] Verify exact run 45641015000 both jobs and author minimal 0061 business_locations + SQL/real concurrency tests.
- [ ] Verify new exact 0061 SHA and both CI jobs. Fix only actual failure if any; then update verified counts/dictionary. Next review website_host references in all migration/test files, informational vs routing semantics, migration compatibility and domain security policy; no duplicate host or operational activation. If security decision blocked, advance independent CRM/catalog requirements instead. Next unused 0062 only after verification. Temporal/financial/production gates remain.


## TEST-083 / BUILD-030A — current
- [x] Verify 0061 exact both jobs, update verified coverage; audit all migration/test host references; author dormant 0062 site identity and exact retry tests.
- [ ] Verify exact 0062 SHA and both CI jobs, repair actual failure only. Check explicit runtime base-table count; update verified coverage only after success. Next unused 0063; no domain claim/routing or host duplication. Advance independent CRM/catalog favorites/tag or counterparty design while owner domain policy remains open.
- [ ] Preserve temporal, custody, refund/valuation gates; location retry contract remains open. No production access.


## TEST-084 / FIX-030A — current (supersedes prior next action)
- [x] Verify failed exact 0062 CI run 45647070040; inspect actual log and fix missing aliases in both full JSON snapshots only; preserve all assertions.
- [ ] Verify new correction SHA and both CI jobs; if any actual failure, inspect and fix root cause before next migration. Check runtime base-table count diagnostic and actual site concurrency evidence. Last fully verified 0061; next unused 0063 after success. Then advance independent CRM/catalog favorites/tag or counterparty design. No domain routing/ownership activation or duplicated host; existing temporal/financial/custody gates unchanged. No production access.


## REVIEW-030B — current
- [x] Verify intermediate 0062 correction job steps and design CRM tag relationship/test matrix in docs/CRM_CUSTOMER_TAG_DESIGN_FA.md.
- [ ] Verify final exact run 45649134004 both jobs and logs (runtime base table count and actual site contention). If failed fix actual root cause. If PASS, update counts and sites_and_domains PARTIAL, then implement minimal 0063 tags/links per design, inspect module/ACL/locking and run exact SQL/concurrency CI. No tag-driven commercial/security/marketing rules or merge. No duplicate customer. Preserve existing gates; next unused 0063.


## TEST-085 / BUILD-030B — current
- [x] Verify exact 0062 CI; reuse prepared design commit; author 0063 and matched acceptance/concurrency tests.
- [ ] Confirm 0063 SHA reachable from main; verify exact CI both jobs. If failed fix actual cause only. If success update verified group CRM tags/merge to PARTIAL and runtime counts; next unused 0064. Independent favorites/queues or counterparty design; preserve owner-gated policies and no legacy/production access.


## TEST-086 / FIX-030B — current
- [x] Inspect exact failed 0063 run 45650762864, separate volatile state transitions from acceptance assertions and strengthen exact replay row checks.
- [ ] Verify correction branch ref and exact run, both jobs plus actual CRM create/attach contention and catalog count. If failed, diagnose precise new assertion. If PASS, promote exact branch changes to main preserving history (fast-forward or verified PR), verify resulting main SHA and required CI before next development. Last verified 0062. No 0064 until full success. All previous policy and production gates remain.


## TEST-087 / REVIEW-031B — current
- [x] Verify candidate 0063 exact full CI, count logs, prior upgrade and concurrency; record PR state and queue design.
- [ ] Verify PR #1 exact run 45652606889 and merge result; main must contain tested candidate tree/history. Verify main CI. Reconcile this documentation-only checkpoint into main (do not duplicate existing commits). If connector fails, report blocker and retain branch/commit. No 0064 DDL before main promotion. Then implement and test minimal queue identity/binding per docs/CRM_SERVICE_QUEUE_DESIGN_FA.md. All previous gates remain; no production/legacy access.


## TEST-088 / BUILD-031 — 2026-11-25
- TEST-088: PR #1 merged f583474cc72a42ece32c6ee0e039aaf5bda343dc, exact main run 45654059400 SUCCESS both jobs 139345880019/139345879319. Logs 63 contiguous pairs, 75 PASS suites, measured 90 base tables, actual tag contention and 24 COGS races. PR #2 documentation merged at 18ee2ad500b2713302440e8814dcde7dea7b947d with exact checkpoint tree. 23 verified/14 partial/20 not implemented; tag/merge partial. Main 0063 verified.
- BUILD-031: authored 0064 service_queues, nullable composite FK on existing support_tickets, 11-column legacy INSERT ACL preserved and protected queue_id, separate scoped nonlogin executor and shared audit. Exact state replay; ticket row lock for assignment, no routing or SLA/feedback policy. SQL test, real create/assign/opposing contention, separate committed pre-0064 upgrade job reusing 0013 fixture. No previous tests removed. Candidate expected 64 pairs, 77 foundation PASS suites, 91 base tables, separate upgrade proof; not yet verified. Preserve open ticket/customer-conversation consistency gap, privacy, queue access/closed-ticket lifecycle, temporal/financial/custody/domain gates. No production or legacy access.
- Next verify exact candidate SHA and all three CI jobs, inspect actual failure before any next migration. Main promotion only after PASS if candidate branch used. Next unused 0065 only after 0064 verification.

- [ ] Verify 0064 exact CI foundation, return-upgrade and queue-upgrade; actual lock waits and committed old row equivalence. Fix only actual errors; promote main and update verified counts. No 0065 until PASS.


## TEST-089 / REVIEW-032B — 2026-11-25
- TEST-089: exact candidate c9db3f637d447d579c17df2f230f762907fe79ac run 45659699146 SUCCESS, foundation 139365900387, queue-upgrade 139365900844, return-upgrade 139365901017 all SUCCESS. Foundation logs: 64 contiguous migration/test pairs, 77 PASS suites (64 SQL + 13 concurrency), runtime catalog 91 base tables, actual create and ticket lock waits, exact queue retry and serialized opposing assignments, exact audit, 24 COGS races. Committed pre-0064 ticket upgrade independently proves exact old row preservation, nullable queue/no backfill and old runtime writes. Actual return-history upgrade passed. Coverage 23 verified prototype/14 partial/20 not implemented unchanged; service queue/SLA/feedback group remains PARTIAL. Main still 0063 63/75/90, not promoted.
- PR #3 head c9db3f637d447d579c17df2f230f762907fe79ac, base 18ee2ad500b2713302440e8814dcde7dea7b947d, state open, draft true; exact PR run 45661080855 status in_progress, conclusion pending. PR comment REVIEW-032A 7169006681 already recorded design. Documentation-only checkpoint; do not alter tested PR head or allocate 0065 before main verification. No operational or legacy access.
- New docs/CATALOG_CATEGORY_HIERARCHY_DESIGN_FA.md expands prior design: existing table self FK, preserve tenant-wide uniqueness and original column ACL, tenant-wide advisory transaction lock before graph reads, recursive cycle/root check, exact replay and shared audit, actual committed upgrade and opposing-edge contention. No additional table, no duplicate product/category master, no attributes/barcodes, no business/security policy change. 64 migration texts previously scanned for literal category references (only 0004), not a full caller/semantic audit. Queue lifecycle/SLA/feedback, temporal/custody/financial/domain gates remain open.
- Next: verify PR #3 exact checks, mark ready if needed and merge preserving history, verify resulting main tree equals tested candidate and exact main CI. Reconcile this checkpoint once (do not duplicate existing design/implementation). Then allocate 0065. If failures, fix actual cause only; no bypass or weakening tests.

- [ ] Confirm exact PR #3 and main promotion/CI, reconcile documentation checkpoint, implement 0065 per category design. No new migration until prior gate.


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


## TEST-096 / BUILD-035 — current (supersedes 0067 handoff)
- [x] Verify all seven 0067 main CI jobs at exact merge SHA `69ca58b6d0862883aaad252c32bb0c733ef4b44a`; migrate REVIEW-035 dormant reorder design once into a new branch; author 0068 SQL, acceptance, real contention, committed upgrade, and workflow entries without duplicating warehouse/stock/purchase master.
- [ ] First: verify full exact run `45694773849` for branch `upc-0068-reorder-config`: all EIGHT jobs, check foundation 68 SQL acceptance, additional reorder concurrency and 24 COGS races; inspect catalog count 95 and upgrade full old-row equality. If FAILED, inspect exact logs and fix root cause only. Do not weaken assertions or overwrite old migrations.
- [ ] Once branch candidate fully PASS, open a PR into current main, check HEAD/ancestry and PR checks, merge normally without force, then verify all eight main CI jobs before allocating 0069. Update verified dictionary coverage only after main success. If no changes justified, next step must follow current 57-group deficit priorities.
- [ ] Keep reorder config dormant: NO automatic purchase, stock movement, suggestion engine, price/financial policy. All old temporal/return/domain/retention gates remain; no production/legacy access.


## Current first actions (supersedes prior pending 0068 steps)
- [x] Exact 0068 main CI and merged PR verified; 68/85/95, 8/8 SUCCESS.
- [ ] Verify documentation checkpoint branch/PR CI; merge only after both succeed; verify resulting main CI.
- [ ] Review shipping identity against all existing migrations and requirements; build 0069 only if no equivalent exists, with scoped ACL/RLS/audit, exact retry, concurrency and committed upgrade proof. Preserve all policy gates.


## TEST-097 / REVIEW-036 — verified main 0068 (2026-11-26)
- Exact main `4d30eab9c0fbb689b57618e5c600f78ee2798018` verified directly through GitHub branch, merged PR #9 and run 45696627212: completed SUCCESS, all eight jobs (foundation, cogs, queue/category/barcode/attribute/reorder/return-upgrade) SUCCESS. PR run 45695839631 completed SUCCESS at head 2bf4c59cabf584b8b194dd766ba183f58051c6da. No open PR at review time.
- Foundation job 139495607774: 68 unique contiguous migration/test pairs, 84 PASS markers, measured 95 base tables, actual reorder lock waits and serialized differing updates, exact audit, no stock/procurement effect. COGS job 139495607681: one PASS, 24 races; total 85 suites. Reorder upgrade 139495607634: exact committed pre-0068 stock/reservation/purchasing/permission/catalog facts preserved; no backfill or automatic procurement.
- Reconciled the 57 dictionary rows using prior 0060 comprehensive migration inventory, subsequent verified 0061–0068 deltas, exact current untruncated migration tree, and current CI evidence. Reorder group N→P; category/attributes/barcodes still P (label lifecycle missing). Counts: 23 verified prototype / 16 partial / 18 not implemented, not a completion percentage. This is incremental coverage reconciliation, not an independent exhaustive field/call-graph/ACL audit.
- Open temporal issues remain explicitly observed in main COGS logs: module expiry after function return before COMMIT; stock DEFAULT recorded_at preceding close despite later writer commit (no cutoff crossing proven). Partial/damaged/expired return, custody/refund/valuation, domain activation, CRM privacy, reorder basis/lead times/approval/automatic procurement remain gated. No operational or legacy change.
- Next priority selected for review: shipping/delivery group, dormant tenant shipping-method identity as a possible independent increment; inspect all existing migrations for equivalent relation and audit paths first. No rates, routing, dispatch, order state change, payment/tax effect or activation without policy. Allocate 0069 only after justified non-duplication review. Existing main is verified, checkpoint changes are documentation-only; promotion requires exact branch and PR CI before merge, then main CI. No 0069 SQL in this checkpoint.

# WORK_LOG — ثبت افزایشی و دائمی

هر عامل پس از **هر اقدام موفق یا ناموفق** یک رکورد append کند. قالب:
`Action ID | timestamp | phase | actor | objective | pre-check | files/DB touched | exact operation | result | tests/evidence | blockers | rollback | next exact action | commit SHA`.
**هیچ رکورد قدیمی حذف نشود**؛ ادعای DONE فقط با شواهد قابل بررسی.

## DOC-001 / 2026-11-24
تهیه طرح جامع فارسی، چارت معماری، بسته PDF/ZIP برای انتقال بین چت‌ها. فقط مستندسازی؛ هیچ تغییر تولیدی.

## DOC-002 / 2026-11-24
الزام ثبت هر اقدام در گزارش، به‌روزرسانی وضعیت و handoff بین چت‌ها به بسته افزوده شد. فقط مستندسازی.

## DOC-003 / 2026-11-24
تهیه بسته GitHub starter برای مخزن خصوصی؛ هنوز آن زمان مخزن ایجاد نشده بود. فقط فایل محلی، بدون تغییر DB.

## DOC-004 / 2026-11-24
مالک مخزن خصوصی `mohamadhajabbasi-dev/unified-platform-core` را ساخت. دسترسی push از GitHub تأیید شد. ورود متون مرجع در همین مرحله انجام می‌شود؛ بازرسی schema و مهاجرت هنوز آغاز نشده. وضعیت commit نهایی را در GitHub بررسی کنید و در اینجا با SHA ثبت کنید.

## الگوی ثبت قدم بعدی
### ACTION-ID / ISO timestamp
- Phase / هدف:
- وضعیت قبلی و کنترل تکراری‌نبودن:
- مسیرهای دقیق:
- عملیات انجام‌شده:
- نتیجه واقعی (DONE / FAILED / PARTIAL):
- شواهد / تست / SHA:
- خطر و rollback:
- موانع:
- گام دقیق بعدی:

## DOC-005 / 2026-11-24 — verified GitHub repository bootstrap
- Phase: 00 — documentation / GitHub repository bootstrap
- Pre-check: repository inspected; initial README only; private visibility and push permission verified.
- Paths created: AGENTS.md, .gitignore, docs/MASTER_PLAN_FA.md, docs/ARCHITECTURE_CHART.md, ai-handoff/DECISIONS.md, PROJECT_STATE.md, NEXT_ACTIONS.md, WORK_LOG.md, CHANGELOG.md, CONTINUITY_PROTOCOL_FA.md. README updated.
- Result: DONE — 11 text files initialized/updated remotely; GitHub read-back confirmed 9 essential files and their blob SHAs.
- Evidence: README commit `fb7fcbdc49ee52cd6a083f54f7a1805f324e2ac6`; protocol commit `b7f3ad2e490bea4215d8462be5ace7cce9edeb1a`; chart commit `0d7015f8f9ee83ca4e486893ae599b11cf626525`.
- Scope limitation: full original 20-file ZIP was **not** completely uploaded; binary PDF, PNG, HTML and several auxiliary texts **remain pending**. The new Markdown master is a concise maintained version, not byte-identical to prior PDF.
- Production/database changes: NONE. Read-only schema discovery: NOT_STARTED.
- Next exact action: verify GitHub state, decide whether to archive complete original ZIP/PDF in repository via authorized upload method, then request approved read-only inventory.

## INV-001 / 2026-11-24T16:43:00+03:30 — repository preflight
- Phase: 01 — read-only discovery preparation. Actor: ChatGPT. Scope: verify repository and owner approval, no production changes.
- Pre-check/operations: read AGENTS, README, MASTER_PLAN, ARCHITECTURE_CHART, .gitignore and all six ai-handoff files; list full recursive tree (11 text files, not truncated), review all 14 main commits, verify private repository and pull/push permissions. No prior schema evidence or migration code in this repo.
- Result: DONE for repository review; owner explicitly authorizes read-only inventory in current instruction. Original binary archive remains optional/pending, not required for inventory. Database engine names remain owner-reported.
- Evidence: verified starting main HEAD `503273567150bcf85893723085b145718956db37`, latest message 'docs: record verified remote initialized state and pending full archive'.
- Paths changed: ai-handoff/WORK_LOG.md, PROJECT_STATE.md, NEXT_ACTIONS.md only. Database/server touched: NONE. Tests: GitHub read-back and commit history only; no DB tests. Rollback: documentation-only revert if needed.
- Blocker: secure read-only access and actual source schema evidence not yet verified. Next: discover authorized source repositories / read-only connection; do not read secrets or customer rows; inventory metadata before proposing mapping. Checkpoint commit identified by Git history (cannot embed its own SHA).

## INV-002 / 2026-11-24T16:43:00+03:30 (session start) — source code inventory + access probe
- Phase: 01. Actor: ChatGPT. Pre-check: INV-001 main HEAD `f4ee8acd9183848331e883c8a4fec1096853ae77` verified; existing docs paths checked absent. Owner permits read-only only.
- Operations: list authorized GitHub repos; read complete recursive trees of ERPPlus master (2875 files, pinned `52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049`) and CommerceAI main (952 files, pinned `e7ae9b09f21c042e56407f593b99258fe280b20a`), inspect EF contexts, csproj, provider registrations, customer configuration, sync service, worker, controller and selected code ranges; check authorized Desktop Commander devices status (both Offline). No terminal or DB query executed; no production config or customer rows collected.
- Result: PARTIAL — source evidence of SQL Server provider for ERPPlus (contradicts initial owner-reported MySQL), Npgsql for Commerce; actual deployed engines not verified. Found overlapping model entities, store-scoped customer uniqueness vs tenant-level requirement, catalog/stock/customer/order sync directions. No count of duplicate records; no physical schema or migration executed.
- Paths: docs/CURRENT_INVENTORY.md, CURRENT_DATA_MAP.md, CURRENT_SYNC_MAP.md, OPEN_QUESTIONS.md; ai-handoff/WORK_LOG.md, PROJECT_STATE.md, NEXT_ACTIONS.md, CHANGELOG.md. Source repos and servers unmodified. No approved architecture decision changed.
- Tests/evidence: GitHub source read at pinned SHAs with linked lines in docs; device list read; no DB/CI/runtime tests. Risk: schema drift, store-vs-tenant identity, false dedupe, stale snapshots. Rollback: docs-only revert if required.
- Blocker: both devices offline and no actual DB metadata available. Next exact action: obtain authorized metadata-only access via connected device or sanitized export; verify engines and database identity before metadata queries, then complete inventories and mapping before any ERD/ADR approval. Checkpoint SHA in Git history.


## INV-003 / 2026-11-24 — GitHub-only continuation, no desktop dependency
- Phase: 01 — source audit, actor: ChatGPT.
- Pre-check: INV-002 and prior docs reviewed; duplicate analysis avoided; Commerce CustomerConfiguration and ERP AppDbContext re-read directly from GitHub.
- Operation: registered `docs/GITHUB_ONLY_DISCOVERY_PLAN.md` with confirmed code evidence, scope boundaries, and ordered GitHub-only source-review tasks.
- Outcome: DONE for planning and verified source inspection. Commit `05bff1977c2a8b61c18a1b8978fd80a8ef29fd90`.
- Production/database/source-app changes: NONE. Live database status remains UNVERIFIED. No Remote Desktop Commander needed for code review.
- Next: source-level customer identity/migration audit on GitHub, report field-level findings with refs and SHAs; continue logs on each action.

## DESIGN-001 / 2026-11-24 — architecture direction corrected per owner
- Precheck: read AGENTS, MASTER_PLAN, DECISIONS, PROJECT_STATE, NEXT_ACTIONS and recent records in GitHub; source audit had become falsely treated as source of target design.
- Owner clarification: new canonical schema must be designed from requirements, never copy or reproduce old ERPPlus/Commerce schemas.
- Operation: commit new `docs/TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA.md` (SHA `c5aee0b55f9efbb12af23855eb97507e31a32474`); update governance and continuity files to prioritize greenfield target design.
- Result: DOCUMENTATION ONLY. No physical database created; no app or production changes.
- Next: conceptual target ERD and table responsibility / relationship matrix, owner review before any implementation.

## DESIGN-002 / 2026-11-24 — proposed clean canonical target ERD
- Precheck: reviewed requirements-first brief and GitHub legacy evidence only as migration risk, not target shape.
- Operation: created `docs/TARGET_ERD_V0_FA.md` containing greenfield one-physical-PostgreSQL diagram, proposed core tenant-owned entities, access roles, module grants, platform dashboard, stock ledger, tenant-specific backup and acceptance scenarios.
- Evidence: GitHub create commit `2c8e51fca4db3e77ef1c4b770b642363fe9840c3`.
- Result: PROPOSAL WRITTEN, **NOT APPROVED**; no DDL, migrations, production or old-repo changes.
- Next action: owner review of target model (especially customer/product ownership, price and stock scope); then refine conceptual ERD, constraints and API boundaries. Legacy source mapping later, only for safe transfer.

## DESIGN-003 / 2026-11-24 — isolated greenfield development authorization
- Precheck: main `b413a25c6ccab350d85d04ee20d7d6a0781cdfea`, repository tree and 12 recent commits, mandatory architecture/handoff docs and README/master plan/decisions/changelog read. No executable SQL or test harness existed.
- Operation: record D-013 in AGENTS and DECISIONS, align README/master/target docs, append PROJECT_STATE/NEXT_ACTIONS/WORK_LOG/CHANGELOG.
- Result: DONE for scope update, no SQL executed. Owner authorizes normal isolated development and testing; not final approval of open technical choices nor production migration. No Desktop Commander, legacy repos, DB or server accessed/changed.
- Evidence: commit/read-back; no runtime tests at this documentation step. Rollback: documentation revert only. Next: first migration and tenant/customer tests.

## BUILD-001 / 2026-11-24 — foundation prototype and CI
- Precheck: mandatory docs re-read, DESIGN-003 HEAD `1b1205f8d66a12b0f72e6ab21b3058b69c5396f7` verified; no prior SQL files. Scope D-013.
- Operation: add db/migrations/0001_core_crm.sql, db/tests/0001_core_crm.sql, db/README.md, .github/workflows/greenfield-db.yml; append handoff and changelog. No other repo, live DB or server touched.
- Result: authored versioned prototype with canonical tenant customer, composite FK, verified identity unique constraint, trusted session login binding and RLS; synthetic acceptance suite. Runtime tests not yet observed; CI status pending verification. No real user or credential data.
- Provisional choices: PostgreSQL 16, dedicated trusted backend login mapping, verifier function, test-only bootstrap owner. No final architectural approval; distinct identity linking, least-privilege owner, IAM/modules, other domains, audit and concurrency tests pending. Rollback: disposable CI container removal; repo revert if necessary.
- Next: inspect GitHub Actions run for this commit and log actual results, then next domain. SHA in Git history.

## TEST-001 / 2026-11-24
- BUILD-001 commit verified. Actions run 45404619911, attempts 1 and 2, both concluded failure. Retry accepted; neither attempt exposed job steps or logs; log retrieval returned 404. SQL execution and cause unverified. No external database access or changes. Prior attempt to save this checkpoint was blocked; branch HEAD unchanged on read-back. Next: inspect run summary and resolve verified CI blocker before extending foundation.

## TEST-002 / 2026-11-24 — public runner retry
- Precheck: mandatory documents, tree, current main and visibility verified. Owner made repository public; no visibility change performed by agent. Retried run 45404619911 after changed visibility. Attempt 3 job 138489581659 reached in_progress; setup succeeded, container initialization started. SQL result pending at this checkpoint. Only handoff files changed; no production access. Next: verify final run and logs, then continue only on PASS.

## TEST-003 / 2026-11-24 — foundation PASS
- Run 45404619911 attempt 3, job 138489581659: completed success. Checkout SHA 605e42f116bf5cf4adf99cdd218283289b712ae2; PostgreSQL 16.16; migration 0001 committed, test 0001 rolled back synthetic fixtures and printed PASS foundation: identity reuse, cross-tenant isolation, verified uniqueness, FK, privilege, spoofing, fail-closed and revocation. Read job logs and step conclusions; container removed. Warnings: trust authentication confined to isolated CI; checkout Node 20 deprecation. Neither production nor legacy touched. Next: harden function ownership and implement IAM/module approval in incremental migration, rerun regression.

## BUILD-002 / 2026-11-24 — IAM and module decision prototype
- Precheck: TEST-003 main `d190fcf11e3f3e04609bbad51472b0239d511c4c`; required docs reviewed; foundation logs PASS. Created db/migrations/0002_iam_modules.sql and db/tests/0002_iam_modules.sql; updated db/README and handoff/changelog. No legacy or production interaction.
- Implementation: seven new normalized tables for roles/permission registry/membership grants, independent platform staff, modules and append-only tenant module decisions. Non-login least-privilege function owners replace bootstrap superuser on foundation functions. Permission and module checks default deny; approval checks active superadmin; latest decision/expiry and actor history. No duplicate customer/product masters or module enable flag.
- Tests authored: tenant-scoped role grants, cross-tenant FK, denial of escalation/staff/tenant approval, grant isolation and expiry, revocation, history and non-superuser owner assertions. Runtime results pending new CI. Provisional design: grant history doubles as approval record; no delegated write API, CRM permission integration, generalized audit, request workflow or concurrency tests yet. Rollback: test container disposal; revert code only if needed. Next: inspect run and fix evidenced issues.

## TEST-004 / 2026-11-24 — IAM regression PASS
- Run 45407145508 job 138490807758 completed success, exact head 8921f7e7b90fa9b778699115c8767444aa546f5e. Both migrations 0001 and 0002 applied; both tests executed and printed PASS foundation and PASS IAM. Job logs read and verified: function owners, tenant-scoped roles, denied escalation, platform approvals, expiry and actor history. No production access/change. Next: enforce CRM authorization by permission and module grant, add denied-operation tests; catalog after enforcement.

## BUILD-003 / 2026-11-24 — CRM access gates and identity linkage
- Precheck: TEST-004 HEAD 897ecdd852c7799ab6147c831d9cc8492282991d; mandatory docs and existing migrations/tests reviewed. No duplicate master tables.
- Changes: migration 0003, regression fixtures 0001/0002, test 0003, concurrency shell test, existing CI workflow, db README and handoff. Restrictive RLS on CRM and resolver write gate; verified link with conflict rejection and shared advisory lock; two-session concurrency test. No legacy or production access. SQL/CI results pending. Provisional choices: CRM module required for CRM access, separate read/write permissions and trusted verifier; no automatic merge. Next: inspect CI logs and fix any failure.

## FIX-001 / 2026-11-24
- Run 45407722953 job 138492831903: all three migrations applied; foundation test failed with syntax error at DO $ (one missing dollar delimiter in modified test fixture). Remaining tests skipped. Verified exact log and file; corrected delimiter to DO $$ in db/tests/0001_core_crm.sql only. No production or legacy changes. Next: rerun full CI and inspect results. Regression status pending.

## TEST-005 / 2026-11-24 — CRM enforcement and concurrency PASS
- Run 45407886388 job 138493418952 completed success at SHA 0fc37d44cb9b9b7a99f0d83b2ca61a6a95438464. Verified logs: migrations 0001–0003 applied, PASS foundation, IAM, CRM authorization and concurrency. Two concurrent sessions contended on advisory lock and returned one customer ID; one customer and one identifier remained in synthetic fixture. Prior test syntax failure corrected in FIX-001. All container steps successful; no production or legacy interaction. Next: catalog and price tables with tenant-aware FK, SKU uniqueness, price non-overlap and permission/module tests.

## BUILD-004 / 2026-11-24 — canonical catalog and prices
- Precheck: TEST-005 main 9d1b1a12a40cd87b60c27139bdee8f0880237b19; required docs, current tree and prior successful tests verified; migration 0004 absent.
- Changes: db/migrations/0004_catalog_pricing.sql, db/tests/0004_catalog_pricing.sql, db/README.md, handoff and changelog. Six new normalized tables; tenant-aware foreign keys, case-insensitive tenant SKU, category relation, price-list currency, temporal price exclusion, RLS/module/role checks and protected price amount. Existing workflow picks up new SQL automatically. No legacy or production access. Test results pending CI. Provisional choices: tenant-owned catalog, flat categories, currency-specific price list, temporal price periods [start,end), direct backend grants; media and hierarchy deferred, historical period correction and financial currency policy unresolved. Next: verify CI and then inventory ledger/reservations.

## TEST-006 / 2026-11-24 — catalog and full regression PASS
- Run 45408223573 job 138494611409 completed success at SHA af18194ee17b2765f31288ca4e122cd7d886584c. Logs confirm migrations 0001–0004 applied and PASS foundation, IAM, CRM authorization, catalog and concurrency. Verified catalog tenant SKU, composite FKs, RLS, temporal price non-overlap and boundary, historical amount protection and permission revocation. Test container removed. 20 tables, 4 migrations, 5 test suites. No production/legacy interaction. Next: inventory warehouses, stock ledger, reservations and derived stock balances, negative and concurrent tests. Catalog hierarchy/media and financial currency policy still provisional.

## BUILD-005 / 2026-11-24 — stock ledger and reservations
- Precheck: TEST-006 main 4647e7e08504a3aed588457190346718a205aa30; required docs, catalog SQL and workflow reviewed; inventory schema absent.
- Changes: db/migrations/0005_inventory.sql, db/tests/0005_inventory.sql, db/tests/concurrency/inventory.sh, CI workflow, db README and handoff. Three normalized tables and derived balance view, tenant-aware FK, permission/module enforcement, non-login executor, immutable runtime ledger, idempotent adjustments/reservations/consumption, expiration/release, shared pair lock and READ COMMITTED constraint. Two-session oversell test authored. No legacy or production access. CI pending. Whole units and full reservation consumption provisional; transfers/valuation/lot/order association and partial fulfillment pending. Next: verify CI, fix observed errors, then order/payment integration.

## TEST-007 / 2026-11-24 — inventory and full regression PASS
- Run 45408923495, job 138497113024, tested commit a3f27494ad6956b063d09cfb1ecf192835186d5f: completed success. Verified logs: migrations 0001–0005 applied, PASS foundation, IAM, CRM authorization, catalog, inventory, identity concurrency, inventory concurrency. Observed competing lock, exactly one reservation and no oversell (10 units, competing reservations of 7, remaining available 3). Container cleanup successful. 23 prototype tables and one derived stock view; no legacy/production access or changes. Next: sales order/payment integration with canonical references, snapshot prices, atomic reservation and idempotency. Provisional inventory limits recorded in db/README.

## BUILD-006 / 2026-11-24 — sales checkout and verified capture
- Precheck: TEST-007 main c7f0bc588c88b35316590989961006d654dae230; required docs, catalog/CRM/inventory migrations and existing inventory tests reviewed; sales schema absent.
- Changes: db/migrations/0006_sales.sql, db/tests/0006_sales.sql, db/README and handoff/changelog. Three new normalized tables, derived totals view, exact tenant FK and immutable snapshots, transactional checkout and reservation, duplicate checkout/capture rejection, separate trusted payment recorder, cancellation/fulfillment, restricted order reservation namespace, permission/module gates. Synthetic negative/lifecycle tests authored. No legacy or production access or actual gateway calls. CI pending. Provisional: physical-only single warehouse/list/currency, one full capture, no zero-total checkout or tax/shipping/refunds/partial/late recovery; external verification and concurrent sales tests pending. Next verify CI, fix observed issues, then concurrent sales and returns/finance.

## TEST-008 / 2026-11-24 — sales and full regression PASS
- Run 45411022860, job 138504507103, tested SHA 85303d2f3ab108435ac0a63c45839c4a4225f568 completed success. Logs verify migrations 0001–0006 and eight test suites (foundation, IAM, CRM, catalog, inventory, sales, identity concurrency, inventory concurrency). Sales tests cover atomic rollback, stale price rejection, canonical checkout retry, cross-tenant customer rejection, payment amount/currency/idempotency, trusted role restriction, order reservation ownership, cancellation/fulfillment and historical price snapshots. No real gateway access or production/legacy changes. Next: concurrent checkout/capture tests and refund/late-capture reconciliation model; no external charge or deployment.

## BUILD-007 / 2026-11-24 — sales concurrency, returns and refunds
- Precheck TEST-008 2359298b0f2257a6c3a414a1ff94fda838d70550; required docs and existing sales SQL/test/workflow reviewed. Added 0007 migration/test, sales concurrency script, CI step and handoff. Two event tables; full inspected return uses existing stock ledger, verified full refund uses original payment, late capture goes to review, no direct refund transaction or external gateway. Provisional full-only scope; extra captures, partials, damaged returns, durable external reconciliation and accounting still open. CI pending. No legacy or production access. Next verify CI then finance journal.

## FIX-002 / 2026-11-24 — sales concurrency fixture isolation
- Run 45411682401 job 138506869813: seven migrations and nine suites passed (including returns and both previous concurrency suites); new sales concurrency setup failed with duplicate role_grants_pkey before contention. Existing inventory concurrency leaves synthetic fixtures in disposable container, so shared role_key selected earlier roles as well. Changed sales fixture role keys to distinct sales-race-editor/reader. No migration or production change. Full rerun pending.

## TEST-009 / 2026-11-24 — returns and sales concurrency PASS
- Run 45411865940 job 138507510205 completed success, tested SHA b2fa7580ddf353fb21f14f2d32d629379c8e8938. Logs confirm 0001–0007 applied and ten suites PASS including full returns/refunds, late capture review, actual competing checkout/capture locks, exactly one order/hold/payment. FIX-002 isolated synthetic role keys after first test setup failure. No production/legacy or real gateway operations. 28 prototype tables. Next tenant finance journal with verified capture/refund linkage, balanced immutable postings and tenant isolation.

## BUILD-008 / 2026-11-24 — tenant finance foundation
- Precheck TEST-009 e3f338cb7721b6e7bb43bfe04afbfdba467b1b66; required docs, current tree, returns/refunds and test fixtures reviewed. No finance schema existed.
- Changes: db/migrations/0008_finance.sql, db/tests/0008_finance.sql, db/README, handoff/changelog. Three normalized tables and derived trial balance view; tenant/currency composite FK, signed balanced postings, deferred DB constraints, immutable posted history, unique capture/refund links and exact reversal, role/module gates and isolated checker. Manual/capture/refund test suite authored. CI pending. No production, legacy, actual payment or platform billing changes. Provisional customer advance/clearing treatment, no revenue recognition or period/tax/FX/valuation/settlement/invoices. Next verify CI and then extend finance/other domains.

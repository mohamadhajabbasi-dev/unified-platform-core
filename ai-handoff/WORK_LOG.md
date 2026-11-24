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

## TEST-010 / 2026-11-24 — finance and full regression PASS
- Run 45412335881 job 138509182694 completed success at SHA 0300fd92b31767be1a6d92e84ed115c3de406898. Read logs: migrations 0001–0008 applied; eleven test suites PASS including finance deferred constraints, immutable balanced postings, verified capture/refund exact reversal, source idempotency, currency/tenant isolation, and all three actual concurrency suites. Container cleanup successful. 31 prototype tables and 3 derived views. No production/legacy or actual money operation. Accounting model provisional: clearing/customer advances, not automatic revenue recognition; fiscal period/tax/FX/valuation, settlement, automatic posting and platform billing pending. Next: extend tenant accounting lifecycle, separate platform subscription billing, then remaining domains.

## BUILD-009 / 2026-11-24 — fiscal periods and recognition
- Precheck TEST-010 d06a0131b6ed848c5d69a10260695cce10d4f01b; required docs, finance migration and tests reviewed. Initial local orchestration syntax error before any GitHub write; corrected approach, reused existing writer. Added migration/test 0009, updated 0008 fixture, README and handoff. One fiscal period table, non-overlap, UTC posting gate, close serialization, explicit fulfillment recognition and refund reversal. No year-end closing entries, tax/COGS or actual money. CI pending. No legacy/production access. Next verify CI then independent billing.

## TEST-011 / 2026-11-24 — fiscal lifecycle and full regression PASS
- Run 45413678605, job 138513980630, tested SHA 4cc134d8f2758d3caa121cc16b3b47d6b35a808c, completed success. Logs confirm 9 migrations and 12 suites PASS, including period gate, non-overlap, recognition after fulfillment, full refund reversal, closed-period rejection, tenant isolation and prior concurrency suites. 32 prototype tables. No operational changes. Next: separate platform subscription billing. Period UTC and recognition model provisional; annual closing entries, accounting policy, tax/COGS and historical upgrade path pending.

## BUILD-010 / 2026-11-24 — separate platform billing
- Precheck TEST-011 b1fdb0b8c43c5e79e8ba75377c4233cb6eba7fff; mandatory docs, current tree and IAM model reviewed. Added migration/test 0010, db README and handoff. Three normalized platform billing tables, derived status, nonoverlapping priced terms, invoice and verified receipt idempotency, private billing executor, active superadmin checks and separate recorder, own-tenant read-only access. No effects on tenant sales/finance or module approvals. CI pending. Provisional full-payment one-term policy, no refund/proration/tax, delegated staff, real gateway or platform accounting. No legacy/production access. Next verify CI then remaining CRM/catalog/content/ops.


## REQ-015 / 2026-11-24 — tenant legal profiles, user settings and Commerce traffic attribution
- Phase: 03 GREENFIELD / requirements and schema-design extension.
- Input: owner's request for visitor/source-of-customer records per Commerce-enabled tenant; tenant full identity, corporate/person, partners, authorized representatives, org/user settings.
- Pre-check: main HEAD `4cc134d8f2758d3caa121cc16b3b47d6b35a808c` (BUILD-009); inspected AGENTS, PROJECT_STATE, NEXT_ACTIONS, TARGET ERD, DB README and migrations 0001/0002. Already existing canonical `core.tenants`, `core.users`, `iam.memberships`, `crm.customers`; no new master duplicates.
- Actions:
  - Created `docs/TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA.md` (commit `551520621e108a19948d072a08586f4821286a41`).
  - Extended `docs/TARGET_ERD_V0_FA.md` (commit `73eb1d6645c8390fb79c738b9d0a3a1ac1fcc831`).
  - Extended `docs/MASTER_PLAN_FA.md` (commit `66ecbb564bc59bf73632069b1593888732e2d8b4`).
  - Extended `AGENTS.md` (commit `155a1314a0bab6a2e5398038b553fca2af5528bc`).
  - Added decision D-014 to `ai-handoff/DECISIONS.md` (commit `8811e95733531508d063ee66cf44685d61913ea1`).
- Findings: Existing PostgreSQL prototype migration set 0001..0009 covers foundational domains but not verified legal/partner/visitor attribution features. TEST-010 PASS (0001..0008; 31 prototype tables, 11 suites); 0009 CI result unverified in current check (no GitHub check statuses exposed by connector).
- Repository visibility **PUBLIC**, unlike stale original header claiming PRIVATE. Only synthetic documentation committed, no personal data.
- Result: REQUIREMENTS/DESIGN ADDED; **NO SQL implementation for new requested features yet**. No legacy, server or production changes. No Desktop Commander.
- Next: verify 0009 CI; add organization legal/member settings as non-duplicating normalized migration/tests, then Commerce entitlement gating and visitor/customer-source migration/tests; update handoff after each action.

## TEST-012 / 2026-11-24 — billing and full regression PASS
- Run 45414085343 job 138515432286 completed success at tested SHA 3b6e7b6d775174272d3f49aee6debc534bf47def. Logs confirm 10 migrations, 13 suites PASS (including platform term non-overlap, invoice/receipt idempotency, isolation, admin revocation, no tenant finance or entitlement effects, and 3 concurrency suites). Container cleanup successful. 35 prototype tables, 4 derived views. TEST-011 also verified 0009 run 45413678605. Later REQ-015 documentation updates preserved; comparison confirms no DB/workflow changes since tested SHA. First checkpoint attempt stopped on changed HEAD; second commit object 1921deb5dc2ae00eda7635df74414474ba130455 was not attached to main due to concurrent documentation changes/API error. Re-read latest head d0154b356526488a6984c962380e743bd4b814c1 and append this merged checkpoint without overwriting prior work. No legacy/production or real gateway access. Next legal dossier and scoped settings, explicit Commerce purchase entitlement plus approved module, visitor and acquisition tracking.

## BUILD-011 / 2026-11-24 — tenant dossier and scoped preferences
- Precheck TEST-012 9cb2cdc636e851ddd8dc9a56cfa00a1325daa7ba; D-014, REQ-015, required docs, tree and IAM schema reviewed. Added migration/test 0011 and handoff. Five dependent tables plus shared ops audit metadata table; no new tenant/user/customer master. Tenant legal permission separate from settings/personnel, typed timezone and self preferences, membership FKs, stakeholder dates and audit trigger. CI pending. Provisional identity vault references, no real legal data, verification/documents, cross-party total/cycle checks and platform audited read still pending. No legacy/production access. Next verify CI then purchased Commerce entitlement.

## TEST-013 / 2026-11-24 — dossier and full regression PASS
- Run 45415077783 job 138518959088 completed success at SHA e35e34bca013180c8a6c73f94d0b544ade98c5aa. Logs verify 11 migrations, 14 suites PASS: legal scope, stakeholder relationships, typed settings, self preferences, tenant separation, audit metadata and revocation, plus all three existing concurrency suites. Container cleanup successful. 41 prototype tables and 4 derived views. No operational access or changes. Legal vault, verification, document metadata, ownership aggregate validation, manager cycles and platform audited reads remain pending. Next explicit purchased Commerce entitlement, then privacy-aware analytics and attribution.

## BUILD-012 / 2026-11-24 — explicit Commerce entitlement
- Precheck TEST-013 d646782f516bf0f808d676205405b32b70d72aeb; required docs, D-014 and billing/IAM reviewed. Added 0012 migration and test, one subscription-module relation, pre-invoice scope lock, derived paid entitlement and separate approval check. Negative tests unpaid/generic-paid/unapproved/expired/cross-tenant. CI pending; no real data, legacy or production access. Provisional paid full term UTC; chargebacks/refunds and per-module pricing pending. Next verify then traffic/attribution.

## TEST-014 / 2026-11-24 — purchased Commerce entitlement PASS
- Run 45415742246 job 138521322391 completed success at SHA 74a0ae3dda33002da17fb4dd91139bd54f70e590. Logs verify 12 migrations and 15 suites PASS: explicit purchased scope, paid term, independent approval, expiry and isolation; all previous acceptance and concurrency suites passed. 42 prototype tables and 4 derived views. No operational access. Next privacy-aware visitor sessions/events and verified acquisition; platform chargeback/refund/pricing policy remains provisional.

## BUILD-013 / 2026-11-24 — consented visitor analytics
- Precheck TEST-014 46fc32b8379c7086da58372e82af1971133d18ae; required docs, tree, entitlement and test fixtures reviewed. Added 0013 migration/test and handoff. Two scoped tables, source aggregate view, paid and approved collection gate, trusted collector, consent/bot gate, idempotency, withdrawal, bounded retention purge, negative tests. CI pending. 24h/30d and bounded source codes provisional; actual consent verification, sanitization, bot classifier, scheduler, partition/load and acquisition/order attribution pending. No real visitor data or operational access. Next verify CI.


## REQ-016 / 2026-11-24 — application visitors, downloads and multi-price
- Phase: 03 isolated new PostgreSQL / greenfield requirements-extension. Actor: ChatGPT.
- Owner request: track app visitors, app-store downloads, app engagement and all app-related metrics per tenant; ensure multiple price types per product.
- Pre-check: read latest PROJECT_STATE/NEXT_ACTIONS/AGENTS, `db/README.md`, SQL `0004_catalog_pricing.sql`, `0011_tenant_dossier.sql`, `0012_commerce_entitlement.sql` and previous web/tenant analytics design. Existing price_lists+price_entries+price_at are **already implemented**, so no duplicate pricing master was proposed. No existing app download/session implementation verified. Prior TEST-013: 41 tables / 11 migrations / 14 suites PASS; BUILD-012: 42 if applied, runtime verification pending.
- Changes committed:
  - `docs/APP_ANALYTICS_MULTI_PRICE_FA.md`: full app distribution, first-open, sessions, conversion, crash, UTM, privacy, non-duplicating analytics and pricing rules. Commit `475337172903c4efa55d123bbc978ef136734c5c`.
  - `AGENTS.md`: enforced D-015 and no duplicate product price/app visit tables. Commit `564b8a9faeccb33a1b973606a60dfb5b1c853b32`.
  - `docs/MASTER_PLAN_FA.md`: scoped app analytics/multi-price. Commit `419c48f00fcbc2d2b0a5e0cb51fe947c1d0b7bcd`.
  - `docs/TARGET_ERD_V0_FA.md`: integrated canonical multi-price and unified analytics. Commit `d8b01ccfbeb33bca814867c7642b9b6f0aa9730b`.
  - `docs/TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA.md`: superseded proposed web-only session master by unified cross-channel analytics. Commit `07ae5afad1811bb8349186b2e2e1cb9c46acfafa`.
  - `ai-handoff/DECISIONS.md`: D-015. Commit `79044e7a77ecc39d6e7537ee19c9667e0f8e2522`.
- Status: REQUIREMENTS + TARGET DESIGN RECORDED, **NOT APP ANALYTICS SQL IMPLEMENTED**, **NOT MULTI-PRICE RESOLUTION IMPLEMENTED**. Only pre-existing multi-list temporal price prototype exists.
- Verification: re-read GitHub source files and recorded commit SHAs; no SQL/runtime tests initiated in this action; 0012 CI status not yet independently verified.
- Repository public; only synthetic docs, no real customer/install/tenant/partner records, PII or secrets committed. ERPPlus/CommerceAI, their databases, production server and local devices: UNTOUCHED.
- Next exact action: verify BUILD-012 CI then develop one shared analytics sessions/events source with tenant app distributions and verified acquisition, plus separate incremental pricing resolver/quantity rules with synthetic RLS + checkout tests. Preserve per-action checkpoints.

## TEST-015 / 2026-11-24 — web analytics regression PASS
- Run 45416207835 job 138522973195, tested 9afb677dcfb50ea16262fe750ab8e80a254c0bba, completed success; logs verify all 13 migrations and 16 suites PASS. 44 prototype tables, 5 views. No production or real traffic. Concurrent documentation D-015/REQ-016 preserved. Initial checkpoint stopped on changed HEAD; second commit c532e0d79d8a86d46a4014ec1ed5821aa173d83b not attached due to API error/concurrent update. Latest d1e6b1a5bf73dca718ccc539504ba080a7e385d0 compared: documentation only, no DB/workflow changes. REQ-016 assumption web tables absent is stale: 0013 exists and passed. Next generalize existing tables to shared analytics.sessions/events, no duplicate app master; separate app paid entitlement and approval; registry, releases, installations and official distribution metrics, then verified attribution and existing price list selection rules. Provisional 24h/30d retention, collector/consent verification, scheduler, privacy/load review pending.

## BUILD-014 / 2026-11-24 — shared analytics and app first open
- Precheck TEST-015 bf7375a828ce615958928709fd34a4e7fddaf21d; mandatory docs, D-015, pricing/entitlement and 0013 reviewed. Move existing session/event tables into analytics, reuse writer and channel-specific APIs; add app registry, release and installation (3 tables), two derived views. Independent purchased app module and approval, consent/retention, release checks, withdrawal and tenant isolation. Update 0013 tests for relocated tables; add 0014 test. CI pending. Provisional tenant-owned apps, 30-day install retention, no real store reports/collector/shared app registry. No legacy or production access.

## TEST-016 / 2026-11-24 — shared web/app analytics PASS
- Run 45418858238 job 138532500500 completed success at SHA 15dacc4199930a943a897f00174969878c43d5cc. Logs verify all 14 migrations and 17 suites PASS, including relocated web session/event regression, independent app entitlement, registry and releases, first-open dedupe, separate session and active-installation metrics, cross-channel write/withdrawal denial, disabled release, revocation, tenant isolation and no duplicate master. Three existing concurrency suites passed. 47 prototype tables and 7 views; no real data, legacy or production access. App registry currently tenant-owned, installation retention 30 days provisional; shared cross-tenant app registry, official store aggregates, customer/order attribution, quality telemetry and production consent/scheduler/load review pending. Next official distribution reports then attribution and authorized price resolution.

## BUILD-015 / 2026-11-24 — app distribution reports
- Precheck TEST-016; latest head 08f8412f40e3ad521bc617274c850f78671e54b9 reviewed. Concurrent content/CRM and source evidence changes preserved; duplicate migration prefix 0013 noted, no existing migrations overwritten. Added 0015 migration/test, one append-only report table and latest revision view. Trusted import role, tenant/app/release FKs, provider/platform check, separate unknown/zero and metrics, source digest/ref, correction revision/idempotency and entitlement gates. CI pending. No official source connection or real data. Next verify full regression, reconcile concurrent changes, then verified acquisition/order attribution.

## TEST-017 / 2026-11-24 — distribution and integrated regression PASS
- Run 45420046746 job 138536799970 completed success at SHA af330fdd8dbc2b07175bea1e68ae1cb70a8e10f2. Logs verify 16 SQL migration files and 19 suites PASS (including concurrent content/CRM engagement addition, distribution revision/idempotency, unknown vs zero, app/release scope and permission/entitlement gates, all 3 prior concurrency suites). 53 prototype tables and 8 views at tested SHA (47 previous + 5 content/engagement + 1 distribution). Duplicate numeric prefix 0013 preserved, both files successfully executed by filename order; resolve unique migration identifiers before deployment. No real data, provider API, legacy or operational access. Actual marketplace provenance and ownership verification, scheduler, coverage mapping and shared app attribution remain pending. Next verified customer acquisition/order attribution, reusing existing consent evidence, then canonical price resolution.


## SOURCE-004 + BUILD-013/014/015 — 2026-11-24 / GitHub-only data coverage and independent SQL
- Phase: GREENFIELD_IMPLEMENTATION / SOURCE-COVERAGE / CI_UNVERIFIED.
- Owner instruction: inspect persisted data models in **ERPPlus and CommerceAI from GitHub read-only**, then construct clean normalized new PostgreSQL tables to cover business information without cloning legacy or modifying legacy systems.
- Preflight: reviewed newest master source `ERPPlus.Infrastructure/Data/AppDbContext.cs` at source commit `52d4a5be3cc11fa358aaf4b1ef4f7767e0d8c049` and `CommerceAI.Infrastructure/Persistence/ApplicationDbContext.cs` at `e7ae9b09f21c042e56407f593b99258fe280b20a`. Enumerated **182 ERPPlus + 52 CommerceAI EF DbSets**; these are C# declarations, not verified live physical DB tables. Read representative Product, Customer, Employee, SaleInvoice, Account, BankAccount, WorkflowDefinition, Article, Order, Payment, Promotion, ShippingMethod models. Other field-level details not yet exhaustively verified.
- Source-only outputs (GitHub commits):
  - `docs/LEGACY_DBSET_COVERAGE_2026-11-24.md` full 234-name register + initial logical grouping: `9011b02c7a70b77e809eecbaafcd5722d11f663d`, correction `fcff59c2892260164023df3009350ab5614dd9a5`.
  - `docs/SOURCE_FIELD_EVIDENCE_FA.md` verified representative field evidence: `f531c35b2b753f1cc6594b72f1b021d9f7593792`.
  - `docs/CANONICAL_TARGET_TABLE_DICTIONARY_V1_FA.md` normalized target of 57 canonical table groups: `08f8412f40e3ad521bc617274c850f78671e54b9`; status corrected `567b997db5c3206cfd2eb86c2fa3323c789a7894`.
- Actual **new-repository SQL authored** (all verified by GitHub read-back; NOT EXECUTED/CI-PASS VERIFIED):
  - `db/migrations/0013_content_crm_engagement.sql`: 5 distinct tenant-scoped content/CRM tables, commit `7b3b65aec6c74024de574e2b977532030e8dcbfd`; synthetic test `db/tests/0013_content_crm_engagement.sql`, `b88f57b47349159d1ee3c245d0f77fbdba7a2a04`.
  - `db/migrations/0014_catalog_details_price_tiers.sql`: 6 dependent brand/unit/media/warranty/review/volume price tables connected to current canonical catalog, commit `da5c9a3c50ae42a7ee7e8205995077cce7dbfa84`; synthetic test `db/tests/0014_catalog_details_price_tiers.sql`, `5c394ded9a1368f18e8cbe04e141b4a698d828bd`.
  - `db/migrations/0015_hr_payroll_commissions.sql`: 7 tenant HR, contracts, payroll, obligations and commission tables, commit `485bb0106d367844a84bacdfdde64be27e4d0d36`; synthetic test `db/tests/0015_hr_payroll_commissions.sql`, `45124b055f034c71f647f06be27a392a107dec6c`.
- Additional: db/README, README, AGENTS, D-016/DECISIONS, MASTER_PLAN, canonical matrix updated. Clarified that owner permits **read-only GitHub source inspection** of legacy repos; original databases/server/source remain **completely untouched**.
- Scope: baseline prior TEST-013 had **41 tables / 11 migrations / 14 suites PASS**; 0012 was authored (42 if applied) but 0012 CI outcome not independently checked here. New 0013–0015 add **18 definitions**, hence potentially **60** only if all 0012–0015 migrations apply. **No claim of CI pass**, no production database creation/deployment, no legacy data access or transfer, no actual secrets/PII in public repo.
- Static validation: all 3 new migrations and 3 tests fetched back from GitHub; 0013/0014/0015 all contain isolated database guard, tenant RLS policies and differentiated domain tables. **No PostgreSQL runtime execution or full SQL semantic parsing was available**.
- Known gaps: remaining data domains include purchasing/suppliers, stock lots/transfers/cost, fiscal tax invoices, shipping/fulfillment/promotion, banking/cheques/installments, app analytics, pricing audience resolver/checkout, AI credits/usage, marketplaces, workflow, outbound notifications, backup/restore, platform admin dashboard. Source DbSets do not capture all raw SQL/Redis/file/telemetry contents; deeper source pass required. Employee privacy/legal policy and CRM encrypted message handling need security review.
- First exact next action: verify GitHub Actions run for latest main containing 0013–0015, inspect logs and fix actual failures; then continue one verified domain at a time. Each action append-only log, update state/next and push; NEVER request Desktop Commander or touch old systems.

## TEST-018 / BUILD-016 — reconcile parallel baseline and attribution
- Verified run 45421101715 job 138540527723 at 8bb8e9d554f832afc77e1498f34690fcade741c4: 18 SQL files and 21 PASS suites including parallel catalog details/quantity tiers and HR/payroll. Compared later 84f2d979ded13272b6ef19f3c6767992fb5b4c97: docs only, D-016 preserved. 66 tables at tested baseline (53+6+7), no production. Precheck 84f2d979ded13272b6ef19f3c6767992fb5b4c97 tree and required docs. Added 0016 attribution migration/test; two dependent tables, two views, verified identifier/current consent, session/channel gates, deterministic retained first touch and order last touch, consent/session erasure and retention purge. CI pending. Nonweb limited to phone/in-person; external verification/consent, real checkout integration, messenger attribution, privacy scheduler remain pending. No source or operational system access. Existing price tier implementation preserved; authorization resolver/checkout remains open.


## PRICE-017 / 2026-11-24 — owner-defined original, discounted, colleague, wholesale prices
- Owner clarification: every tenant product/variant needs **four specific price categories**: original retail, discounted retail, colleague, wholesale.
- Precheck: reopened `db/migrations/0004_catalog_pricing.sql` and `db/migrations/0014_catalog_details_price_tiers.sql` and test 0014, current AGENTS, decisions and project handoff from GitHub. Current source has existing multi-list temporal `catalog.price_lists`/`catalog.price_entries` and authored `catalog.price_quantity_tiers`. No new price master needed. Legacy apps/databases/server not accessed.
- Executed GitHub docs changes: new `docs/FOUR_PRODUCT_PRICE_TYPES_FA.md` (commit `8b67ddb7ab83bdfb6b4dbfde2a80cfa1a74b28df`); AGENTS D-017 `4d2f01886822217c1c0c130421abb6b5b2c96eeb`; DECISIONS D-017 `b2183ceb5e4a5beb069dc7e5093c3e7f6d9d15d4`; MASTER_PLAN `c64c5ca501c78a1fe7a4ceac87d7ffc828145599`; TARGET_ERD `87722696fe8af35cc3a90c7350241525ee177361`; APP_ANALYTICS_MULTI_PRICE `8d7abd20b1fa7e9dbbfbc46cd02fb8522ff8c745`.
- Exact design: four price list keys `original/discounted/colleague/wholesale`; original required, discount optional & time-limited & <= original, colleague/wholesale private by verified eligibility, wholesale volume rules via existing dependent tiers; no new table. Retail display strike-through, checkout reprice on server and immutable order snapshot.
- Security gap identified: current `catalog.price_at` and SELECT RLS `catalog.read` permit requesting a supplied list; customer-specific eligibility and private wholesale/colleague read restrictions NOT implemented. Must fix before production.
- Result: REQUIREMENT/DESIGN COMMITTED; **NO SQL CREATED/CHANGED** in this action; four-role bootstrap, comparison constraints, eligibility resolver, channel checkout tests pending. Previous 0013–0015 migrations/tests still unverified runtime; no new migration until CI evidence.
- Next exact action: check latest CI 0012–0015, repair test failures, then implement four roles and secure resolver using current price tables plus synthetic cross-tenant/price-list/discount/checkout tests. All production and old databases untouched.

## TEST-019 / 2026-11-24 — acquisition and integrated regression PASS
- Run 45422397870 job 138545155769 completed success at 32eae6b47fa929fddb74739fa8d267d8097397fe. Verified logs: 19 migration files and 22 suites PASS, including attribution, catalog details/tiers, HR, distribution and three actual concurrency suites. 68 prototype tables (66 baseline + 2 attribution). Source first retained and order last touch, current consent/verified identity checks, session reassignment denial and erasure tested. No production or legacy access. Positive app attribution and full checkout integration not independently exercised; nonweb phone/in-person only, messaging proof, consent revocation when CRM disabled, privacy scheduler and durable anonymized aggregates pending. No permanent first touch after privacy erasure. Duplicate numeric prefixes 0013/0014/0015 pending coordination. First checkpoint commit 1c6955f474a41faa33c616bb994ca9e884757532 could not attach due to API error/concurrent docs. Re-read 53e0ef1d6d2e5e309d7ba3cb160a6fdd3664845b and confirmed docs only; preserve D-017/PRICE-017. Next implement precisely four named core prices original/discounted/colleague/wholesale in existing lists/entries, private-price authorization, discount consistency and server-side checkout. No separate price master; quantity tiers existing, resolver pending.

## BUILD-017 — four prices and checkout
- Precheck TEST-019 c0c1a23b6bff1e8f31bde9b20c4e890e623100e3; required docs, D-017 and pricing/checkout inspected. Added 0017 migration and synthetic test, one dependent decision history table, restricted raw prices, standard bootstrap and discount validity, trusted private quote, minimum/tiers, per-line checkout snapshots and current server revalidation. CI pending. Provisional wholesale > colleague > discount > original, same currency, legacy retail fallback only before original, trusted verifier external. No legacy/production access.

## TEST-020 / 2026-11-24 — four-price and full regression PASS
- Run 45423622801 job 138549506735 completed success at 52c47b901105ab264f72818e0fc2c97f4e7080ee. Verified logs: 20 migration files and 23 suites PASS including bootstrap, discount coverage, private RLS, trusted eligibility, wholesale quantity selection, checkout historical price/tier snapshot, revocation, and all three existing concurrency suites. 69 prototype tables, no production/legacy access. Provisional wholesale > colleague > discount > original, single currency and per-price minimum, legacy retail fallback only before original exists. Dedicated mixed-price cart, eligible web/app end-to-end, concurrent price writes/eligibility changes, expiry/currency boundary, and review of raw private prices via other APIs/roles still required. Trusted customer identity and service-channel proof must be implemented externally; no end-user API or production readiness. Mapped tenant trigger validation tested; bootstrap superuser fixtures outside tenant RLS do not establish cross-tenant invariant validation. Price write serialization lock held but dedicated race not yet exercised; review lock ordering with concurrent row updates before production. Next harden these tests and remove retail compatibility; then procurement and inventory extensions under D-016.

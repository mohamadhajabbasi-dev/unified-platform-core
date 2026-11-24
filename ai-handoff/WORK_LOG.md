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

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

## Checkpoint DESIGN-002 — 2026-11-24 (latest)
- Result: `docs/TARGET_ERD_V0_FA.md` created and committed (`2c8e51fca4db3e77ef1c4b770b642363fe9840c3`); it is a **new requirements-first proposed design**, not a copy of ERPPlus/Commerce tables.
- Status: **PROPOSED / AWAITING OWNER REVIEW**. DB and server unchanged; no physical tables created.
- Next: confirm target design with owner, refine table/PK/FK/RLS model; treat legacy mapping solely as migration concern.

## Checkpoint DESIGN-003 — 2026-11-24 (latest)
- Phase: 03 — GREENFIELD_ISOLATED_IMPLEMENTATION_AUTHORIZED.
- Starting main HEAD: `b413a25c6ccab350d85d04ee20d7d6a0781cdfea`; reviewed repository tree and 12 recent commits, all mandatory documents. No SQL, migrations or test harness existed.
- Owner directs GitHub-only greenfield implementation and synthetic-data tests; legacy DB/server/source untouched, no Desktop Commander. Final design approval and deployment/transfer remain gated.
- First exact next action: add versioned foundation migration and synthetic PostgreSQL acceptance tests for tenant isolation and customer verified identity. Provisional technical choices, not production approval.

## Checkpoint BUILD-001 — 2026-11-24 (latest)
- Phase: 03 — GREENFIELD_FOUNDATION_IMPLEMENTATION / CI_UNVERIFIED.
- Baseline DESIGN-003 `1b1205f8d66a12b0f72e6ab21b3058b69c5396f7`; first SQL migration, acceptance tests and GitHub-hosted isolated CI workflow authored. No existing SQL duplicated. No legacy access, server access, production changes or migration of old data.
- Prototype: tenant/user/membership, private trusted login scope, CRM customers/identifiers/addresses; RLS, composite FK, unique verified identity, transactional resolver. Details and limitations in db/README.md. Choices provisional, not final approved security architecture.
- Runtime result: NOT_YET_VERIFIED. Next exact action: query GitHub Actions runs for BUILD-001 commit, inspect job logs, record observed result and fix any failure; if workflow write/trigger denied, record blocker. Then add IAM/module grant and catalog/price migrations and tests incrementally.

## TEST-001 — latest checkpoint
- BUILD-001 committed at `605e42f116bf5cf4adf99cdd218283289b712ae2`. CI run 45404619911 attempts 1 and 2: failure, steps/logs unavailable. SQL tests not verified. No external system changes. First next action: diagnose GitHub Actions initialization and obtain actual test evidence.

## TEST-002 — latest checkpoint
- Public visibility confirmed; run 45404619911 attempt 3 now in progress, job 138489581659, setup successful, container initialization started. Tested code SHA 605e42f116bf5cf4adf99cdd218283289b712ae2. SQL results pending. No production changes.

## TEST-003 — latest checkpoint
- Phase 03: foundation runtime PASS on PostgreSQL 16.16. Run 45404619911 attempt 3, job 138489581659, tested code SHA 605e42f116bf5cf4adf99cdd218283289b712ae2. All migration and synthetic test steps succeeded; logs verified. No final security approval; identity linkage/concurrency, function ownership, IAM/modules and remaining domains pending. No production changes.

## BUILD-002 — latest checkpoint
- Phase 03: IAM/module prototype authored in migration 0002 and tests. Seven distinct new tables; function ownership hardened; no production changes. CI result pending. Existing CRM grants not yet IAM-gated; scope model provisional. Next: verify CI for BUILD-002, then integrate IAM/module enforcement, concurrent identity tests and catalog.

## TEST-004 — latest checkpoint
- Phase 03: 0001/0002 migration and regression tests PASS. Run 45407145508 job 138490807758, tested SHA 8921f7e7b90fa9b778699115c8767444aa546f5e. 14 prototype tables across core/iam/crm/platform. Module and IAM check functions tested; existing CRM access not yet wired to them. No production changes. Next: enforce permission+module gates on CRM and test.

## BUILD-003 — latest
- CRM permissions/module enforcement and verified identity linking authored; no new tables; concurrency and negative tests added. Runtime verification pending. Next: check CI then catalog/price; no production changes.

## FIX-001 — latest
- BUILD-003 migrations applied; CI failed on test fixture syntax (run 45407722953). Corrected delimiter; all acceptance and concurrency checks pending rerun. No production changes.

## TEST-005 — latest checkpoint
- 14 prototype tables; 3 migrations and 4 test suites PASS. Run 45407886388, job 138493418952, tested SHA 0fc37d44cb9b9b7a99f0d83b2ca61a6a95438464. CRM read/write permissions, active module, verified link conflict and simultaneous resolution tested. Trusted external identity verification, detailed audit and final auth architecture remain open. No production changes. Next catalog/pricing.

## BUILD-004 — latest
- Catalog and pricing migration 0004 authored: six tables, 20 total if applied; independent tenant master and temporal prices with role/module gating. Runtime verification pending. Media/hierarchy and full financial pricing rules remain open. No production changes.

## TEST-006 — latest checkpoint
- Phase 03: 20 tables across core, iam, crm, platform, catalog; 4 migrations and 5 test suites PASS. Run 45408223573 job 138494611409, verified tested SHA af18194ee17b2765f31288ca4e122cd7d886584c. Greenfield CI only; no operational database created or changed. Catalog hierarchy/media, price-list selection/rounding and final approval remain open. Next inventory stock ledger/reservations.

## BUILD-005 — latest
- Inventory migration 0005 authored: three tables and one derived view (23 prototype tables total if applied). Ledger/reservations, idempotency and pair-lock functions, synthetic and concurrent tests. CI pending. No production changes. Next verify regression and inventory concurrency, then sales.

## TEST-007 — latest checkpoint
- Phase 03: 23 prototype tables, 5 migrations and 7 test suites PASS, plus derived stock_balances view. Run 45408923495 job 138497113024, tested SHA a3f27494ad6956b063d09cfb1ecf192835186d5f. Real concurrent oversell test passed. Greenfield disposable CI only; no operational DB created or changed. Whole units/full consumption provisional; transfer/valuation/lot/serial/partial fulfillment and order linkage remain pending. Next: sales orders/payment core.

## BUILD-006 — latest
- Sales migration 0006 authored: three tables (26 total if applied) and derived order totals view. Checkout, snapshot, reservations, verified capture recording and cancel/fulfill lifecycle; test suite authored. CI pending. No production changes or real payments. Next verify CI.

## TEST-008 — latest checkpoint
- Phase 03: 26 prototype tables, 6 migrations, 8 test suites PASS and two derived views. Run 45411022860 job 138504507103, tested SHA 85303d2f3ab108435ac0a63c45839c4a4225f568. Sales physical checkout, verified capture recording and full fulfillment/cancellation tested. Concurrent sales-specific tests, refunds, late capture, taxes, discount, shipping, partial payments and digital/service lifecycle remain pending. No operational changes. Next concurrent sales tests.

## BUILD-007 — latest
- Returns/refunds migration 0007 and concurrent checkout/capture tests authored. 28 prototype tables if applied. CI pending; no actual funds or production access. Next verify CI and finance journal.

## FIX-002 — latest
- BUILD-007 migrations and nine suites passed; sales concurrency fixture setup failed on duplicate role grants. Isolated role keys; rerun pending. No production changes.

## TEST-009 — latest checkpoint
- 28 prototype tables, 7 migrations, 10 suites PASS, 2 derived views. Run 45411865940 job 138507510205, tested SHA b2fa7580ddf353fb21f14f2d32d629379c8e8938. Full-only returns/refunds and late full capture review; concurrency proven. No production changes. Partial/damaged returns, multiple capture and durable reconciliation inbox remain pending. Next: finance.

## BUILD-008 — latest
- Finance migration 0008 authored, 3 new tables (31 if applied) and derived trial balance view. Balanced immutable journal, manual and verified capture/refund postings. CI pending. No production or real money operations. Next verify finance CI.

## TEST-010 — latest checkpoint
- Phase 03: 31 prototype tables, 8 migrations, 11 test suites PASS and 3 derived views. Run 45412335881 job 138509182694, tested SHA 0300fd92b31767be1a6d92e84ed115c3de406898. Tenant double-entry accounting and verified capture/refund posting tested. No operational changes. Fiscal period, revenue recognition, automatic posting, tax/FX/settlement and separate platform subscription billing remain open. Next: accounting lifecycle and platform billing.

## BUILD-009 — latest
- 32 prototype tables if applied; fiscal periods and recognition authored; CI pending. No production changes. Next verify tests then independent platform billing.

## TEST-011 — latest checkpoint
- 32 tables, 9 migrations, 12 suites PASS and 3 derived views. Run 45413678605 job 138513980630, tested SHA 4cc134d8f2758d3caa121cc16b3b47d6b35a808c. Fiscal periods and recognition tested. No operational changes. Next platform subscription billing.

## BUILD-010 — latest
- Platform subscription billing authored: three tables, 35 total if applied, fourth derived view. CI pending. Independent of tenant sales/finance and entitlements; no production changes or money operations.


## Checkpoint REQ-015 — 2026-11-24 (latest; supersedes earlier progress/visibility notes)
- Phase: **03 — isolated greenfield PostgreSQL prototype**.
- GitHub visibility **PUBLIC** per live repository metadata; initial PRIVATE header is historical and now inaccurate. Never commit actual tenant/customer/legal/visitor data or secrets.
- Last **verified PASS**: TEST-010, migrations **0001–0008**, **31 provisional tables**, 11 test suites, synthetic PostgreSQL only (run 45412335881, SHA `0300fd92b31767be1a6d92e84ed115c3de406898`).
- **BUILD-009** at `4cc134d8f2758d3caa121cc16b3b47d6b35a808c` added migration 0009 (fiscal periods/revenue recognition), estimated **32 provisional tables if applied**, but 0009 runtime result **NOT_VERIFIED** in this check. Do not claim 0009 PASS.
- REQ-015: Added documented requirements for complete tenant legal/personal organization dossier, partners/representation/ownership, scoped settings, and Commerce-conditional visitors/source attribution with CRM customer reference. See `docs/TENANT_IDENTITY_VISITOR_ATTRIBUTION_FA.md` and D-014.
- These **new features are design/requirements only**; no migrations, tests, application endpoints or UI implemented for them yet.
- Source code of original ERPPlus/CommerceAI, old DBs and server: **UNTOUCHED**. Deployment: **NONE**.
- First next action: verify latest 0009 CI evidence and fix if needed, then implement targeted tenant-profile/settings and visitor attribution migrations in separate incremental steps with RLS and synthetic tests. Never duplicate Tenants, Users or Customers.

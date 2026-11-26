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

## TEST-012 — verified latest checkpoint (updates REQ-015 test status, preserves its requirements)
- 35 prototype tables, 10 migrations, 13 test suites PASS, 4 derived views. Run 45414085343 job 138515432286, tested SHA 3b6e7b6d775174272d3f49aee6debc534bf47def. Fiscal lifecycle run 45413678605 also verified PASS. Subsequent docs-only changes preserved. D-014/REQ-015 new features remain requirements only. Billing separate from tenant ledger and module approval; explicit Commerce entitlement not yet implemented. No operational changes. Next migration 0011: tenant legal dossier and scoped settings, then Commerce entitlement and analytics/attribution. Fiscal/billing policy and year-end close, tax, proration, refunds, platform ledger remain provisional/pending.

## BUILD-011 — latest
- Dossier/settings and shared audit metadata migration 0011 authored (41 tables if applied). CI pending. Legal verification/vault and full audit still open. No operational changes.

## TEST-013 — latest checkpoint
- 41 prototype tables, 11 migrations, 14 suites PASS and 4 derived views. Run 45415077783 job 138518959088, tested SHA e35e34bca013180c8a6c73f94d0b544ade98c5aa. Dossier/settings and audit metadata tested. No production changes. Next Commerce purchase entitlement, then visitors and attribution. Legal identity/vault and complete audit remain provisional.

## BUILD-012 — latest
- Explicit purchased module relation and Commerce eligibility authored, 42 tables if applied. CI pending. No operational changes. Next traffic and attribution after PASS.

## TEST-014 — latest checkpoint
- 42 prototype tables, 12 migrations, 15 suites PASS and 4 derived views. Run 45415742246 job 138521322391, tested SHA 74a0ae3dda33002da17fb4dd91139bd54f70e590. Paid Commerce entitlement and separate approval tested. No production changes. Next visitor sessions/events and verified acquisition.

## BUILD-013 — latest
- Visitor analytics migration and tests authored, 44 prototype tables and 5 derived views if applied. CI pending. No real collection or deployment. Customer acquisition/order linkage pending.


## Checkpoint REQ-016 — 2026-11-24 (latest; supersedes earlier feature-scope notes)
- Phase: **03 — greenfield database implementation + requirements**.
- Confirmed working baseline: **TEST-013**, migrations `0001..0011`, **41 provisional tables**, 14 test suites PASS, synthetic/isolated Postgres (run 45415077783).
- Newer **BUILD-012**: `db/migrations/0012_commerce_entitlement.sql`, one new `platform.subscription_modules` table (**42 if applied**); SQL/test authored; CI PASS **not verified** in this checkpoint.
- Multi-price **already partly implemented** by `catalog.price_lists`, `catalog.price_entries`, `catalog.price_at`, temporal constraints (0004). Automatic audience/channel/quantity/contract selection and final resolver **NOT implemented**.
- App visits/downloads/analytics **NOT implemented**; owner requested complete per-tenant app lifecycle reporting. New requirement/architecture file `docs/APP_ANALYTICS_MULTI_PRICE_FA.md` committed at `475337172903c4efa55d123bbc978ef136734c5c`; other docs and AGENTS updated under D-015. Proposed unified `analytics.sessions`/`analytics.events` (web, Android, iOS, desktop) prevents duplicate web-only and mobile-only analytics masters.
- Distinguish official marketplace downloads, first_opens, app installations, active users, in-app visits, and conversion; tenant/app entitlement & privacy apply.
- GitHub visibility **PUBLIC** confirmed; no real telemetry or PII committed. Source projects, old databases, server and deployments **UNTOUCHED**.
- First exact next action: verify BUILD-012 isolated CI; implement incremental tenant-safe shared analytics/app tracking with synthetic tests, then pricing rule resolver/tier selection without a second pricing master. Keep audit/updates after every action.

## TEST-015 — verified latest checkpoint (updates REQ-016 stale CI status)
- 44 prototype tables, 13 migrations, 16 suites PASS, 5 views. Run 45416207835 job 138522973195, tested SHA 9afb677dcfb50ea16262fe750ab8e80a254c0bba. TEST-014 Commerce also PASS. Subsequent docs-only D-015/REQ-016 preserved. Web tables exist; next migrate/generalize them to shared analytics.sessions/events, not duplicate tables. App telemetry and automatic price resolution not yet implemented. No operational changes.

## BUILD-014 — latest
- Shared analytics migration 0014 authored; 47 prototype tables if applied, 7 views. Existing web tables moved, not duplicated. Separate app eligibility and registry/releases/install first open. CI pending. No production changes.

## TEST-016 — latest checkpoint
- 47 prototype tables, 14 migrations, 17 suites PASS, 7 views. Run 45418858238 job 138532500500 tested SHA 15dacc4199930a943a897f00174969878c43d5cc. Single shared analytics.sessions/events and scoped app registry/releases/installation tested. No real SDK, distribution reports or production access. Next official download aggregates separate from first-open, then attribution and pricing. Tenant-owned apps and 30-day retention provisional.

## BUILD-015 — latest
- Distribution report migration 0015 authored, one table and one derived view. CI pending. Parallel content/CRM additions preserved; table and migration counts to be reconciled from current tree. Actual provider import integration not implemented. No operational changes.

## TEST-017 — latest verified distribution checkpoint
- Tested SHA af330fdd8dbc2b07175bea1e68ae1cb70a8e10f2, run 45420046746 job 138536799970: 16 migration files, 19 test suites PASS, 53 prototype tables and 8 views including parallel content/CRM addition. Duplicate prefix 0013 needs coordination before migration runner adoption. Distribution reports and CRM engagement tested; provider integration not implemented. No production changes. Next verified customer/order attribution, then authorized price resolver.


## Checkpoint SOURCE-004 / BUILD-013..015 — 2026-11-24 (LATEST)
- Phase: **03 — independent greenfield PostgreSQL source-coverage & SQL development**.
- Owner explicitly permits READ-ONLY GitHub source inspection of ERPPlus/CommerceAI for coverage, notwithstanding earlier D-013 source-read restriction. No permission to connect to/edit legacy DB/server/code or use Desktop Commander.
- Source evidence: **182 ERPPlus + 52 CommerceAI EF DbSets**; exact source inventory, representative field evidence and 57-group normalized target matrix are committed. These are NOT live table counts or proof of complete field-level parity.
- Original verified runtime baseline: **TEST-013** 41 tables / migrations 0001–0011 / 14 synthetic suites PASS. Migration 0012 authored but latest runtime status not independently checked in this turn.
- NEW: migration **0013** (5 content/CRM tables), **0014** (6 catalog/media/quantity tier tables), **0015** (7 HR/payroll/commission tables) and matching tests all committed & GitHub read-back verified. Total **18 new authored table definitions**, potential **60 if 0012–0015 apply**. **CI: UNVERIFIED for these new migrations; cannot claim PASS**.
- Existing canonical tenants, users, customer, product, orders, price entries and ledger reused. No mirror table for each legacy DbSet.
- Repo public; ONLY synthetic fixture data and source-derived schema descriptors. No actual customer/employee/partner records or credentials uploaded.
- Changes to ERPPlus, CommerceAI source, active databases, server, operational storefront: **NONE**. New production DB/deployment/data migration: **NONE**.
- Current gate: full synthetic regression in GitHub Actions with exact tested commit SHA, repair failures before extending more SQL; security review of consent/message encryption, user-authorized price list/employee data, and final architecture approval remain pending.
- Next: check Actions latest run; fix only proven errors. After pass, proceed with next uncovered domain from canonical dictionary, and log every action.

## TEST-018 / BUILD-016 — reconciled baseline
- Run 45421101715 job 138540527723 at 8bb8e9d554f832afc77e1498f34690fcade741c4: 18 migrations/21 suites PASS, 66 prototype tables. New 0016 attribution authored (68 if applied), CI pending. Preserve D-016 and parallel changes. No deployment. Existing tier table not duplicate; audience/checkout authorization pending.


## Checkpoint PRICE-017 — 2026-11-24 (LATEST)
- Owner has now specified **four core price categories** per tenant product/variant: `original` (اصلی), `discounted` (تخفیف‌خورده), `colleague` (همکار), `wholesale` (عمده). See `docs/FOUR_PRODUCT_PRICE_TYPES_FA.md`, D-017.
- Current SQL `0004` supports multiple price lists/validity per variant; `0014` adds a draft quantity-tier relation. **Four named standard lists are NOT bootstrapped/validated; price role/eligibility resolution, discount consistency and checkout authorization NOT implemented**.
- No duplicate price table or four mutable product price columns created.
- New doc/AGENTS/DECISIONS/MASTER_PLAN/ERD all committed on GitHub. Existing 0013–0015 authored migrations and synthetic tests still CI UNVERIFIED in this response; do not misstate success.
- Critical blocker before production: protect private colleague/wholesale prices from direct querying by readers with catalog.read; never trust client-supplied price_list_id.
- NEXT: verify latest GitHub Actions regression for 0012–0015; then create incremental secure four-role pricing rules and tests against existing price lists without touching ERPPlus/CommerceAI/production server.

## TEST-019 — latest verified checkpoint (supersedes PRICE-017 stale CI status, preserves D-017 requirements)
- 68 prototype tables, 19 migration files, 22 test suites PASS at 32eae6b47fa929fddb74739fa8d267d8097397fe, run 45422397870 job 138545155769. Attribution with current consent/privacy erasure tested; no operational changes. Parallel catalog/HR verified. Subsequent docs-only PRICE-017/D-017 preserved. Four price categories specified, not implemented; protect colleague/wholesale from ordinary catalog readers and never trust supplied list ID. Next authorized resolver and checkout using existing price lists/entries/tiers. Positive app attribution, real consent/checkout integration pending.

## BUILD-017 — latest
- Four price roles and checkout implementation authored, 69 prototype tables if applied. CI pending. No production changes. Verify exact runtime and correct failures before next domain.

## TEST-020 — latest verified checkpoint
- 69 prototype tables, 20 SQL migration files, 23 suites PASS at 52c47b901105ab264f72818e0fc2c97f4e7080ee, run 45423622801 job 138549506735. Four standard prices, scoped eligibility, checkout per-line snapshot and RLS tested. No production changes. Provisional priority and same currency; legacy retail path remains for old fixtures; customer/channel service authentication, mixed-price cart/paid-channel tests and concurrent pricing tests pending.

## BUILD-018 — latest
- Pricing hardening authored, no new tables; 69 prototype tables. 21 migration files if applied; new synthetic and concurrency suites pending CI. No production changes. Next verify and then procurement.

## TEST-021 — latest verified checkpoint
- 69 prototype tables, 21 migration files, 25 test suites PASS at 33ed911cf34b2944351ce7e4163d0f358bbc7d40, run 45424606919 job 138553037717. Original-only checkout, trusted web/app/offline channel capabilities, bootstrap validation, mixed cart, expiry and actual price/revoke concurrency tested. No new tables or operational changes. Production identity/service channel proof, load and upgrade review pending. Next supplier/purchasing/receipts using canonical stock ledger.

## BUILD-019 — latest
- Procurement foundation authored, 74 prototype tables if applied, 22 migration files. Full receipt and stock movement links; CI pending. No invoice/payable or finance posting yet. No operational changes.

## TEST-022 — latest verified checkpoint
- 74 prototype tables, 22 migration files, 27 suites PASS at 990d6df716acd4ee8a942019dab63a4019000932, run 45426509033 job 138559865461. Counterparty, purchase and full receipt integrated with canonical inventory ledger; actual duplicate receipt race passed. No production changes. Supplier invoices/payables/settlement and valuation not implemented. Next verified supplier invoice and finance integration; partial receiving/returns and legal party verification pending.

## BUILD-020 — latest
- Supplier finance authored; 76 prototype tables if applied, 23 migration files. Invoice and partial settlement linked to existing journal and fiscal periods; CI pending. No operational changes.

## TEST-023 — latest verified checkpoint
- 76 prototype tables, 23 migration files, 28 suites PASS at ffe6d0fd8dcbd07feceea6c6ef49a48efdc2ac8d, run 45427508836 job 138563413627. Supplier invoice and partial/full settlement with derived payable and existing journal/fiscal gate tested. No operational changes. Dedicated settlement race and closed-period settlement test pending, as are account mapping, COGS, actual bank verification and invoice variance/tax/returns. Next harden then warehouse transfers and valuation.

## BUILD-021 — latest
- 78 prototype tables if applied, 24 migration files; transfer and settlement hardening authored. CI pending. No operational changes.

## TEST-024 — latest verified checkpoint
- 78 prototype tables, 24 migration files, 30 suites PASS at 1f24f141ac1f1f70d9caa96c6db68866f46d5ba8, run 45431863822 job 138579086006. Atomic interwarehouse transfer and supplier settlement concurrency/closed-period guard verified. No operational changes. Dedicated transfer races, transit/approval, lot/serial/expiry, valuation, full bank mapping pending.

## BUILD-022 — latest
- 81 prototype tables if applied, 25 migration files; trace metadata and guarded ledger adjustments authored, transfer races added. CI pending. Tracked sales/procurement/transfer allocation not enabled. No deployment.

## FIX-003 — current
- First BUILD-022 CI failed in old inventory concurrency readiness check after trace lock added; SQL tests passed. Fixture corrected, full CI pending.

## TEST-025 — latest verified checkpoint
- 81 prototype tables, 25 migration files, 32 suites PASS at 9e62c03eaca9f202e486a3a3ccbddb9dd2e989b5, run 45433354373 job 138584395213. Trace foundation and seven concurrency suites verified after FIX-003. Tracked stock is blocked from unadapted workflows; no full tracked sale/purchase/transfer lifecycle yet. No production changes.

## BUILD-023 — latest
- 81 prototype tables, 26 migration files if applied; allocated receipt and transfer authored, no duplicate ledger. CI pending. Tracked reservation/sale/return not enabled.

## TEST-026 — latest verified checkpoint
- 81 prototype tables, 26 migration files, 33 suites PASS at 3f75d641754b5df16409d6f3056fd8d0765216b5, run 45434441176 job 138588298403. Existing receipt and transfer relations support explicit lot/serial allocations, no new table or stock master. Tracked sales/returns remain blocked. Dedicated serial race and full production lock/security review pending. No operational changes.

## BUILD-024 — latest
- 82 prototype tables if applied, 27 migration files. FEFO and tracked checkout/fulfillment/full return authored; CI pending. No production changes.

## FIX-004 — current
- First 0024 migration failed SQL syntax; corrected guard function delimiter. Full CI pending.

## FIX-005 — current
- 27 migrations applied in second run; SQL regression stopped at prior return alias conflict. Corrected alias, full CI pending.

## TEST-027 — latest verified checkpoint
- 82 prototype tables, 27 migration files, 34 suites PASS at 1174ad86892bff6d984eeb9fd91e8089a40dce01, run 45436355581 job 138595123350. FEFO reservations, tracked fulfillment and explicit full sellable return verified; two defects fixed in CI. Seven previous concurrency suites pass. Dedicated tracked serial race, total allocation limit alignment, partial/damaged/expired returns, external proof and production security/lock review pending. No operational changes.

## TEST-028 candidate — latest
- 82 tables, 27 migrations; last verified 34 suites at TEST-027. Added serial race suite, CI pending. No deployment.

## TEST-028 — latest verified checkpoint
- 82 prototype tables, 27 migration files, 35 suites PASS at 7da09a17941764823da56f43b14fa2a7c5ef3b24, run 45437056776 job 138597607794. Eight concurrency suites, including three competing tracked serial cases. No operational changes. Allocation cap alignment, valuation/COGS and remaining lifecycle limits pending.

## BUILD-025 — latest
- 82 tables unchanged, 28 migration files if applied; checkout allocation cap and receipt cost evidence view authored, CI pending. Valuation/COGS not yet implemented. No production changes.

## TEST-029 — latest verified checkpoint
- 82 tables, 28 migrations, 36 suites PASS at 981dc341f0542c9f167bb2127cb347eb4393d40d, run 45438333111 job 138602166135. Checkout total allocation cap and historical receipt cost evidence verified. Valuation/COGS design only; no deployment.


## BUILD-026A — valuation preview candidate
- 82 tables unchanged; 29 migration files if applied. Read-only, invoker-RLS FIFO/moving-average replay of ordinary purchase receipts and reservation consumption, no new tables or journal writes. Explicitly rejects tracked stock, adjustments, transfers and returns in the selected history; agreed uninvoiced receipts flagged provisional. Per warehouse/variant, four-decimal rounding, deterministic recorded_at/movement_id ordering are experimental. No persistent policy, immutable allocations, COGS journal, transfer/return or concurrency certification. CI pending; no operational access.


## TEST-030 — verified
- TEST-030: run 45439836678 job 138607567327 at 0fcc7b0f56b4c2c360254e23fdac494debc7de5b completed success; actual logs show 29 migrations, 37 PASS suites (29 SQL + eight concurrency), 82 tables unchanged. Restricted valuation preview verified.

## BUILD-026B — latest
- 83 tables if applied, 30 migration files. BUILD-026B: one new tenant-scoped finance.valuation_policies relation, immutable method/currency, enrollment of unused ordinary physical variants under existing trace lock, permission and RLS gates, configured preview wrapper and synthetic tests. Experimental preview policy only, no operational enforcement, immutable movement allocations, journal COGS, transfer/return, or production access. CI pending.


## TEST-031 — verified
- TEST-031: run 45440610535 job 138610366925 at e819c2a64215af4cfa45273704732ab7f86ddb7f succeeded; actual logs show 30 migrations and 38 suites PASS (30 SQL, eight concurrency). 83 prototype tables.

## BUILD-026C — latest
- 84 tables if applied, 31 migrations. BUILD-026C: refactored existing replay algorithm into one per-movement calculation source; one new append-only finance.movement_cost_facts relation with exact canonical movement and policy FKs, tenant RLS, explicit finance capture permission and existing variant lock. Requires matched invoices for all replayed receipts, rejects unknown/unsupported history, compares prior cost and sequence for exact retry. Does not post COGS or enforce costing at stock mutation; per-receipt FIFO allocation links, transfer/returns, mixed currency and concurrent capture tests remain pending. Policy/rounding and explicit post-invoice capture are provisional; CI pending. No operational access.


## TEST-032 — verified
- TEST-032: run 45441258538 job 138612684702 at 90fb17ca07b8ecae0fc453f89e2131b00134dd5a completed success. Actual logs: 31 migrations, 39 suites PASS (31 SQL, eight concurrency), 84 prototype tables.

## BUILD-026D — latest
- 85 tables if applied, 32 migrations. BUILD-026D: one new normalized finance.fifo_cost_allocations child relation for exact outgoing-to-receipt cost provenance, same tenant/warehouse/variant composite FKs to existing movement cost facts. Single replay algorithm now emits FIFO source allocation detail; existing preview/replay signatures preserved. Capture checks allocation quantity and cost reconcile to outgoing cost and immutable retry. Moving average still uses aggregate cost facts, no artificial FIFO provenance. CI pending. No automatic costing enforcement, COGS posting, transfers/returns, or production access.


## FIX-006 — latest
- FIX-006 / 2026-11-24 — run 45441720623 job 138614372664 at 8ef451d9d7d52f088d402a932290d62a7ae6aa37 failed after 32 migrations applied and 31 SQL suites passed. SQLSTATE undefined_column from PL/pgSQL record b shadowing receipt alias b in 0029 test (record b has no field tenant_id). Renamed both SQL aliases a/b to fa/rb in both receipt provenance assertions; quantities, costs and all assertions preserved. No production SQL change; all concurrency suites skipped by failed job. Full CI rerun required. Last fully verified baseline TEST-032: 84 tables, 31 migrations, 39 suites PASS. Candidate: 85 tables, 32 migrations. No legacy/operational access.


## TEST-033 — verified
- TEST-033: run 45441927719 job 138615123346 at 6a5c074ab31ad720bb3e58990cd66babff982130 completed success, 32 migrations, 40 suites PASS (32 SQL, eight concurrency). FIX-006 verified. 85 prototype tables.

## BUILD-026E — latest
- 85 tables unchanged; 33 migrations if applied. BUILD-026E: added explicit positive ordinary FIFO sale COGS posting to existing journal with unique movement FK/source, matched source invoice inventory debit, expense account, order/variant locks, period gate and exact retry. No new table. Experimental, explicit posting only; zero cost, moving-average posting, returns/reversal, transfer, full account semantic mapping and dedicated races remain pending. No operational changes. CI pending.


## FIX-007 / MIG-ID-001 — latest
- FIX-007 / MIG-ID-001: run 45442387058 job 138616779663 at 86deadf3f95edda175168eda605774546300e4ee failed applying old 0030 (syntax error near DECLARE caused by assign_period ending END $; rather than END $$;); corrected exactly that delimiter. Pre-write validation initially rejected mismatched suffix of 0025 migration vs test; no mutation occurred, corrected check to compare numeric IDs, retaining original test name suffix. Renumbered all 33 migration/test pairs to contiguous 0001–0033, preserving previous lexical execution order and blob contents except single COGS delimiter fix. Historical IDs mapped in db/MIGRATION_ID_MAP.md. Added CI preflight and four guard unit tests. No tables, functions, grants or data semantics added/removed by renumbering. Last full verified TEST-033: 85 tables, 32 migrations, 40 suites at 6a5c074ab31ad720bb3e58990cd66babff982130; new CI pending. No persistent database migration or production access.


## FIX-008 — latest
- FIX-008 — GitHub read-back of MIG-ID-001 d01c00257a648010e8aa1de787444060f40e7318 confirmed 33 contiguous migration/test IDs, exact original ordering and unchanged blobs, but exposed that JavaScript replacement-string dollar escaping left the original delimiter unchanged. Corrected with literal callback replacement and asserted the invalid delimiter is absent. Run 45442789337 for the prior SHA was still in progress at read-back; no PASS claim. All renumbered SQL/test contents unchanged except the intended one-character correction in canonical 0033. Full CI on this new SHA required; no operational access.


## TEST-034 — verified
- TEST-034: run 45442881158 job 138618565410 at 0fea83bb72e798901ba622da99127dc9361fc499 completed success. 33 migrations, 41 SQL/concurrency suites (33 SQL, eight concurrency) PASS, plus four guard unit tests. Previous renumber-only run 45442789337 passed all four guard tests and 33 unique ID validation but failed COGS delimiter; FIX-008 verified. 85 prototype tables unchanged. All 33 SQL migrations inspected for table declarations; original sequence unchanged; no new table or operational access.

## TEST-035 candidate — latest
- TEST-035 candidate: added two actual competing-session scenarios for cost capture and COGS posting, with observed advisory lock waits, exact retries, immutable allocation reconciliation, one balanced journal and denied conflicting account, unauthorized/cross-tenant posting. Independent synthetic fixture; no new tables or SQL migration. CI pending. Explicit FIFO COGS is experimental, not approved accounting; return reversal, moving-average posting, transfer valuation and lifecycle enforcement remain pending.


## TEST-035 — verified
- TEST-035: run 45443295044 job 138620081848 at 0db9805c054545b939b05f7fd1355e050a976060 completed success. 33 migrations, 42 suites PASS (33 SQL + nine concurrency), four migration guard unit tests. Actual competing cost capture and COGS locks, idempotency and tenant gates confirmed. 85 tables.

## BUILD-026F — latest
- BUILD-026F: canonical 0034 adds explicit full ordinary sellable FIFO return reversal using existing journal, unique tenant return movement FK, exact sale/return relation and original expense/asset accounts and amount. No new table. Order and variant locks; existing fiscal period and immutable balanced journal. Tests include pre-return rejection, exact retry, closed-period reversal and conservation. No automatic posting. Does not yet reintegrate returned stock into cost replay or enable valuation of resale; capture remains fail closed after returns. Return-layer provenance, moving-average posting, zero-cost policy, transfers, further concurrency and approved accounting policy remain pending. CI pending; no operational access.


## FIX-009 — latest
- FIX-009 — run 45443813770 job 138621932950 at 0c84496d2238d44065e5ccb2fac34c7a4012db2a failed in 0034 acceptance test after guard and all 34 migrations passed; 33 SQL suites passed, concurrency skipped. Error 42702 ambiguous column reference amount in finance.reverse_fifo_cogs line 34. Renamed local amount to v_original_cost and updated both original journal line comparisons, preserving qualified l.amount and all existing assertions. No table, permission, accounting semantics or test change. Last fully verified TEST-035: 85 tables, 33 migrations, 42 suites and four guard unit tests. New CI pending, prototype only; no operational access.


## TEST-036 — verified
- TEST-036: run 45444335208 job 138623820708 at 6a53d994df36bd00036244d744b87270f2351e74 completed success; 34 migrations, 43 suites PASS (34 SQL + nine concurrency) and four migration guard tests. FIX-009 verified. 85 tables.

## BUILD-026G — latest
- BUILD-026G: canonical 0035 extends existing replay function (no duplicate tables or valuation API). Only full ordinary FIFO returns with exact original captured sale, confirmed COGS and reversal journal, original invoiced receipt allocations and sales access are admitted. Restores historical quantities/cost at end of FIFO queue, retains original receipt IDs and consolidates recurring receipt layers when consumed. Existing capture/journal APIs reused; no second inventory debit. Updated 0034 regression to reject unreversed returns and verify captured reversed returns; dedicated 0035 tests resale cost and journal conservation. Provisional FIFO return re-entry timing/order, no moving-average returns, transfer valuation, partial/damaged/zero-cost return, automatic posting, production approval or dedicated return concurrency. New CI pending. No operational access.


## FIX-010 — latest
- FIX-010 — run 45444927977 job 138625943750 at 25cc668fb1b17b689033fbde44a0f58f1d6629aa failed in 0034 regression with FAIL confirmed return capture after all 35 migrations and ID guard applied; 33 SQL suites passed, remaining suites skipped. The assertion combined two volatile capture calls and a read of their writes in one SQL expression; order and snapshot visibility are not guaranteed. Split write, exact retry and persisted row assertions into separate statements in 0034 and 0035, with explicit actual counts and separate error labels. Also separated two resale capture calls. No assertions removed, no migration/runtime semantics changed. This is a suspected fixture issue, not yet a verified root cause; new CI must confirm. Last full verified TEST-036: 85 tables, 34 migrations, 43 suites, four guard tests. No operational access.


## TEST-037 — verified
- TEST-037: run 45446005665 job 138629833448 at 44c83fff7fcd630b4e099bbef2e1515c20a41b7f completed success, 35 migrations, 44 SQL/concurrency suites (35 SQL + nine concurrency), four migration guard unit tests. FIX-010 and FIFO resale provenance verified. 85 tables unchanged.

## BUILD-026H — latest
- BUILD-026H: canonical 0036 introduces one shared explicit COGS posting implementation for FIFO and moving_average, retains existing strict FIFO wrapper without duplicate posting logic; existing journal source FK, idempotency, period and permission gates reused. Moving-average positive confirmed sale cost from captured immutable facts; every preceding positive pool movement must be an invoiced purchase receipt debited to the same inventory account, including depleted receipts (conservative restriction pending accounting approval). Mixed account pool rejected, exact retry, no fabricated FIFO allocations. Synthetic tests verify 1320 COGS and 880 asset balance, wrong account/method and closed period. No table, no production access or policy approval. Moving-average return, transfer, zero-cost handling, lifecycle and concurrent moving-average tests pending. New CI pending.


## TEST-038 — verified
- TEST-038: run 45446414562 job 138631301536 at 97756def76543e792a30c5f029a02288c4dae549 completed success; 36 migrations, 45 SQL/concurrency suites (36 SQL + nine concurrency) PASS and four migration guard tests. Shared moving-average posting verified; 85 tables.

## BUILD-026I — latest
- BUILD-026I: canonical 0037 extends existing return replay and shared COGS posting for moving_average; one shared reversal implementation with strict compatibility FIFO wrapper, same journal sources, historical exact cost from captured sale and reversal. Pool accepts confirmed return debit only to the same inventory asset; all preceding purchases still must match. No fictitious FIFO layers. Test changes rate via a later receipt, checks original 1320 returned, resale 2290, net COGS 2400, no duplicate debit, rejection before reversal, wrong method/account and closed period. No new tables. Provisional full ordinary sellable returns only; transfers, zero cost, tracked/partial/damaged returns, automatic lifecycle and dedicated return concurrency remain pending. CI pending; no production access.


## TEST-039 — verified
- TEST-039: run 45447390713 job 138634807713 at 01b420d7dac44ecf8ca0f082ede752321934740c completed success; 37 migrations, 46 SQL/concurrency suites (37 SQL + nine concurrency) PASS, four migration guard tests. Moving-average return and resale verified; 85 tables.

## BUILD-026J — latest
- BUILD-026J: canonical 0038 implements ordinary moving-average interwarehouse cost replay and atomic paired capture using existing transfer_lines and cost facts. No new tables, no transfer journal, transfer movement excluded from consumed COGS, exact signed pair reconciliation, private existing cost writer, variant lock and same permissions/RLS. Tests cover source/destination isolated capture rejection, exact retry, roundtrip quantity/value conservation, no new journal and blocked downstream COGS after transfer-in pending asset account provenance. Conservative capture requires whole histories in both warehouses to be replayable in source-then-destination order; complex uncaptured dependency chains fail closed. FIFO transfer, tracked transfer, destination COGS account mapping, cross-account reclassification, approved policy and dedicated transfer cost concurrency remain pending. New CI pending; no production access.


## TEST-040 — verified
- TEST-040: run 45448040617 job 138637116976 at 99964953c72573165a5a11ee4fe63203af236059 completed success; 38 migrations, 47 SQL/concurrency suites (38 SQL + nine concurrency) PASS and four migration guard tests; exact transfer cost pairs verified. 85 tables.

## BUILD-026K — latest
- BUILD-026K: canonical 0039 extends shared COGS posting to same-asset moving-average transfer provenance. Private recursive cutoff validator follows exact earlier paired transfer cost facts through warehouses to all preceding confirmed purchase/return journal debits, deduplicates nodes and rejects mixed account provenance, including remote inputs. No new table, no transfer journal or account reclassification. Updated 0038 regression to verify destination posting with correct account and reject wrong account. New 0039 tests cover destination/roundtrip COGS, remote mixed account rejection, balanced asset/cost and private helper permissions. Conservative history-wide input rule including exhausted inputs; cross-account transfers, FIFO, tracked, partial/zero-cost return and complex dependency chains remain pending, no production policy approval. CI pending; no operational access.


## TEST-041 — verified
- TEST-041: run 45448694965 job 138639477153 at 0013124130b576811f240ce5f62fb539652fc925 success; 39 migrations, 48 suites (39 SQL + nine concurrency), four guard tests. Recursive transfer asset provenance verified, 85 tables.

## BUILD-026L — latest
- BUILD-026L: canonical 0040 extends existing FIFO replay and paired transfer capture, preserving original invoiced receipt IDs and exact source cost allocations across warehouses. Replaces only receipt-side same-warehouse FK with tenant+variant+movement FK backed by unique constraint; outgoing warehouse FK unchanged. No table. Incoming FIFO layers appended in original receipt chronological order (provisional policy; not exact physical ordering of mixed restored layers). Tests cover paired atomicity, two receipt costs, roundtrip, original remote receipt allocation, destination COGS, full sellable return and resale, wrong account and permission. No transfer journal; same-asset receipt proof for COGS. Complex unrecorded dependency chains, tracked stock, zero/partial/damaged returns, account reclassification, lifecycle gates and dedicated cost concurrency remain pending. New CI pending; no production access.


## TEST-042 — verified
- TEST-042: run 45449124330 job 138641037866 at 609d53b8c2d1902c358bd6cb0b105eed598f0ad5 completed success; 40 unique migrations, 49 SQL/concurrency suites (40 SQL + nine concurrency), four migration ID unit tests. FIFO transfer, cross-warehouse provenance, destination COGS/return/resale verified; 85 tables.

## TEST-043 — latest
- TEST-043 candidate: expand existing verified COGS concurrency suite and fixture, not a duplicate harness or migration. Five actual competing lock races instead of two: initial cost capture, COGS posting, paired FIFO transfer capture, destination full-return reversal, and capture of restored return cost. Verify exact first/retry counts and identical journal ID, signed paired costs, blocked capture before reversal, tenant/permission rejection, immutable fact totals and source/destination quantity/value, 5 balanced journal headers, unchanged net COGS 1240 and inventory 960. Same PostgreSQL 16 synthetic CI. No schema/runtime changes; suite count remains 49, individual race cases increase by 3. New CI pending; no production access. Moving-average concurrency, lifecycle enforcement, tracked valuation, complex chain capture and accounting approval remain pending.


## TEST-043 — verified
- TEST-043 verified: run 45453244380 job 138655716755 at 18adb5816bf1ed4dde9b6815c97332eca9f9a4ab success; 40 migrations, 49 SQL/concurrency suites (40 SQL + nine concurrency), four guard unit tests; all five observed COGS contention races passed. 85 tables.

## BUILD-026M — latest
- BUILD-026M: canonical 0041 read-only tenant-scoped inventory_cost_issues and explicit assert_inventory_cost_ready, based on existing stock ledger, receipt evidence, immutable cost facts, journals and paired transfer lines. Reports missing cost/invoice/COGS/reversal, unsupported movement, mismatched purchase cost, unpaired transfer and zero sale cost awaiting policy. Requires finance/inventory/procurement/sales read and enabled modules; unknown or unconfigured scope fails closed; empty configured warehouse permitted. No table, no automatic operational block, no period-close change, no profit certification or full ledger audit; readiness covers this warehouse/variant snapshot only, not all accounting and not transaction locking. Tests include pending and resolved stages, unsupported movement and tenant/permission gates. Pending CI. Next approval-dependent lifecycle/locking and comprehensive reconciliation, moving-average races and tracked/complex transfers. No operational access. Earlier lookup of incorrect 0009 filename returned 404; corrected to canonical 0009_finance_lifecycle.sql, read only.


## FIX-011 — latest
- FIX-011: run 45463597151 job 138692481291 at 2b87e1fa16799dd157e3a49f366d55e7721642d9 failed in 0041 acceptance test with syntax error near BEGIN. All 41 migrations and migration ID guard passed; 40 SQL suites passed, concurrency skipped. Read-back found two END $; and one DO $ BEGIN instead of double-dollar delimiters in the test (JS replacement-string expansion). Corrected only those three delimiters using literal callback replacement, verified all three DO blocks have matching delimiters. No SQL runtime changes, no test assertions removed. Last fully verified baseline: 40 migrations, 49 suites (40 SQL + nine concurrency, five COGS races), four guard tests, 85 tables. New CI pending; no operational access.


## TEST-044 — verified
- TEST-044: run 45463986659 job 138693842767 at 1284fd4aa06521355e217a4bb4269870d47161a6 success; 41 migrations, 50 suites (41 SQL + nine concurrency), four guard tests. FIX-011 and lifecycle diagnostics verified; 85 tables.

## BUILD-026N — latest
- BUILD-026N: canonical 0042 extends existing read-only inventory_cost_issues (same readiness API, no table) with invoice journal amount/type/currency checks against whole supplier invoice, COGS signed amount/type/currency checks against immutable fact, return journal exact original account/amount reversal and returned fact match. After basic lifecycle checks pass, replays configured warehouse/variant and compares each captured sequence, quantity, cost, invoiced status and exact FIFO sources; replay check violation yields scope-level issue. Synthetic fault injection via privileged test transaction and savepoints, including temporary immutable trigger disable ONLY in disposable CI and rollback, validates balanced but wrong invoice/reversal and changed sale cost/allocation/sequence; normal API cannot mutate facts. No automatic posting/closure, no complete tenant-wide financial certification or account-balance reconciliation. Scope snapshot only, may require load testing. New CI pending. No production access.


## TEST-045 — verified
- TEST-045: run 45467042707 job 138704599957 at 0f285a80a540254828e7c68555342e81cd06b0ad success; 42 migrations, 51 suites (42 SQL + nine concurrency), four migration guard tests. Exact replay and journal fault injection verified. 85 tables.

## TEST-046 — latest
- TEST-046 candidate: extend same existing COGS concurrency harness with five additional moving-average two-session lock races (capture, COGS posting, paired transfer, reversal, return cost capture), using existing unused variant and separate synthetic asset/expense accounts, no duplicated fixture or migration. Expect exact retry counts/IDs, 1320 historical initial COGS, paired 330 transfer and return, 880 net inventory, 1320 net expense, no FIFO allocations, ten total journal headers across both scenarios and readiness checks in both warehouses. Tenant/permission and wrong-method checks. No runtime/DDL changes. Suite count remains 51; ten actual COGS races pending CI. No production access; next tenant-level reconciliation, complex chains, tracked valuation and policy approval.


## TEST-047 — verified
- TEST-047: run 45475840661 job 138735731458 at b37d5aa5df13e211498a7b2c4d542d61814ac1d8 success; 42 migrations, 51 SQL/concurrency suites (42 SQL + nine concurrency), four migration guard tests; ten observed lock races, five FIFO and five moving-average, verified. 85 tables.

## BUILD-026O — latest
- BUILD-026O: canonical 0043 tenant-wide read-only inventory reconciliation reuses existing per-scope diagnostics and canonical ledger, reports missing valuation policy even without facts, compares signed captured value to inventory-source asset journal net separately per currency, reports each inventory-related asset account and outside journal activity (including net-zero outside activity), explicit conservative tenant readiness assertion. No table, stored balance, account mapping or auto posting. Outside activity is a review flag, not necessarily erroneous; totals are currency-level comparison, NOT independently attributed expected balance per account, and not full financial certification or locked period close. Tests cover clean FIFO, missing facts, two currencies/methods, unconfigured scope, manual offset, tenant isolation and permission. New CI pending. Complex chain capture, tracked valuation, approved accounting and performance/period-lock review pending; no production access.


## FIX-012 — latest
- FIX-012: run 45578648148 job 139082801809 at 775b58592165d8a5c9e43892fa5d2d2ddf9d2a6c failed at 0043 synthetic test with record a has no field account_id; PL/pgSQL local preview record a collides with SQL alias a in two asset-activity assertions. All 43 migrations applied, 42 prior SQL suites passed; concurrency skipped. Changed only both conflicting SQL aliases to aa, retaining preview variables and all assertions. No runtime/DDL changes. Fully verified baseline 42 migrations, 51 suites (42 SQL + nine concurrency; ten COGS lock races), four guard tests, 85 tables. New CI pending. No production access.


## TEST-048 — verified
- TEST-048: run 45578934697 job 139083768266 at 429e9672dc8c7832d77d78fc856ef91ce7396a55 success; 43 migrations, 52 suites (43 SQL + nine concurrency), four guard tests, ten COGS races; tenant reconciliation and FIX-012 verified; 85 tables.

## BUILD-026P — latest
- BUILD-026P: canonical 0044 factors existing replay into one read-only optional inclusive prefix engine and full replay wrapper; one private prefix cost writer and existing full private wrapper. Existing transfer capture now walks the historically connected warehouses for the same tenant/variant under variant lock, processes transfer pairs in outgoing chronological order then validates full histories/pairs, all in one transaction. No tables or duplicate costing algorithms. Both methods tested on A->B->C->A with later uninvoiced receipt forcing rollback of all tentative facts/allocations, then exact retry, per-warehouse balance, destination sale/receipt lineage, tenant totals, private writer and cutoff access. New behavior captures all connected histories, not just requested transfer; conservative fail-closed if any later unsupported/unconfirmed movement. Replay repeated per transfer, performance/large history limits not benchmarked; strict chronology, tracked valuation and financial policy still pending. CI pending. No operational access.


## TEST-049 — verified
- TEST-049: run 45581403955 job 139092072763 at dc802a9407f6ce07efaeb9a620452cc937919dde success; 44 migrations, 53 suites (44 SQL + nine concurrency), four guard tests and ten COGS races; 0044 connected transfer capture, rollback and remote COGS provenance verified; 85 tables.

## TEST-050 — latest
- TEST-050 candidate: extend the existing COGS concurrency harness to accept a different second statement and add one actual two-session chain contention scenario per valuation method; two different transfer IDs in the same three-warehouse component must yield first=6 new facts, second=0 with observed advisory lock wait. Reuse existing synthetic variants/tenants, add only one synthetic warehouse. Then eight cycles (24 transfers, 48 new cost facts) per method, timed capture and retry logged as CHAIN_TIMING; check 61 facts per variant, 28 exact pairs per variant, conserved quantity and value, no new journals, readiness and no moving-average FIFO rows. 60s statement timeout is only CI ceiling; sample includes client overhead and is not production capacity/load certification. No DDL/runtime changes; 12 actual race cases pending new CI, 53 suites unchanged. Next tracked valuation design and targeted performance review; no operational access.


## DESIGN-0045 — latest
- DESIGN-0045: reviewed tracking policies, lots/serials, allocated receipt/transfer, reservation allocations, tracked return keys, existing cost facts, FIFO allocation and journal boundaries; added staged proposed trace valuation design and acceptance criteria to existing valuation design doc, no new table/migration/runtime change. Explicit provisional serial specific identification / lot-restricted FIFO, never equate FEFO with financial costing. First 0045 read-only trace evidence, then policy/replay/capture/journals in increments. TEST-050 run 45582369761 job 139095338216 at 9410c90335794e4b2b27b04278315deca3e2bc67 is in_progress; no new test pass claimed. No operational access.


## TEST-051 — verified
- TEST-051: TEST-050 run 45582369761 job 139095338216 at 9410c90335794e4b2b27b04278315deca3e2bc67 success; 44 migrations, 53 suites (44 SQL + nine concurrency), four guard tests and twelve COGS races. CHAIN_TIMING FIFO 1191ms capture/1170ms retry, moving-average -263ms capture (INVALID wall-clock discontinuity)/341ms retry. 85 tables. No production benchmark claim.

## BUILD-026Q — latest
- BUILD-026Q: 0045 read-only tracked_movement_evidence, one canonical movement lookup with four module/permission gates, exact traced identity, receipt/invoice, paired multi-line transfers, consumed sale allocation and full returned allocation/source evidence. Reject unsupported or missing/ambiguous evidence, tenant isolation; no cost fact, policy, journal or table writes. Tests cover split receipt/one invoice, four-line transfer, FEFO sale allocation, full return identity, unsupported adjustment and permissions. Also fix timing harness using monotonic_ns and nonnegative assertion; rerun timings. New CI pending. Valuation policy/engine/COGS still unsupported for tracked variants; no operational access.


## TEST-052 — verified
- TEST-052: run 45584291044 job 139101830912 at 9e35012d01077f482be9ad09c7c13d40d822d787 success; 45 migrations, 54 suites (45 SQL + nine concurrency), four guard tests and twelve observed COGS races. Tracked evidence verified. Valid CHAIN_TIMING (monotonic wall elapsed including client): FIFO 691ms capture/678ms retry; moving_average 258ms capture/256ms retry, 24 extra transfers and 48 new facts each. Synthetic only, 85 tables.

## BUILD-026R — latest
- BUILD-026R: canonical 0046 extends only existing valuation_policies method constraint with explicit experimental lot_fifo and serial_specific. Same configuration API and variant lock, tracking-first enrollment before stock/reservations, exact immutable retries, ordinary methods unchanged and reverse enrollment guarded to prevent ordinary policy + tracking mismatch. Configured tracked preview fails closed; existing capture engine rejects new methods until supported, no financial facts or posting activation. Tests include invalid method/identity/order, post-stock enrollment, exact retries, read/write permissions, tenant isolation and pending readiness. README corrected stale planning/private/CI statements using confirmed public repository metadata and TEST-052 checkpoint; no visibility change. New CI pending. Next shared tracked replay/prefix, then multi-line transfers and tracked COGS/returns; policy remains provisional. No production access.


## TEST-053 — verified
- TEST-053: run 45585132510 job 139104673552 at c1002e07bd590386985ecbb5345350c6d46087f2 success; 46 migrations, 55 suites (46 SQL + nine concurrency), four guard tests, twelve COGS races; explicit tracked policies verified. CHAIN_TIMING FIFO 1553/1543 ms, moving_average 451/445 ms (synthetic). 85 tables.

## BUILD-026S — latest
- BUILD-026S: canonical 0047 extends the existing replay/prefix engine and one cost writer, not a parallel costing algorithm. For lot_fifo/serial_specific require exact immutable policy, four read/module gates and 0045 evidence; consume only positive remaining layers with matching lot AND serial, chronological first within identity. Existing FIFO source table reused for both methods, including specific-identification receipt allocation; no new tables. Receipt/sale only; tracked transfers/returns and COGS/reversal posting remain fail closed, readiness reports pending. Tenant-filtered read-only private executor dependencies added, no runtime table write grants. Tests cover unconfirmed rollback, FEFO physical selection vs cost layers, lot split receipt and exact serial receipt IDs, cost retry, wrong currency/method, no posting and isolation. 0046 acceptance's obsolete blanket preview prohibition replaced with unconfirmed read-only preview and invoice-required capture; remaining assertions retained. CI pending; no production access.


## TEST-054 — verified
- TEST-054: run 45586345108 job 139108810312 at 111339e57c452d9ad232bd203d783bca7f87a0be success; {"migrations":47,"pass":56,"latest":["2026-11-25T09:32:40.0861724Z Ran 4 tests in 0.001s","2026-11-25T09:32:40.0863057Z Migration ID guard: 47 unique contiguous migration/test pairs","2026-11-25T09:33:11.6906832Z PASS shared traced receipt and sale valuation, lot FIFO restricted layers, serial exact source, retries and fail closed","2026-11-25T09:35:24.5123343Z CHAIN_TIMING method=fifo transfers=24 new_facts=48 capture_ms=999 retry_ms=990","2026-11-25T09:35:35.1956685Z CHAIN_TIMING method=moving_average transfers=24 new_facts=48 capture_ms=297 retry_ms=299","2026-11-25T09:35:54.7494356Z PASS COGS concurrency: twelve competing lock races (six FIFO, six moving average), distinct chain entry points, 48 extra transfer pairs, readiness and tenant isolation"]}; 85 tables.

## BUILD-026T — latest
- BUILD-026T: 0048 extends same replay and connected capture for tracked transfer pairs, multi-line same variant via existing header FK, exact lot/serial evidence and original receipt identity, no transfer journal or new table. Tracked return replay and COGS posting remain blocked. Tests cover mixed lot/serial multi-line A-B-C-A, rollback with later uninvoiced receipt, exact retries, remote FEFO and serial sale provenance, conserved value and tenant permissions. Existing 0047 isolated-capture rollback assertion retained (now fails because missing peer). New CI pending; no operational access.


## TEST-055 — verified
- TEST-055: run 45587060563 job 139111239826 at b571a3205323205313177954cf8d55b8a5488f27 success; 48 migrations, 57 suites (48 SQL + nine concurrency), four guard tests and twelve COGS races. Traced multiline transfer chain verified. CHAIN_TIMING FIFO 777/765 ms, moving_average 258/253 ms, synthetic. 85 tables.

## BUILD-026U — latest
- BUILD-026U: 0049 extends existing post_inventory_cogs and inventory_cost_issues; traced sale identified by exact 0045 evidence, same order/variant locks, confirmed prefix replay and exact source allocations required before writing one journal per sale movement using existing cogs key. Same asset/expense scope and original invoice debit plus exact lot/serial identity. No duplicate writer/table. Readiness now accepts supported traced receipt/sale/transfer histories and still blocks traced returns; replay checks remain. Test on multi-hop lot and serial sale plus a second order with two lot allocations, four COGS journals, exact/conflicting retries, wrong account/method and transfer rejection, tenant-level conservation 680 inventory/740 expense, permissions. 0046 obsolete unsupported receipt diagnostic assertion updated to purchase_invoice_missing. Traced reversal/return replay still pending. New CI pending. No production access.


## TEST-056 — verified
- TEST-056: run 45587915545 job 139114165981 at de663b49b0c5337c905fe9b23c30bb9a4ec4a497 success; 49 migrations, 58 suites (49 SQL + nine concurrency), four guard tests, twelve COGS races. Traced COGS and readiness verified. CHAIN_TIMING FIFO 900/894 ms, moving_average 281/275 ms, synthetic. 85 tables.

## BUILD-026V — latest
- BUILD-026V: canonical 0050 extends shared reverse_inventory_cogs, replay/prefix and readiness for exact full sellable traced returns. Original allocation and return key, exact identity, captured original replay, original and inverse journal lines, historical receipt layers restored in same engine; no new table or writer. Tests extend 0049 synthetic lifecycle with four returns over two orders, pre-reversal capture denial, wrong method, exact retries, value restoration 1420 and net expense zero, resale and tenant readiness. Traced reversal/return concurrency, partial/damaged/expired/zero-cost policies and period-close controls remain pending. New CI pending; no operational access.


## TEST-057 — verified
- TEST-057: run 45589346958 job 139119098459 at 5be9619e3bd58a6d530fe7a21bf684e69a547459 success; 50 migrations, 59 suites (50 SQL + nine concurrency), four guard tests, twelve COGS races. Exact traced full return and resale verified. CHAIN_TIMING FIFO 887/877 ms, moving_average 265/259 ms, synthetic. 85 tables.

## TEST-058 — latest
- TEST-058 candidate: extend existing COGS harness (no new test suite or runtime changes) with six actual two-session advisory lock races per lot_fifo and serial_specific: capture two confirmed receipts, capture two transfer pairs, capture two sale allocations, post two COGS journals, reverse both exact returns, capture both returns. Both post/reversal requests run both allocations atomically, same order/variant locks; check exact UUID retries, one-time facts and journals, remote receipt identity, pre-reversal rejection, conservation and readiness, reader/tenant gates. Expected 24 total race scenarios, 59 suites unchanged, 22 journals in isolated synthetic tenant. New CI pending. Not a production load benchmark. No operational access.


## TEST-059 — verified
- TEST-059: run 45595381537 job 139139952220 at db67b4571fe1e7bce28e18414886b7f7a1adb8bc success; 50 migrations, 59 suites (50 SQL + nine concurrency), four migration guard tests, 24 actual COGS lock races (six per method). CHAIN_TIMING FIFO 1147/1143 ms, moving_average 331/324 ms, synthetic. 85 tables.

## BUILD-026W — latest
- BUILD-026W: 0051 adds one read-only finance.inventory_period_close_issues(period) preflight using existing tenant reconciliation, period.manage + four read/module gates, exact tenant period and exclusive UTC upper-date boundary. Reports not ended, already closed, any newer inventory movements or source-linked inventory journals, plus existing current-state issues. No historical as-of certification or automatic close; current-state readiness alone cannot certify a past cutoff with newer activity. Existing close_period unchanged. Tests cover empty ended, current/future, unknown stock, uninvoiced, mismatched/captured and later journal, read-only, permissions, foreign period. No new tables. CI pending. Next design an atomic tenant-scoped write barrier, inventory as-of/cutoff policy and actual single close API guard; do not reverse existing lock order or silently alter module/period policy. Partial/damaged/expired returns pending. No production access.


## DESIGN-0052 — latest
- DESIGN-0052: reviewed exact inventory ledger/receipt basis, valuation writer, journal period gate, tracked sales and cross-tenant module decision paths; documented candidate shared/exclusive tenant barrier, fail-fast 55P03, dependency coverage matrix, snapshot/backdating, permissions/module expiry, legacy early-close behavior, staged 0052 private guard then single close API integration, acceptance and historical as-of limitations. Docs only, no DDL or close behavior changes. 0051 run 45596926623 job 139145335825 at aa77ac75e4245c908dad2a9c2744f65cfc8511c7 status in_progress; SQL acceptance step completed successfully; full CI not yet verified. No operational access.


## TEST-060 — verified
- TEST-060: run 45596926623 job 139145335825 at aa77ac75e4245c908dad2a9c2744f65cfc8511c7 success; 51 migrations, 60 suites (51 SQL + nine concurrency), four ID guard tests, 24 COGS races. CHAIN_TIMING FIFO 1209/1152ms, moving_average 341/329ms synthetic. 85 tables.

## BUILD-026X — latest
- BUILD-026X: 0052 implements private fail-fast transaction advisory barrier (shared writes, exclusive future close; 55P03); trigger covers 32 existing tenant-scoped reference relations (inventory, valuation, purchase, journal, sales, catalog, membership/module and periods), all insert/update/delete, rejects tenant reassignment, no runtime execute or extra table grants. Shared writes preserve existing API-specific isolation, exclusive READ COMMITTED. Actual two-session tests extend COGS harness: writer blocks exclusive, distinct variant succeeds, exclusive blocks stock/cost/journal and second exclusive, other tenant succeeds, rollback and capture retry; no change close_period yet. Global identity/DDL/TRUNCATE privileged admin operations, module time expiry, backdating, transaction upgrades and historical cutoff semantics still need explicit review before activation. Not production capacity evidence. New CI pending. No operational access.


## TEST-061 — verified
- TEST-061: run 45599712882 job 139155078197 at b8e6fa739a32adc40a370701dd127148026cd954 success; 52 migrations, 61 suites (52 SQL + nine concurrency), four guard tests, 24 COGS races and actual private barrier bidirectional exclusion/concurrent shared writers/other tenant/rollback/retry. Synthetic CHAIN_TIMING FIFO 1667/1680ms, moving_average 566/555ms. 85 tables.

## BUILD-026Y — latest
- BUILD-026Y: code SHA 36d261c1c1bb57a6e4bf012c52cc155325fea15f adds 0053 in existing finance.close_period, conservative provisional end-date UTC gate, no upgrade of own shared/exclusive lock, exclusive fail-fast barrier then nonwaiting legacy period lock, fresh READ COMMITTED reads, permission recheck, real inventory history check using existing private finance executor, preflight for any history, empty-history finance-only path, exact closed retry, guard rejects later mutations in the same close transaction. No new tables/API. Eight legacy SQL tests explicitly reject unsafe close then use rollback-only scoped UPDATE grant/policy to simulate already-closed posting fixture; preserve posting/retry/rollback checks; no such production grant. New 0053 SQL tests for early/upgrade/invalid/foreign/unauthorized close; existing COGS harness extended with actual close vs writer, historical rejection, finance-only tenant B, concurrent two closes, post-close mutation rejection and exact retry timestamp. New CI pending. Verify before proceeding. Limitations: conservative cumulative history gate blocks historical close after later inventory activity; positive nonempty historical close and time/backdating/admin mutation audit still needed; no general accounting completeness certification, policy provisional, no production access. CI overhead and legacy test adjustments require review.

## TEST-062 — verified / 2026-11-25
- TEST-062: run 45601424659 job 139161026188 at 36d261c1c1bb57a6e4bf012c52cc155325fea15f completed success; 53 unique migrations and SQL suites, nine concurrency suites (62 total PASS), four migration guard tests, 24 COGS races plus atomic close/barrier cases; 85 prototype tables per verified preceding baseline (0053 creates no tables). CHAIN_TIMING FIFO 1364/1354ms, moving_average 393/371ms, synthetic capture/retry only. No production access.

## TEST-063 — candidate / 2026-11-25
- TEST-063 candidate: extend existing COGS concurrency suite with actual platform.record_module_decision (non-tenant synthetic platform approver), disabled inventory module with existing history must fail closed, module writer vs close and close vs module writer fail fast 55P03, independent tenant decision allowed and rollback; retain all prior assertions. No new migration, table, public function or policy. CI pending. First verify exact candidate run; then positive nonempty historical close fixture and backdating/admin/expiry review.

## TEST-063 — verified / 2026-11-25
- TEST-063 verified: run 45604079177 job 139170248068 at a81aa6e62201f47163dbc79ccc164a42869c9d27 completed success; 53 migration/test pairs, 62 PASS suites, four guard tests, 24 COGS races plus actual module decision contention. CHAIN_TIMING FIFO 1397/1394ms, moving_average 382/362ms synthetic only. No production access.

## TEST-064 — candidate / 2026-11-25
- TEST-064 candidate: positive nonempty historical close using existing COGS tenant B after finance-only cases, one purchase receipt, invoice and captured FIFO cost 200 IRR. Test-only scoped INSERT clock projection creates historical facts through existing APIs, retains existing triggers and removes fixture triggers/function before committed close. Existing journal gate runs for current open period then fixture-only trigger projects historical period; this is synthetic data construction, not evidence of production backdating. Actual close, preflight, cross-tenant rejection, exact retry and no extra facts/journal assertions. 53 migrations, 85 tables, no runtime code change. CI pending. Late cost capture, as-of and module expiry/admin policy remain open.

## TEST-064 — verified / 2026-11-25
- TEST-064 verified: run 45605363818 job 139174725186 at 10746494260b5b24e445bf0e14b69e8bfa7edcb5 completed success; 53 migration/test pairs, 62 PASS suites, four guard tests, 24 COGS races plus real module decision contention and positive nonempty reconciled historical close. 85 tables confirmed; CHAIN_TIMING FIFO 704/680ms, moving_average 221/207ms synthetic only. No production access.

## TEST-065 — candidate / 2026-11-25
- TEST-065 candidate: characterize actual existing late cost capture in rollback-only historical fixture and statement-time inventory entitlement expiry across actual close (rolled back, fresh statement denies, restore entitlement and retain positive close). Check four actual synthetic logins for SUPERUSER/BYPASSRLS/CREATEROLE, executor membership, direct table/column mutation privileges on eight protected relations. No new runtime behavior/policy, table or migration; new CI pending. Time-at-row-barrier boundary remains untested; historical as-of and expiry/late-cost final policy unapproved.

## TEST-065 — pending observation / 2026-11-25
- TEST-065 run 45606515589 at 7ad0480313c54bc7160f14786dccaa89e5859dbd still in progress; at last job inspection guard, migrations, SQL and eight concurrency suites passed; final COGS pending.

## DESIGN-0054 — 2026-11-25
- DESIGN-0054 / 2026-11-25: Reviewed current full-return/refund, order locks and item/reservation identity, tracked sales and expiry, FIFO/moving-average/traced reversal and replay, current financial posting, warehouse transfer and period barrier. Added candidate phased partial/damaged/expired return design to existing inventory valuation design; retain canonical sales.returns, sales.refunds, stock_ledger, cost facts, FIFO allocations and journal entries. Independent per-return line fact is proposed only if validated as necessary; no new DDL/table/function/test. Preserve full-return contracts and exact retry; physical receipt, refund and financial valuation are distinct, not automatically coupled. Disposition, partial FIFO cost allocation, impairment, refund calculation and period-effective policy require approval before financial activation. No production access.

## TEST-065 — verified / 2026-11-25
- TEST-065 verified: run 45606515589 job 139178670484 at 7ad0480313c54bc7160f14786dccaa89e5859dbd success; 53 migrations, 62 PASS suites, four ID guard tests, 24 COGS races; observed late captured_at not flagged and statement-start entitlement remains usable after expiry within same statement; fresh statement denied, rollback and protected-role checks passed. CHAIN_TIMING FIFO 689/670ms, moving_average 210/198ms synthetic. These observed limitations are not approved accounting/security policy.

## BUILD-026Z — candidate / 2026-11-25
- BUILD-026Z candidate: 0054 adds one read-only finance.order_return_capacity(order) derived from canonical orders/items, consumed reservations, exact sale stock movements and existing full-return header/key. Reuses tracked_movement_evidence for traced sales/returns, validates exact ordinary evidence and sums, fails closed for unfulfilled/refunded-without-return and ambiguous/unsupported history. No physical receipt/refund/cost writer, no table, no new permission/grant beyond execute for runtime with four existing read/module gates. Tests ordinary and lot/serial before/after full return, pending/missing and access isolation, reuse prior synthetic setup. CI pending; 54 migration/test pairs expected, 63 suites, 85 tables. Partial returns, disposition, cost allocation and refund policy still pending.

## TEST-066 — verified / 2026-11-25
- TEST-066 verified: run 45608739070 job 139186372930 at 4b4fd9e0408f88c5af22be75865418eea2f8093c success; 54 migration/test pairs, 63 PASS suites, 85 tables, four ID guard tests; 0054 ordinary/traced return capacity successful; TEST-065 observations reconfirmed. No new physical return writer.

## BUILD-027A — candidate / 2026-11-25
- BUILD-027A candidate: 0055 replaces existing preflight and close; explicit late capture issue for pre-cutoff movement with captured_at at/after UTC cutoff, closes fail closed without rewriting any facts. Single shared entitlement implementation via private explicit-time overload, original statement-time signature/RLS unchanged, live finance check at entry, required modules after exclusive/period lock and immediately before and after close update; no commit-time guarantee. Tests: ACL, existing late and expiry characterization assertions upgraded to rejection, actual expiry during UPDATE using scoped synthetic trigger, independent committed historical late-cost fixture at end of COGS. Existing positive historical and concurrency tests retained. 55 migrations/64 suites expected, 85 tables unchanged, CI pending. No production access. No approved late adjustment, effective-date or global module expiry policy.

## BUILD-027A — CI checkpoint / 2026-11-25
- 0055 run 45610267991 at b321c2ddc975af47acf89337b234be4c48c0efdd in progress; job 139191653353 guard, all migrations, SQL and eight concurrency steps passed; final COGS not yet verified.

## REVIEW-027A — 2026-11-25
- REVIEW-027A / 2026-11-25: inspected 0005/0007 actual adjustment API, 0052/0053 barrier, 0055 close/entitlement implementation and the new standalone temporal fixture. Designed deterministic follow-up observations for post-close/pre-COMMIT module expiry and default stock recorded_at before tenant barrier, using only synthetic tenants, existing APIs and isolated temporary test instrumentation. No executable changes while 0055 CI is pending (or before independent regression authoring). Commit-time guarantee, effective-date semantics and remedy remain open. Do not mislabel observed behavior as owner-approved policy. No production access.

## TEST-067 — failed / 2026-11-25
- TEST-067 failed: Run 45610267991 job 139191653353 at b321c2ddc975af47acf89337b234be4c48c0efdd. 55 migration/test pairs and SQL/8 concurrency steps passed; COGS notices prove late-cost preflight diagnostic, stale entitlement rejection and expiry-during-update rollback. Final standalone fixture failed SQLSTATE 23505 role_grants_pkey because bootstrap SELECT used common role_key inventory-editor against roles from earlier concurrency suites (actual other tenant 90000000-0000-0000-0000-000000000001). Committed late-cost actual close not reached. Overall CI failed; last fully verified 0054 run 45608739070.

## FIX-027A — candidate / 2026-11-25
- FIX-027A candidate: namespace temporal fixture role keys and scope EVERY role-grant/membership selection to exact two synthetic tenant IDs and three synthetic users. Assert isolated role/membership cardinalities, preserve PK and all existing assertions. No ON CONFLICT suppression, no changes to migrations, RLS, runtime or financial policy. Re-run full CI and prove independent committed late-cost rejection. Next unused 0056.

## REVIEW-027B — 2026-11-25
- REVIEW-027B: audited all 55 migration files at 0f0614a49dd5ce236e88528d43afddde42b62c59 for table declarations/return-refund references and reviewed active 0007,0009,0027,0050,0054 contracts. No equivalent independent return receipt/disposition line relation found; documented necessity, candidate composite FK design, full-return/replay/refund caller matrix, and barrier scope (returns covered, payment/refund not listed; journals covered). No executable changes while run 45618642657 in progress. Next verify full CI, then REVIEW-027A observations, then minimal 0056 with no financial activation. No production access.

## TEST-069 — verified / 2026-11-25
- TEST-068 failed at 0f0614a49dd5ce236e88528d43afddde42b62c59 run 45618642657 with SQLSTATE 42601 at DO $; owner identified delimiter; FIX-027B at 1cf43716d1dd8f00e80192f6432c0fcc06caeb33 changed exactly two delimiter lines, no assertion or policy. TEST-069 verified run 45619317852 job 139222918412 at that exact SHA completed success: 55 contiguous migration/test pairs, 64 PASS suites, 85 tables, four ID guard tests, all nine concurrency suites and 24 COGS races. Four TEMPORAL_GUARD notices verified including independent committed late-cost close rejection. FIFO chain 1711/1699ms and moving-average 539/519ms synthetic only. No production access.

## TEST-070 — candidate / 2026-11-25
- TEST-070 candidate: characterize actual close followed by finance expiry before COMMIT and actual stock DEFAULT evaluated before shared tenant barrier using isolated temporal fixture B; exact two-int test lock, actual blocked writer and independent close commit verified by pg_locks, no timestamp rewrite or midnight crossing. Temporary test trigger removed; existing retry and ledger cap assertions retained. No runtime SQL, migration, table, financial or module policy change. CI pending.

## REVIEW-027C — 2026-11-25
- REVIEW-027C: exact key audit 0005/0006/0007/0027/0028/0031/0052/0054 at df91393c97e5668b548975cdd21411eabb2458cb; use reservation unique identity of order_item and sale movement with nonnull reservation FK to derive item/product/warehouse/lot/serial/allocation instead of duplicate columns. Document exact three candidate composite unique/FK targets, no direct writer until cap and existing lock/RLS/barrier integration, structural negative test matrix. No new table or SQL; TEST-070 run 45621026901 still in progress. No production or policy change.

## TEST-070 — verified / 2026-11-25
- TEST-070 verified run 45621026901 job 139228880850 at df91393c97e5668b548975cdd21411eabb2458cb success; 55 contiguous pairs, 64 PASS suites, 85 tables, four ID guards, 24 COGS races. Four prior temporal guards passed. Actual committed close persisted after finance expiry between function return and COMMIT; actual stock DEFAULT preceded a close committed before writer got shared barrier, no cutoff crossing proven. FIFO 1280/1266ms, moving average 511/493ms synthetic. Neither remaining behavior approved as production policy.

## BUILD-027B — candidate / 2026-11-25
- BUILD-027B candidate: 0056 creates exactly one independent dormant sales.return_items fact, justified by REVIEW-027B/C audit; three exact composite superkeys/FKs bind tenant/order/header/reservation/original sale movement. No duplicate product/trace/price/stock master, no writer/backfill, no DML grants even to executors; sales.read/module RLS+FORCE and existing mutation barrier. Existing full-return/refund/valuation APIs and unique constraints unchanged. Rollback fixture checks legacy ordinary/traced, cross-tenant and mismatched header/order/reservation/movement, adjustment/null, positive quantity/disposition, duplicate, ACL and actual RLS; no inventory or finance change. Aggregate quantity cap, real disposition/quarantine, financial eligibility and late/commit-time policies not implemented or approved. 56 pairs/65 PASS/86 tables expected; CI pending. No operational access.

## TEST-071 — verified / 2026-11-25
- TEST-071 verified run 45623787029 job 139238530412 at 93dce31b3e3f4a1061fc3f75ee6312b04393e937 success; 56 contiguous migration/test pairs, 65 PASS suites, 86 tables, four ID guard tests and 24 COGS races. PASS dormant return line identity/composite FK/RLS/ACL/barrier/legacy/no financial changes verified, prior temporal guards and observations retained.

## BUILD-027C — candidate / 2026-11-25
- BUILD-027C candidate: 0057 adds one private SECURITY INVOKER VOLATILE receipt-line cap trigger, reuse sales.lock_order and existing barrier, READ COMMITTED only, fresh aggregate numeric quantity by original sale movement across dispositions, append-only. No DML grants or new table; legacy writer remains unchanged and no partial/refund/valuation active. Prior 0056 positive classification fixture adjusted to valid quantities under new cap; all FK/RLS/ACL/negative assertions retained. New SQL tests single overcap, multirow rollback, mixed dispositions, update/delete denial, stale snapshot rejection and no legacy double-count. Existing sales concurrency harness uses actual legacy sale/return and two privileged disposable inserts, exact order lock wait, second SQLSTATE 23514, ledger unchanged; not a production/runtime writer. 57 pairs/66 PASS/86 tables expected, CI pending. Next integrate single legacy writer with exact evidence, no double counting or implicit backfill, and test actual runtime concurrency before any partial disposition. No operational access.

## REVIEW-027E — 2026-11-25
- REVIEW-027E: audited upc_sales_executor grants and current 0027 writer/0057 cap. Proposed scoped column SELECT for stock/reservation and tenant-scoped SELECT/INSERT for receipt facts only, no role escalation; preserve same canonical writer/locks, full sale and return provenance, exact retry without implicit backfill. Keep privileged cap/classification fixture separate from new actual runtime full return, preserve all existing negative tests; actual pre-upgrade legacy evidence fixture needed for historical compatibility. No executable change; 0057 run 45625448713 still in progress.

## TEST-072 — verified / 2026-11-25
- TEST-072 verified run 45625448713 job 139244289349 at aa1dd061853a028ce11d61bfc9a490130fefc4d6 success: 57 contiguous pairs, 66 PASS suites, 86 tables, four ID guards, 24 COGS races. RETURN_CAP_RACE exact order lock serialization and excess rejection proven; SQL aggregate/multi-row rollback/append-only/stale snapshot/no double-count passed.

## BUILD-027D — candidate / 2026-11-25
- BUILD-027D candidate: 0058 replaces same full-return allocated writer, keeps request/order locks, existing wrapper/owner/ACL, requires exact consumed reservation and original/return movement evidence, inserts sellable receipt line per movement, no partial writer or table. Scoped column SELECT on reservation/stock and tenant RLS; only existing private sales executor SELECT/INSERT sellable fact, no runtime DML or executor UPDATE/DELETE. Old zero-line exact retry remains read-only; existing line retry validates exact evidence. Evolve 0056/0057 fixtures to independent fulfilled synthetic orders/headers so all negative structural/cap checks survive; real full-return evidence now checked. New 0058 tests actual ordinary/traced/serial, exact retry/conflict, ACL, injected line failure rollback, actual same-key and different-key runtime races and original privileged cap race. Historical upgrade on actual pre-0058 rows not yet independently tested; no backfill. 58 pairs/67 PASS/86 tables expected, CI pending. No operational access or financial policy.

## FIX-028A — 2026-11-25
- TEST-073 / FIX-028A: exact 0058 run 45627260327 job 139250654541 at cad159104e2d70c7d01e568993ae9e279b373f36 failed only at pricing concurrency after all 58 migrations, SQL suites and identity/inventory/sales races passed. Logs show PASS canonical full-return writer, RETURN_WRITER_RACE, RETURN_CAP_RACE, both stale price checkouts rejected; pricing.sh final count still expected one order/reservation but preceding expanded sales fixture creates three. Fix only pricing test fixture expectation: assert exact three before and after, compare full ordered order and reservation snapshots after each race, retain actual lock wait, SQLSTATE 23514 and rejection checks. No migration, runtime, ACL, RLS or financial change; later concurrency suites skipped, overall CI not yet verified. Rerun full CI, then actual pre-0058 upgrade fixture and 0059. No operational access.

## TEST-074 — verified / 2026-11-25
- TEST-074 verified FIX-028A run 45628924408 job 139256537477 at 004bacf71c8f7d73f3cd53b11c2750b42d78a2fa success: 58 contiguous migration/test pairs, 67 PASS suites, 86 tables, four ID guards, nine concurrency suites, 24 COGS races. PASS canonical full-return writer, RETURN_WRITER_RACE, RETURN_CAP_RACE and corrected pricing race confirmed. Prior temporal guard/observations retained.

## TEST-075 — candidate / 2026-11-25
- TEST-075 candidate: independent parallel CI job with its own disposable PostgreSQL 16 service, apply exactly 0001–0057, reuse existing 0054 actual ordinary/traced full return fixture with final rollback changed to commit only in temp copy, then apply 0058. Assert two committed legacy headers, five actual return movements and zero receipt lines; compare deterministic exact row snapshots of all user tables before/after migration and authorized legacy retries; negative conflict/trace/permission/cross-tenant checks. New actual full return and exact retry coexist with old history without backfill/refund/valuation change. No runtime/migration/table modifications, no skipped tests. New job pending; after green proceed 0059 read-only reconciliation. No operational access.

## FIX-028B — 2026-11-25
- TEST-076 / FIX-028B: exact TEST-075 run 45630535075 at 5ff26ddc69c7db6821362136b1a9670cd17f3156: foundation job 139262191015 completed SUCCESS (58 contiguous pairs, 86 tables, 67 PASS, all nine concurrency suites, 24 COGS races); independent return-upgrade job 139262189394 failed after UPGRADE_BASELINE committed actual pre-0058 ordinary/traced returns and passed header/movement/empty-line assertions. Snapshot generated SQL referenced to_jsonb(t) without FROM alias; ERROR column t does not exist, before migration 0058. Fix exactly one line by adding AS t to generated SELECT FROM clause. Preserve full all-table comparison, legacy retries, negative tests and new-writer coexistence; no migration/runtime/ACL/policy change. Both jobs must pass before 0059. No production access.

## TEST-077 / REVIEW-027F — 2026-11-25
- TEST-077 partial verification: exact FIX-028B run 45633317796 at 42dd7ea102b417d4026f388dab5c45642cf3f9a9; independent return-upgrade job 139272049466 SUCCESS. Logs UPGRADE_BASELINE, UPGRADE_LEGACY_RETRY and PASS actual 0057-to-0058 upgrade prove two actual committed legacy headers, five return movements, seven units, zero receipt lines before upgrade, exact full-row snapshot equality after upgrade/replay, negative permission/conflict/traced checks and coexistence with one new actual line. Foundation job 139272048763 still in progress; all migrations/SQL/eight concurrency suites successful at observation, COGS pending. Do not claim full run success.
- REVIEW-027F: 0059 plan extends existing finance.order_return_capacity(uuid) only, retaining STABLE SECURITY INVOKER, same signature, owner/ACL, four read/module gates and 0054 exact sale/return ledger validation. Count receipt lines by tenant/order after header/lifecycle checks. Zero-line historical header retains exact ledger fallback (confirmed actual upgrade); nonzero lines require exactly one sellable line per original sale movement with identical return_id/order_id/reservation_id, received_quantity equal positive original return movement quantity, and total line count equal validated movement count. Never sum line quantity plus ledger quantity; preserve existing return capacity output. Use qualified aliases to avoid RETURNS TABLE name conflicts. Unsupported non-sellable/mixed/incomplete evidence fails closed with SQLSTATE 23514, no write or lock. Existing 0058 retry recognizes all-zero lines as legacy; cannot distinguish total privileged deletion/corruption from historical absence without an independent trusted version marker. Ordinary runtime/executor UPDATE/DELETE/TRUNCATE remain prohibited; do not claim detection of privileged wholesale loss. Do not add marker/table/backfill without justified requirement. Existing RLS policy provides full tenant sales-read visibility. Actual historical negative fixture: in separate rollback subtransaction on committed pre-0058 header, insert one valid-cap but incomplete or non-sellable fact via superuser, run capacity under authorized runtime and assert specific mismatch message; do not disable triggers or fake history. Keep original upgrade snapshot and all existing negative tests; extend isolated upgrade job to apply 0059 after original 0058 checks, check exact legacy/new capacity and unchanged rows. No new SQL or grants in review.

## TEST-078 — verified / 2026-11-25
- TEST-078 verified FIX-028B exact run 45633317796 at 42dd7ea102b417d4026f388dab5c45642cf3f9a9: both jobs completed SUCCESS, foundation 139272048763 (58 contiguous pairs, 67 PASS suites, 86 tables, nine concurrency suites, 24 COGS races), actual return-upgrade 139272049466 (committed pre-0058 ordinary/traced returns, exact all-table snapshot comparisons, replay, no backfill, new coexistence).

## BUILD-027E — candidate / 2026-11-25
- BUILD-027E candidate: 0059 replaces only existing finance.order_return_capacity(uuid), same output, STABLE SECURITY INVOKER, existing ACL and four permission/module gates. After original ledger checks, zero-line legacy fallback preserved; when any receipt line exists, require exact sellable line per original movement/reservation/header and matching count, fail closed 23514 for incomplete/non-sellable/mixed evidence; quantities remain ledger-derived, never additive. No new table/function/ACL/writer, no finance or stock mutation. Matching SQL test reuses actual full-return fixture and exact snapshots, existing permission/tenant assertions; extend independent upgrade job after all existing 0058 checks to apply 0059, verify real committed legacy/new coexistence and full-row equality, rollback-only valid-cap short/damaged/mixed/incomplete facts rejected with exact message. 59 pairs/68 PASS/86 tables expected plus upgrade job, CI pending. Total privileged loss indistinguishable from legacy zero-line absence; no unapproved marker/backfill. No operational access.

## TEST-079 / REVIEW-028C — 2026-11-25
- TEST-079: exact 0059 run 45635678490 at ff1fac78740a267e00bd963cda28ee32d377accf, return-upgrade job 139280341078 SUCCESS: 59 contiguous pairs, actual pre-0058 history, snapshot equality, PASS 0059 actual legacy/new reconciliation, RECONCILIATION_REJECTED short/damaged/mixed/incomplete. Foundation 139280341524 migrations/SQL/eight concurrency succeeded; final COGS still running. Do not claim full 0059 approval.

REVIEW-028C — physical partial return dependency audit (no activation):
1. 0007 sales.returns UNIQUE(tenant_id,order_id) and UNIQUE(tenant_id,request_key) currently mean one receipt event per order. 0056 return_items is the existing dependent receipt fact, with unique (tenant,return,movement,disposition), composite same-order/tenant/reservation/movement FKs; 0057 caps aggregate per original sale movement, append-only, READ COMMITTED and exact order lock. Multiple physical receipt events would require changing only the order-level uniqueness while preserving request-key uniqueness and all composite FK targets; never add a second return header or line table. Existing 0058 writer assumes one header and full sellable quantity; 0059 reader selects one header; old replay/valuation 0045/0050 rely on exact key and full return qty. Do not relax uniqueness before every affected caller supports multi-event history; preserve exact legacy API retries and zero-line fallback. Need explicit receipt event semantics and trusted version marker decision before distinguishing missing new lines from historical absence.
2. 0005 warehouses are only tenant-scoped warehouse identities, not disposition buckets. 0025/0027 guard_trace_movement rejects positive expired lot admission, including sales-return namespace, and protects serial evidence. 0027 stock_balances computes on_hand from ledger, usable only from nonexpired lots, then subtracts active holds; no condition for damaged stock. A warehouse named quarantine alone does not exclude availability. Never send damaged/expired goods into ordinary positive stock nor bypass expiry/serial checks. Prefer evaluate extending existing ledger/warehouse semantics with explicit controlled non-sellable location/status, rather than duplicated product/stock balances; compare against independent physical custody/disposition event only if separate lifecycle requires it. No quarantine table or warehouse-kind field chosen yet. Review every reserve/consume/transfer/adjustment/trace/analytics/valuation path before enabling any non-sellable movement. Prevent serial simultaneous sellable and quarantined custody.
3. Physical receipt, disposition and custody, saleable ATP, COGS/asset value, and refund are different facts. A damaged/expired receipt is not proof of a saleable stock increase, financial reversal, or refundable amount. For now only full inspected sellable returns are operational. Do not change sales.orders terminal states or financial postings until lifecycle design covers partial physical receipts vs fulfillment/payment/refund independently; derive quantities from existing events rather than duplicate totals/status masters.
4. 0007 sales.refunds UNIQUE(tenant_id,payment_id), exact full capture amount/currency and state gating; 0050 reverse_inventory_cogs expects full original sold movement and returned/refunded order, exact full-return ledger key. Partial refund requires independent approved allocation/cap of captured amount, discount/tax/shipping, provider idempotency and charge/settlement chronology; never reuse supplier settlement as customer refund. Partial valuation requires owner decision on FIFO layer reversal, moving-average rounding, impairment and write-off, period cutoff and commit-time module expiry. No financial activation or removal of constraints.
5. Next implementation gate: after both 0059 jobs green, first audit all latest references to sales.returns, sales.refunds, stock_balances, available_units, trace_held and sale-return key. Write a read-only lifecycle/capacity contract and regression matrix for multiple receipts across same/different keys, concurrent aggregate caps, exact serial, expiry boundaries, tenant isolation, no saleable inflation, no refunds/COGS writes, legacy retry. Only synthetic structural changes consistent with approved scope; owner approval before enabling new physical disposition/quarantine/valuation/refund rules. No 0060 allocated by this review.

## TEST-080 / REVIEW-028D — 2026-11-25
- TEST-080: exact 0059 run 45635678490 at ff1fac78740a267e00bd963cda28ee32d377accf, both jobs SUCCESS: foundation 139280341524, upgrade 139280341078. 59 contiguous migration/test pairs, 86 tables, 68 PASS suites, all nine concurrency suites and 24 COGS races. Actual committed legacy/new reconciliation and negative short/damaged/mixed/incomplete cases passed, snapshots unchanged.

REVIEW-028D — scanned all 59 ordered SQL migrations at 8aed719b0c28eb37db6a7bf7787287621e20b4f6 for literal references to sales.returns, sales.refunds, stock_balances, available_units, trace_held, sales-return:. This is a migration-level dependency inventory, not a complete dynamic application or transitive call graph.

| Existing area | Relevant migrations and canonical paths | Required compatibility gate |
|---|---|---|
| Sales receipt and identity | 0007 header/refund uniqueness, 0027 inventory.return_fulfilled_reservation, 0056 line FKs, 0057 sales.guard_return_item_quantity, 0058 sales.receive_full_return_allocated | preserve request-key idempotency, exact payload and same-order serialization; independent receipt events only after compatible readers; never loosen cap or legacy key behavior |
| Saleable stock | 0005 inventory.available_units and assert_pair; 0024 transfer_stock; 0025 guard/adjustments; 0026 transfer_allocated; 0027 trace_held, guard_trace_movement, reserve_stock_internal, consume_reservation_internal, stock_balances | no damaged/expired increase of ATP; preserve exact serial custody, expiry and tenant guards; quarantine cannot be warehouse naming alone |
| Customer refund | 0007 sales.record_full_refund, 0008/0009 finance.post_refund, journal source FK | preserve exact capture/refund cap and provider key; separate physical receipts from money, approved allocation before partial refund |
| Valuation | 0034/0035/0037/0038/0040 historical reversal and replay, 0041/0042 readiness, 0044/0047/0048 replay prefix, 0045 tracked_movement_evidence, 0049/0050 inventory_cost_issues, 0050 reverse_inventory_cogs and replay_valuation_prefix | do not assume a single return header or full quantity for new lifecycle, preserve exact original sale provenance and legacy full reversal; no cost posting until approved |
| Period and evidence | 0052 guard_inventory_period_mutation, 0054/0059 finance.order_return_capacity | preserve period close barrier and four read/module gates; existing capacity remains full-return only; no double count |

Proposed read-only lifecycle contract (not an active API): for each original sale movement, sold = negative canonical sale quantity, physical_received = sum of immutable receipt lines across all valid receipt events, physical_remaining = sold - physical_received, and classification sums = sellable/damaged/expired. All quantities tenant and order scoped, nonnegative, aggregate <= sold. Historical zero-line full receipts derive physical_received from validated return movement, never add ledger and lines. New sellable physical receipt is not saleable ATP until validated stock admission; damaged/expired classification is not a stock movement or a financial posting. Custody balance is not simply lifetime receipt count: subsequent authorized disposition needs its own evidence, without rewriting receipt lines. No partial operational writer is authorized by this contract.

Regression matrix for next synthetic development:
- Multiple distinct receipt events against same original movement: sum within cap accepted in isolated fixture, over-cap rejected atomically; request key exact replay stable, conflicting payload rejected, same-order/different-key races serialize, cross-tenant and wrong-reservation/movement FKs fail.
- Lot/serial: exact original allocation, serial quantity one, no simultaneous saleable/quarantine custody, expired positive admission remains blocked; no oversell, no inventory change merely from classification.
- Legacy: actual committed 0057->0058->0059 history, exact replay unchanged, zero-line fallback, incomplete/mixed fail closed; no backfill and no double count.
- Financial: no receipt-only refund/journal/COGS posting; one-payment uniqueness and full-refund/reversal guards remain. Future policy tests need independently approved net refund caps, tax/discount/shipping, FIFO and moving average reversal, impairment, late cost and commit entitlement boundaries.
- Access and failure: runtime direct DML denied, tenant and module isolation, append-only, exact rollback, period barrier retained. No production deployment.

Next 0060 should be a synthetic-only safety prerequisite, not an unapproved partial writer. Candidate: assert existing live entrypoints deny non-sellable and partial requests and no side effects, and audit latest pg_proc/pg_depend definitions for transitive dependencies. If a real structural prerequisite can be shown without policy change, implement incrementally; otherwise stop at explicit owner decisions on physical custody/quarantine and financial policy. No duplicate master or parallel API.

## BUILD-028E — candidate / 2026-11-25
- BUILD-028E candidate: discovered 0026 inventory.normalize_allocations uses jsonb_to_recordset with four named columns, silently discarding unknown allocation properties. Existing 0058 full-return writer could interpret exact traced allocation plus disposition=damaged/expired as sellable. 0060 replaces only existing sales.receive_full_return_allocated with strict return-specific array/object and allowed-key validation (variant_id,lot_id,serial_id,quantity), before request/order locks and replay; no global normalizer change, valid documented payloads unchanged, unknown properties including explicit sellable disposition now rejected 22023. Tests use actual fulfilled traced order, reject damaged/expired/sellable/unknown properties, partial allocation, expired positive admission, compare order/return/line/stock/refund/journal snapshots, valid full return and same-key replay, invalid replay rejected; previous capacity/tenant checks retained. No new table, ACL, policy, partial writer or finance change. 60 pairs/69 PASS/86 tables expected plus existing actual upgrade job; CI pending. Caller compatibility note: formerly ignored extra JSON fields now fail closed; callers must send documented four keys only. No operational access.


## TEST-081 / REVIEW-029 — 2026-11-25
Exact verified baseline: 1da3f256fe310ce61fe6b9cc0f756a90c069bf4a; [run 45638979449](https://github.com/mohamadhajabbasi-dev/unified-platform-core/actions/runs/45638979449), foundation 139292029109 SUCCESS and return-upgrade 139292029988 SUCCESS. Logs: 60 unique contiguous migration/test pairs, 86 tables, 69 PASS suites, four numbering tests, all nine concurrency suites including 24 COGS races; actual committed pre-0058 ordinary/traced history replay and upgrade passed. 0060 strict four-key allocation validation precedes normalization/replay; explicit damaged/expired/sellable and unknown keys, partial traced return and expired admission rejected; unchanged order/return/line/stock/refund/journal facts and valid exact replay.

57 groups: 22 verified prototype, 12 partial, 23 not implemented. Counts classify groups, not percentage of database completion; some groups overlap (e.g. parties, distribution, tax submissions), and verified means relevant structures and baseline CI exist, not every field, policy or operation is validated. All 60 migration texts scanned for CREATE TABLE, ALTER move/rename, DROP, functions/views; selected definitions and 0060 acceptance/logs reviewed. No independent exhaustive column/ACL/call graph or load audit.

Open gates: module entitlement expiry after function returns and before COMMIT; inventory recorded_at before period barrier acquisition (0055 and actual COGS observations, not fixed). Retain exact existing tests; resolve only with owner-approved temporal policy and deterministic transaction/lock tests. Partial/non-sellable physical custody, quarantine, refund/valuation policy remain blocked; full return path unchanged. No production, legacy access, or final policy activation.

Next: REVIEW-029A — core dependency design for tenant business locations and site/domain registry: compare core tenant addresses/settings, inventory warehouses, analytics sessions/events and platform applications, canonical relationship/uniqueness/RLS/ACL and tests; design one tenant child per genuinely distinct concept, no duplicate store/warehouse/site master. Only then allocate 0061 if justified. Parallel policy-gated backlog (not implement concurrently): counterparty roles and identity before bank/cheques/AR/settlement/installments; shipping and delivery; fiscal invoice/tax (owner approved legal/financial policy); CRM tags/queues/favorites/alerts, licensing/auth security (owner policy), analytics/notification/outbox/workflow/AI/ops backup/restore/load. No new table solely on dictionary label.


## REVIEW-029A — 2026-11-25 (design only)
- Reviewed exact 0001/0002/0005/0011/0012/0014/0016 dependencies and target ERD/tenant identity requirements at aaf1bf5e490e36b6412b513f1956d32b0f9a8612. New issue: core.tenant_settings.website_host already exists; do not create parallel authoritative host. Existing dossier audit target selection does not support location_id; extend existing function in future migration, no second audit.
- [Branch/site design and concrete acceptance matrix](../docs/BUSINESS_LOCATION_SITE_DESIGN_FA.md): minimal proposed 0061 physical branch/store identity referencing existing tenant address, no warehouse/site/product/customer copy; no warehouse-to-location cardinality assumed. Site registry deferred to separate compatibility and owner security policy gate; no DNS/routing activation.
- Latest observed checkpoint CI 45641015000 at aaf1bf5e490e36b6412b513f1956d32b0f9a8612: return-upgrade 139299347939 SUCCESS, foundation 139299347881 IN_PROGRESS (sales concurrency observed); no new DDL or test files. Last fully verified code baseline remains 0060, run 45638979449. First next action verify BOTH jobs at 45641015000; if success implement minimal 0061 and exact negative/real concurrency tests; if failure repair only actual cause first. Open temporal and financial gates unchanged. No production/legacy access.


## TEST-082 / BUILD-029B — 2026-11-25
- Verified exact 0060 checkpoint SHA aaf1bf5e490e36b6412b513f1956d32b0f9a8612, run 45641015000 SUCCESS, foundation 139299347881 and return-upgrade 139299347939 SUCCESS; logs 60 contiguous pairs, 86 tables, 69 PASS suites, 24 COGS races. Reviewed current HEAD c88c0afd092089987915a67a749641ae21090339.
- Authored 0061_business_locations.sql with one physical business-location child, tenant-scoped immutable identity and composite existing address FK, RLS/ACL, exact existing audit writer target extension. No warehouse/host/site/stock/order changes. Address binding additionally requires existing tenant.legal.read; server generates ID/timestamp; location_kind immutable. Explicit location-key conflict, not silent retry or API idempotency; runtime create retry requires future reviewed exact-payload contract. Non-null address on UPDATE requires legal read (including other field updates); address text remains protected. No grant to new permissions except synthetic tests. Metadata only; no module or sales activation.
- Matching rollback SQL test and real competing unique-index write shell test added; workflow adds one step before COGS, existing suites unchanged. Candidate expected 61 migration/test pairs, 87 tables, 71 PASS (61 SQL + 10 concurrent), plus independent return history upgrade. Runtime CI PENDING. No production or legacy access. Temporal expiry/pre-barrier timing, partial/quarantine/refund policy unchanged.


## TEST-083 / REVIEW-029B / BUILD-030A — 2026-11-25
- TEST-083: exact 0061 run 45643530975 at 27faa6a220cf327a2d60047c6b63cedd97aaca1a SUCCESS, foundation 139308257824 and return-upgrade 139308258268 SUCCESS; logs 61 contiguous pairs, 71 PASS suites (61 SQL + 10 concurrent), actual unique-index contention and SQLSTATE 23505, one location and one exact audit, 24 COGS races, actual return history upgrades. 87 base tables derived from DDL inventory (86 earlier + one location relation); prior log numeric 86 was a module decision ID, not a direct runtime table-count query. 0062 test adds explicit catalog count diagnostic.
- REVIEW-029B: literal scan of all 61 migration files and 74 SQL/shell test files at exact 27faa6a220cf327a2d60047c6b63cedd97aaca1a for website_host, site_id and domain_host: only website_host definition (0011 line 64) and UPDATE grant (line 149); no existing literal caller or site master in these files. Generic SELECT */row shapes and future external clients are not proven compatible. Existing informational host allows duplicates across tenants and cannot be trusted for routing. No automatic host import, claim, normalization, removal or dual-write. Domain ownership/verification/reassignment/activation/expiry/security policy remains owner-gated.
- BUILD-030A candidate: 0062 adds only immutable dormant core.sites identity (tenant, generated ID, stable tenant-key, display name, server timestamp), no host/domain, address, warehouse, application, order, event or active flag. Reuses existing IAM/RLS and ops.record_dossier_change; no runtime DML, non-login scoped executor and exact-payload idempotent registration under advisory lock, READ COMMITTED. Metadata does not require commerce entitlement, does not enable commerce, cannot route or collect data; any future activation/analytics must require approved policy and platform.commerce_eligible. No existing roles receive new permissions. SQL and actual two-waiter concurrency tests added; existing tests unchanged. Expected 62 pairs/73 PASS and 88 base tables, CI PENDING. No operational access.
- Open: module expiry after return before COMMIT; pre-barrier recorded_at; partial/quarantine/refund/valuation policy; location exact-retry API still pending. No production access. Next verify exact 0062 CI both jobs and update counts, then advance independent CRM/catalog favorites/tag or counterparty/financial design while domain security policy remains gated.


## TEST-084 / FIX-030A — 2026-11-25
- Exact candidate fff251e1db599a9e1958c896b199c44c392499d2, run 45647070040: FAILURE; return-upgrade 139320797126 SUCCESS; foundation 139320797944 FAILURE at synthetic acceptance test 0062. Migration numbering and all 62 migrations applied; earlier SQL tests through 0061 passed. All 11 concurrency steps skipped. Log: `ERROR: column "s" does not exist`, PL/pgSQL inline block line 13, first JSON snapshot. No complete 0062 acceptance or table-count evidence.
- Root cause: missing table aliases in before/after `jsonb_agg(to_jsonb(s))` for core.sites; same defect statically identified for `to_jsonb(e)` on ops.audit_events. Add explicit aliases s/e and qualify sort columns in both snapshots (four replacements). Preserve full rows, stable ordering, equality assertion and all positive/negative tests. No changes to applied migration, functions, policies, privileges, workflow or race script. New CI pending; last fully verified baseline 0061 run 45643530975. No new migration; next unused 0063 only after both jobs PASS. No operational or legacy access. All domain ownership, temporal, financial, custody and location retry gates preserved.


## REVIEW-030B — 2026-11-25 (design only)
- HEAD 843483533613e7d577cb6953d4f0c51827cf3247; exact correction run 45649134004 observed return-upgrade 139328451042 SUCCESS, foundation 139328451364 IN_PROGRESS at final COGS concurrency; synthetic acceptance including 0062 and prior 10 concurrency suites plus site race completed SUCCESS per job steps. Full CI and explicit runtime catalog count not yet verified; last fully verified baseline remains 0061, counts unchanged.
- Reviewed 0001/0003/0013/0015 CRM/catalog contracts, canonical dictionary, legacy DbSet inventory (CrmTags/merge/queues/SLA/favorites/stock alerts), 0052/0055 temporal guard context and 0062 audit/executor shape. Prepared docs/CRM_CUSTOMER_TAG_DESIGN_FA.md: one tag master and one unique relationship to existing customer, exact retry and no direct runtime DML, module/CRM read/write scope, shared audit and concurrent acceptance. No merge, pricing, marketing consent, credit or access policy inferred from tags. No new SQL/tests/workflow or approved policy; next unused 0063 pending full 0062 PASS and technical review.


## TEST-085 / BUILD-030B — 2026-11-25
- TEST-085: exact correction SHA 843483533613e7d577cb6953d4f0c51827cf3247 run 45649134004 SUCCESS; foundation 139328451364, return-upgrade 139328451042 both SUCCESS. Logs: 62 contiguous pairs, 73 PASS suites, direct catalog count 88 base tables, site exact retry with two actual advisory waiters, conflict 23505 and one audit; 24 COGS races. Site/domain group now PARTIAL, not complete domain lifecycle. 23 verified prototype, 13 partial, 21 not implemented.
- Prior design commit e4a7eb9f3852323322f0e14366c35be0721e359b existed in GitHub but main update repeatedly returned GraphQL server errors/ReadTimeout. Reuse that exact commit as parent (no duplicate design), advance main from verified ancestor only, no force. Verify ref after mutation. If not advanced, report NOT_PUSHED and retain candidate SHA.
- BUILD-030B: 0063 customer_tags/customer_tag_links candidate only, 2 normalized relations linked to existing customer PK, no duplicate customer/consent/pricing. Existing CRM module and crm.read plus dedicated tag ACL, nonlogin executor, no direct runtime DML, shared audit. Exact create and state replay, detach absent no tombstone, same relationship identity on reattach. Real duplicate create and attach contention test; no claim historical command exactly-once, no concurrent opposing-state test yet. 0052 period barrier protects financial paths and module decisions; tags have no financial effects and use existing statement-time permission/module checks, no commit-time policy change. Free-text name normalization limited to lower(btrim), no sensitive semantic classification/retention or operational activation. Expected 63 pairs, 75 PASS, 90 tables after CI; pending verification.
- Open: domain ownership/activation, location retry, merge review, customer-self authorization, module expiry after return/pre-COMMIT and pre-barrier recorded_at, partial/non-sellable custody/refund/valuation. No legacy or operational access. Next verify both exact 0063 jobs, then continue independent requirements (favorites or queues) only after success.


## TEST-086 / FIX-030B — 2026-11-25
- Checked main 843483533613e7d577cb6953d4f0c51827cf3247 and candidate branch upc-0063-crm-tags at 7e2edab04a223800a833046bd963bba357de8606. Exact run 45650762864 FAILURE: foundation 139334309102 failed at 0063 acceptance, return-upgrade 139334309532 SUCCESS. All 63 migrations applied and prior SQL through 0062 passed; all 12 concurrency steps skipped. Log `ERROR: FAIL detach retry`, inline DO block line 11. Last fully verified baseline remains 0062 (62 migrations, 73 PASS, 88 runtime tables). No 0063 coverage promotion or main merge.
- Failure localization: old assertion combined two volatile state-changing calls and a table subquery in one OR expression; PostgreSQL does not guarantee evaluation order, and an expression subquery may observe the pre-mutation snapshot. This is the leading test defect hypothesis, not yet demonstrated as sole cause; actual log did not distinguish returned ID from persisted state. Correct acceptance test by sequencing attach/detach/replay/reattach calls separately from independent state and ID assertions. Strengthen replay checks with full-row equality (including timestamps), preserve all exact audit counts and negative/rollback/module/ACL checks. Migration, functions, workflow and existing concurrency script untouched. If corrected CI fails, diagnose actual failing assertion/implementation; do not relax acceptance.
- Prior direct main fast-forward failures remain; keep correction on upc-0063-crm-tags (or explicit successor branch if connector refuses ref update). Verify remote ref and exact CI; no main promotion until success. Do not allocate 0064 yet. Domain ownership, financial/temporal, merge, sensitive label retention, self-authorization gates unchanged. No operational or legacy access.


## TEST-087 / REVIEW-031B — 2026-11-25
- TEST-087: exact 0063 correction 6416975751ad8c178844ef6425d391ea9364eb2b, branch upc-0063-crm-tags-fix, run 45651092876 SUCCESS; foundation 139335469451 and return-upgrade 139335469186 SUCCESS; 63 contiguous pairs, 75 PASS suites (63 SQL + 12 concurrency), actual catalog count 90 base tables; observed CRM tag create and attach lock waits, exact IDs and audit counts, conflict rejected; 24 COGS races. Tag/merge group PARTIAL (merge absent). 57-group classification 23 verified prototype, 14 partial, 20 not implemented. Counts verified on candidate branch, NOT main. Main verified 0062 (62 migrations, 73 PASS, 88 tables).
- PR #1 open; direct main update failed with GitHub GraphQL error; normal merge attempts timed out/internal error. Main checked at 843483533613e7d577cb6953d4f0c51827cf3247. Exact PR run 45652606889 status in_progress, conclusion pending. Return-upgrade passed and foundation reached final COGS in last job inspection. PR checkpoint comment 7167869959 confirmed remotely. No claim of main promotion.
- Durable documentation checkpoint based on verified candidate only; preserve existing PR head to avoid invalidating CI. New docs/CRM_SERVICE_QUEUE_DESIGN_FA.md specifies minimal queue identity, nullable composite FK on existing tickets, explicit legacy INSERT column allowlist, protected assignment and exact replay, row-lock tests, committed prior-history upgrade, audit scope. All 63 migration files previously scanned for literal support_tickets/service_queues/sla_policies/support_feedback; only 0013 ticket references; not an exhaustive semantic/external caller audit. No 0064 SQL, tests or workflow change. No new commercial, access, routing, SLA or retention policy. No legacy or production access.
- Next: verify PR #1 and exact CI; promote tested tree preserving history, verify main; reconcile this documentation checkpoint by exact content/ancestry (do not redo tag implementation or duplicate docs); only then allocate 0064. Prior temporal, financial, custody, domain, merge, privacy and customer self-auth gates remain.


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


## TEST-096 / BUILD-035 — 2026-11-25 (0068 candidate, NOT MAIN)
- Verified exact main 0067 merge `69ca58b6d0862883aaad252c32bb0c733ef4b44a`, run 45693332423 SUCCESS: all seven jobs, 67 contiguous pairs, 83 PASS suites, 94 PostgreSQL base tables, pre-0067 upgrade and COGS contention retained.
- Branch `upc-0068-reorder-config` from that exact main merge: reused REVIEW-035 reorder design; scanned 0005 inventory/0022 procurement and path-scoped code searches before adding one dependent dormant `inventory.reorder_policies` table, not a second stock balance/purchase order. Composite same-tenant warehouse/variant FKs; positive whole units, nonnegative threshold; dedicated unassigned permission and NOLOGIN executor, minimum RLS/ACL, physical-variant check, tenant-key lock, exact same-state replay, updated-state audit via existing ops writer. No stock posting/procurement automation/price or cost change.
- Tests: matching 0068 SQL acceptance with tenant, deny-by-default, permissions, full-row replay/audit/rollback; actual observed two-session create and opposing update contention; independent committed pre-0068 upgrade based on actual purchase-receipt/stock/reservation fixture; existing suites unchanged. Separate CI reorder-upgrade job and one new foundation concurrency step. Expected 68 SQL pairs / 85 total PASS suites / 95 base tables after SUCCESS; candidate not yet verified. Exact candidate workflow run 45694773849 was IN_PROGRESS at last check; reorder-upgrade and old upgrade jobs completed SUCCESS, foundation/COGS pending.
- Open policy gates: reorder threshold basis (available vs on_hand), lead times, request approvals, automatic procurement; 0055 module expiration/commit and pre-barrier timestamp observations; damaged/partial returns/custody/refund/valuation, domain activation, privacy. No operational or legacy database access.


## TEST-097 / REVIEW-036 — verified main 0068 (2026-11-26)
- Exact main `4d30eab9c0fbb689b57618e5c600f78ee2798018` verified directly through GitHub branch, merged PR #9 and run 45696627212: completed SUCCESS, all eight jobs (foundation, cogs, queue/category/barcode/attribute/reorder/return-upgrade) SUCCESS. PR run 45695839631 completed SUCCESS at head 2bf4c59cabf584b8b194dd766ba183f58051c6da. No open PR at review time.
- Foundation job 139495607774: 68 unique contiguous migration/test pairs, 84 PASS markers, measured 95 base tables, actual reorder lock waits and serialized differing updates, exact audit, no stock/procurement effect. COGS job 139495607681: one PASS, 24 races; total 85 suites. Reorder upgrade 139495607634: exact committed pre-0068 stock/reservation/purchasing/permission/catalog facts preserved; no backfill or automatic procurement.
- Reconciled the 57 dictionary rows using prior 0060 comprehensive migration inventory, subsequent verified 0061–0068 deltas, exact current untruncated migration tree, and current CI evidence. Reorder group N→P; category/attributes/barcodes still P (label lifecycle missing). Counts: 23 verified prototype / 16 partial / 18 not implemented, not a completion percentage. This is incremental coverage reconciliation, not an independent exhaustive field/call-graph/ACL audit.
- Open temporal issues remain explicitly observed in main COGS logs: module expiry after function return before COMMIT; stock DEFAULT recorded_at preceding close despite later writer commit (no cutoff crossing proven). Partial/damaged/expired return, custody/refund/valuation, domain activation, CRM privacy, reorder basis/lead times/approval/automatic procurement remain gated. No operational or legacy change.
- Next priority selected for review: shipping/delivery group, dormant tenant shipping-method identity as a possible independent increment; inspect all existing migrations for equivalent relation and audit paths first. No rates, routing, dispatch, order state change, payment/tax effect or activation without policy. Allocate 0069 only after justified non-duplication review. Existing main is verified, checkpoint changes are documentation-only; promotion requires exact branch and PR CI before merge, then main CI. No 0069 SQL in this checkpoint.


## BUILD-036 — 0069 dormant shipping identity candidate (2026-11-26)
- REVIEW-036 scanned all 68 pinned migration texts for shipping/carrier/dispatch/delivery/fulfill/freight/courier; reviewed existing fulfillment, procurement receipt, legacy field evidence and canonical matrix. No shipping method master found. See docs/SHIPPING_METHOD_DESIGN_FA.md. Candidate adds exactly one tenant-scoped dormant identity, not a second order or fulfillment, no automatic operation, new permission unassigned. Site association, rates, zones, carrier/tracking and dispatch policy remain open.
- Added matching SQL test, concurrent exact-key replay/conflict test, committed pre-0069 sales-history upgrade, one foundation step and one separate shipping-upgrade job. Expected 69 pairs / 87 PASS suites / 96 tables / 9 jobs; NOT verified pending exact candidate CI. 57 group counts unchanged (23/16/18); shipping group remains PARTIAL. Existing migrations/tests unchanged.
- Documentation-only TEST-097 commit 1d777968473a0c0282c296c7ba7c7e7862516543 did not trigger CI because workflow path filter is db/** and workflow only; carry that checkpoint in the same candidate branch and promote once with exact 0069 branch and PR CI, no standalone doc PR needed. Main remains verified 0068 4d30eab9c0fbb689b57618e5c600f78ee2798018. Next inspect exact candidate all nine jobs and fix actual failures only; open PR after branch success, verify exact PR CI, merge then verify exact main. No 0070 or operational changes before gate.


## TEST-099 / REVIEW-037 / BUILD-037 — 2026-11-26
- Exact main 0069 `552fd8a7fc51dbe9ca8bba3ca0108adee395f6c2` verified SUCCESS run 45700468348 all nine jobs. Foundation 139508909837: 69 contiguous pairs, 86 PASS, measured 96 base tables, two observed advisory waiters and exact shipping retry/conflict/audit. COGS 139508909926 one PASS/24 races, both previous temporal observations unchanged. Shipping upgrade 139508909802 exact committed prior rows preserved. Branch 45698024671 and PR #10 run 45699020326 both 9/9 success; merge tree matched tested candidate. Earlier candidate fdeee4736704a5b12c90f7909354cb6a7eea792e run 45697987671 foundation failed FAIL invalid name due to double-escaped control characters in test, corrected in 624050e5ef6a62cf876aaeb0062cb63b54a48eca, no weakened assertion. 69/87/96 confirmed.
- Coverage remains 23 verified prototype/16 partial/18 absent for verified main; shipping group P, now includes dormant identity. Financial review: existing procurement.counterparties and finance.accounts/journals/supplier_settlements must be reused; bank identity protection, legal role/authority, bank-to-ledger mapping and financial posting/reconciliation rules remain policy gated. Do not allocate a parallel party/account master or assert financial policy.
- REVIEW-037: scanned all 69 pinned migration texts for incident/health/monitor/crash/alert/outage/telemetry; only shared app analytics/official distribution telemetry references found, no operational incident identity. Reviewed 0011 audit and 0016 analytics. Owner requirements specify per-tenant health/security status and incidents. One dormant tenant report relation ops.incidents; audit records the registration, not another incident master; no raw logs, telemetry or attack detection. Technical prototype category availability/security and opaque UUID report key, not proof of actual outage or attack, server report timestamp not occurrence time. No automatic correlation, status/severity, closure, retention, system-wide monitoring or notifications. Separate read/write permissions unassigned; cross-module scope like audit, not a new module or grant. No production access.
- BUILD-037: authored 0070 additive SQL, matching acceptance test, actual contention script, committed pre-0070 sales/shipping/audit upgrade and one CI step/job. Expected 70 pairs, 89 suites, 97 tables, 10 jobs, UNVERIFIED until CI. Group health/incident N→P only after exact main success. Next inspect candidate branch run for exact head; if failed fix real cause, then PR and exact PR/main CI before 0071. All previous open policy issues remain; no change to old SQL/tests.


## TEST-101 / REVIEW-038 / BUILD-038 — 2026-11-26
- Verified exact main 0070 `0f89fd4a55114b4c607fe8bf381cca1cb1bd6eea`, PR #11 merged, tree matched tested candidate 23090530130ee4175090bbe2f9b0954cbca349b5. Branch 45770566328 and PR 45771590235 all ten jobs SUCCESS; exact main 45772502903 all ten SUCCESS. Foundation 139748232202 logs 70 contiguous migration/test pairs, 88 PASS, measured 97 base tables, two observed incident advisory waiters, same-ID replay, conflict and one audit. COGS 139748232359 one PASS/24 races; both 0055 temporal observations remain unresolved. Incident upgrade 139748232496 exact committed prior orders, inventory, shipping metadata, audit and all prior table rows preserved. Total 89 suites. No open PR at review.
- Reconciled 57 group matrix incrementally: health/incident N→P (0070 report-only, not confirmed incident detection/lifecycle/metrics); 23 verified prototype / 17 partial / 17 absent. Not a completion percentage. No other classifications changed; old policy gates remain.
- REVIEW-038 scanned all 70 pinned migration texts for backup/restore/snapshot/archive/PITR/recovery, found only unrelated inventory/pricing snapshot, archived articles and cost restoration. Reviewed target ERD, master and requirements, 0002 platform staff/approver and 0011 shared audit. Owner requires per-tenant backup/restore separated from whole-platform and code backups. No previous tenant backup request registry. Design adopts one immutable request-only ops.tenant_backup_jobs; no success/status/worker/storage fields, no actual backup. Unique opaque global request UUID binds one tenant and actor; exact retry only, cross-tenant/actor conflict; timestamp is request not snapshot. Restrict prototype to active platform superadmin and no mapped tenant, existing upc_platform_approver entry role, no direct table access, narrow non-login executor and audit insert policy; list requires explicit tenant. No tenant/other staff grant or new role master, no restore authorization. No real server/legacy/production access.
- BUILD-038 candidate 0071 adds SQL, synthetic authority/ACL/replay/audit/rollback test, observed lock concurrency test and committed pre-0071 upgrade; one extra foundation step and separate upgrade job. Expected 71 pairs / 91 suites / 98 tables / 11 jobs; UNVERIFIED until CI. Existing migrations/tests unchanged. Backup group remains N until exact main success, then P only. Next inspect exact candidate CI, fix genuine failure, PR, exact PR CI, merge, exact main CI before 0072. Open design gates: encrypted external storage, artifact integrity, retention, RPO/RTO, capture consistency, tenant FK graph, restore isolated staging/reconciliation, explicit approval and rollback, separately authorized code/full DB backup. Never full-DB PITR for a single tenant, never publish backup contents. No operational activation.


## TEST-103 / REVIEW-039 / BUILD-039 — 2026-11-26
- Exact main 0071 `a46f37b60225b68ea3229f214d97cbf23a02fcaf`, merged PR #12, tree matched tested 957e235204f59c3337e9553d646ff0b8747e86c4. Branch run 45773697132, PR 45774872371, main 45775889991 all 11/11 SUCCESS. Foundation 139759325787: 71 contiguous pairs, 90 PASS, 98 measured tables, observed two backup-request advisory waiters, exact retry/cross-tenant 23505/one audit; COGS 139759325939 one PASS/24 races, previous two temporal observations remain. Backup upgrade 139759325818 exact prior rows preserved. 91 suites, no open PR. Backup group N→P, request-only; 23 verified prototype / 18 partial / 16 absent of 57, not completion percentage.
- REVIEW-039 scanned all 71 pinned migration texts for favorite/favourite/wishlist/stock_alert/bookmark, no equivalent relation. Reviewed 0015 product_reviews and 0063 tags, 0001/0004 canonical keys, legacy EF coverage and target requirements. CustomerFavorites is distinct from review/tag/cart; no duplicate customer/product. Selected product-level favorite relation rather than variant/site duplication; only internal synthetic tenant operator path with CRM/catalog read permissions, both active modules and separate unassigned favorite read/write gates. Not customer self-service/authentication, behavioral tracking, advertising, alerts, stock/price mutation, or proof of customer consent. Retention/erasure, verified customer authority and public application integration remain gated; inactive row is a prototype choice, not final retention policy.
- BUILD-039 candidate adds catalog.product_favorites and set_product_favorite, composite tenant FKs, one persistent customer/product pair, no absent false creation, same-state retry, reactivation, minimal executor column access, shared audit. SQL/observed contention/committed-history upgrade, one foundation step and extra upgrade job. Expected 72 pairs / 93 suites / 99 tables / 12 jobs, pending exact CI; catalog review/favorites/alerts group stays partial. Existing migrations/tests unchanged. Next check exact branch CI, fix genuine failures, PR, exact PR/main CI before 0073. All previous security, financial, privacy and backup policy gates remain; no production/legacy access.


## TEST-105 / REVIEW-040 / BUILD-040 — 2026-11-26
- Exact main 0072 `d2afd1c1f1cc0d6a8d280661e520bed2a0e794f6`, merged PR #13, tree matched candidate 9818718504ae90dfaeb00dd6e1597c1201406d3e. Branch run 45777406472, PR run 45778467411, main run 45779491004 all 12/12 SUCCESS. Foundation 139771225217: 72 contiguous pairs, 92 PASS, 99 measured base tables, favorites composite tenant keys, module/permission gates, exact retry/rollback/audit and two observed advisory waits. COGS 139771225107 one PASS/24 races, both prior temporal observations remain unresolved. Favorites upgrade 139771225060 exact committed prior rows preserved. 93 suites, no open PR. Coverage remains 23 verified prototype / 18 partial / 16 absent. Catalog reviews/favorites/alerts row remains P.
- REVIEW-040 relies on pinned 0071 full inventory scan (71 migrations, favorite/wishlist/stock_alert/bookmark) and reviewed sole 0072 delta: no existing restock request relation. Legacy coverage lists ProductStockAlerts separately from CustomerFavorites. Reviewed 0004 canonical variant keys, 0005 stock ledger and inventory permission/module, 0013 existing consent events, 0072 favorite relationship, 0068 reorder scope. Stock restock interest is not stock, reorder policy, favorite, notification or consent. Prototype variant-level because stock is variant-scoped; no product/warehouse/channel mirror or stored quantity. One request relation per tenant/customer/variant, is_requested only, no delivery status, recipient/contact, threshold or trigger, no consent inference. Conservative internal-only CRM/catalog/inventory read and active module gates plus separate unassigned stock alert read/write permissions; final scope and retention need owner approval. Existing consent evidence remains canonical and unmodified; no message dispatch, consent activation, stock allocation or subscription billing.
- BUILD-040 candidate adds catalog.stock_alert_subscriptions, set_stock_alert_request, composite tenant FK, stable ID/request-state idempotency, shared audit, limited executor columns, forced RLS. Synthetic tests include foreign variant/customer, separate inventory permission/module denial, unchanged consent/favorites/stock, observed actual locks, committed 0072 favorite and other prior rows upgrade. Adds one foundation step and extra upgrade job. Expected 73 pairs / 95 suites / 100 base tables / 13 jobs, UNVERIFIED until exact CI. Coverage remains 23/18/16 (group remains partial pending consent/notification lifecycle). No old migration/test changes. Next check exact branch CI, fix genuine failures, PR, exact PR and main CI before 0074. All earlier privacy, backup, financial and security gates remain. No production/legacy access.


## TEST-106 / FIX-040 — 2026-11-26
- Exact candidate 31cee87b583ef3e9c54470d6bdf61ebada2a4beb, push CI 45781793815: foundation 139778771298 FAILED at synthetic 0073 SQL `DO $ BEGIN`, SQL syntax error, exit 3. Eleven upgrade jobs SUCCESS including stock-alert-upgrade 139778771323; COGS in progress at review. Root cause: JavaScript replacement-string dollar escaping in generated test, three opening delimiters and two closing delimiters collapsed from double to single dollar. Fix ONLY these five test delimiters using literal callback replacement; no assertion removed, no permission or migration logic changed. Inspect exact corrected CI before PR. Main remains verified 0072 d2afd1c1f1cc0d6a8d280661e520bed2a0e794f6, 72/93/99, 12 jobs, coverage 23/18/16. Candidate 0073 still unverified. No production or legacy access.


## TEST-108 / REVIEW-041 / BUILD-041 — 2026-11-26
- Exact main 0073 `1493839024fef6623a6fec0d41a5652f0c2a98fd`, merged PR #14, tree matched corrected candidate 7875053376916dad7d6cab6c9b0a080b3b2c8d8d. Original failed run 45781793815 syntax-only test delimiter fix recorded TEST-106. Corrected branch 45782347480, PR 45783879811, main 45784843681 all 13/13 SUCCESS. Foundation 139788903169: 73 contiguous pairs, 94 PASS, 100 measured tables, two actual advisory waits and one request/three audits; COGS 139788903314 one PASS/24 races, prior two temporal observations remain open. Upgrade 139788903442 exact prior rows preserved. Total 95 suites, no open PR. Coverage remains 23 verified prototype /18 partial /16 absent. Stock alert requests verified dormant, group stays partial pending consent/delivery.
- REVIEW-041 scanned all 73 pinned migrations for article/editorial/revision; only 0013 canonical content.articles and unrelated 0017 analytics report revisions. Target dictionary explicitly lists article_revisions/editorial_workflows/seo_settings. Owner requires tenant articles; choose manual capture of distinct editorial text states only, not parallel article master. Snapshot of eight existing text fields including cover reference (not binary); excludes status/publication/author and timestamps. Per article/tenant SHA-256 of canonical JSONB text unique, compare exact payload on digest match; identical state returns same historical ID even after reversion, not full edit chronology. Captures consistent visible text at function SELECT, no lock on direct article edits, no automatic versioning or restore/publish/workflow/SEO automation. Hash serialization format version needs explicit migration review if PostgreSQL serialization changes. Prototype-only retention and size/quotas, restoration authorization and editorial lifecycle need owner policy. Dedicated unassigned read/capture permissions, existing content read/write and module gates; no source edit privilege for executor, append-only audit.
- BUILD-041 adds content.article_revisions and content.capture_article_revision, composite tenant article/actor FKs, content digest idempotency, scoped NOLOGIN executor, forced RLS and shared audit. SQL, observed actual advisory contention, committed upgrade including prior stock alert and current article. Expected 74 pairs /97 suites /101 tables /14 jobs; UNVERIFIED until exact CI. Article revision group N→P only after main CI; meanwhile 23/18/16. No old migrations/tests modified. Next exact branch CI, PR, PR CI, merge, exact main CI before 0075. No production or legacy access. Existing policy/temporal gates remain.


## TEST-110 / REVIEW-042 / BUILD-042 — 2026-11-26
- Exact main 0074 `77254fb6bc7067e9ab5e8bc5f0bb60a0675ffb16`, merged PR #15, tree matched candidate fdaf59e2fc4291e66c65f29237b5180a099ca78e. Branch 45786056251, PR 45787202686, main 45788672784 all 14/14 SUCCESS. Foundation 139801865278: 74 contiguous pairs, 96 PASS, 101 measured tables, article revision immutability, tenant gates, exact state retry and observed advisory wait. COGS 139801865349 one PASS/24 races, two earlier temporal observations remain. Upgrade 139801865381 exact previous rows preserved. 97 suites, no open PR. Article revisions/editorial/SEO group N→P; 23 verified prototype /19 partial /15 absent of 57.
- REVIEW-042 reuses prior pinned all-73 migration article/editorial/revision scan plus verified sole 0074 delta; no article-favorite relationship. Legacy inventory separately lists ArticleFavorites and CustomerFavorites. Owner requires tenant articles and canonical per-tenant customer. 0013 content.articles and 0001 crm.customers canonical composite keys. 0072 product favorite cannot represent an article without weakening FK or introducing fake catalog product. Distinct typed association, no duplicate master or cross-channel mirror; no polymorphic IDs. One tenant/customer/article, independent of article revisions and product favorites. Internal prototype only: no inference of consent, user ownership, public visibility, publication eligibility, analytics or notifications. Dedicated unassigned content.favorites.read/write plus crm.read/content.read and both active modules. Stable identity, absent false no row, exact state retry, inactive row retained only for prototype. Retention, privacy, public/customer authority and published-state rules remain gated.
- BUILD-042 candidate adds content.article_favorites, content.set_article_favorite, composite FKs, scoped NOLOGIN executor, forced RLS, shared audit. Synthetic SQL/observed contention/committed upgrade including prior article revision and stock alert request. Expected 75 pairs /99 suites /102 tables /15 jobs, UNVERIFIED until exact CI. No prior migration/test changes; 57-group matrix remains 23/19/15, article identity already implemented, article favorite child not separate group. Next exact branch CI, PR, PR CI, merge, exact main CI before 0076. All earlier privacy, financial, backup, temporal and security gates remain. No production or legacy access.

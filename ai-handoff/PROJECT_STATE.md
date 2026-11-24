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

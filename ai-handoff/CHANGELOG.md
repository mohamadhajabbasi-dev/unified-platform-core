# CHANGELOG

- 2026-11-24 DOC-001: تهیه معماری، PDF و بسته handoff (documentation only).
- 2026-11-24 DOC-002: افزودن پروتکل اجباری ثبت گزارش پس از هر اقدام (documentation only).
- 2026-11-24 DOC-003: بسته آماده ورود به GitHub (offline only).
- 2026-11-24 DOC-004: مخزن خصوصی ساخته‌شده توسط مالک و آغاز ثبت مستندات راهبری؛ هیچ migration یا تغییر production اجرا نشده.

- 2026-11-24 INV-002: افزودن چهار مستند اولیه inventory/data map/sync map/open questions بر اساس کد واقعی دو مخزن؛ بدون تغییر تولید، بدون ساخت جدول، بدون تأیید schema زنده. ثبت مغایرت provider و blocker دسترسی.

- 2026-11-24 DESIGN-003: D-013 — greenfield GitHub-only development/test authorized; legacy access deferred, final approval retained.

- 2026-11-24 BUILD-001: first isolated core/CRM SQL migration and acceptance tests; CI definition; runtime verification pending.

- 2026-11-24 BUILD-002: prototype IAM roles, grants, module decisions and function-owner hardening; regression CI pending.

- 2026-11-24 BUILD-003: CRM access enforcement, conflict-safe verified identity linkage and concurrent test; CI pending.

- FIX-001: correct foundation regression test delimiter after BUILD-003; rerun pending.

- 2026-11-24 BUILD-004: add canonical tenant catalog and non-overlapping temporal prices; regression CI pending.

- 2026-11-24 BUILD-005: inventory ledger, reservations and derived balances; concurrent oversell CI pending.

- 2026-11-24 BUILD-006: atomic checkout, order snapshots, verified payment capture and fulfillment; regression CI pending.

- 2026-11-24 BUILD-007: full returns, verified full refunds, late capture review and concurrent checkout/capture; CI pending.

- FIX-002: isolate sales race fixture role keys from inventory race fixtures.

- 2026-11-24 BUILD-008: tenant double-entry finance, capture/refund journal and derived trial balance; CI pending.

- BUILD-009: fiscal periods, posting gate and fulfillment-based revenue recognition; CI pending.

- BUILD-010: independent platform subscriptions, invoices and verified billing receipts; CI pending.

- BUILD-011: legal dossier, stakeholders, addresses, typed tenant/member settings, shared audit metadata; CI pending.

- BUILD-012: explicit purchased Commerce scope, paid term and approval gate; CI pending.

- BUILD-013: consented visitor sessions/events, source reporting, withdrawal and bounded retention purge; CI pending.


- 2026-11-24 REQ-016: Added tenant-scoped app download/first-open/activity/attribution/quality reporting and unified web/app analytics design; validated existing multi-price price lists and documented missing channel/quantity/customer price resolution. D-015/AGENTS/MASTER_PLAN/ERD/handoff updated. No SQL or production changes for requested features.

- BUILD-014: move web sessions/events into shared analytics, app eligibility/registry/releases/first-open; CI pending.

- BUILD-015: app distribution reports, latest revision, explicit unknown/zero and trusted import; CI pending.


- 2026-11-24 SOURCE-004/BUILD-013..015: read 182 ERPPlus and 52 CommerceAI EF DbSet definitions via GitHub; map 234 source declarations to 57 normalized canonical target table groups. Authored new independent migrations 0013 (5 content/CRM tables), 0014 (6 catalog/price-tier tables), 0015 (7 HR/payroll tables) with matching synthetic tests. All newly authored test results PENDING. No ERPPlus/CommerceAI/production changes.

- BUILD-016: consented acquisition and order attribution, source/retention rules; CI pending. Parallel catalog/HR baseline verified.


- 2026-11-24 PRICE-017: Confirmed four tenant product price categories (original, discounted, colleague, wholesale). Existing catalog price lists reused, private price-list access and checkout resolver flagged as security gap. Added docs/FOUR_PRODUCT_PRICE_TYPES_FA.md and D-017 governance and handoff. Documentation only; no new SQL/production changes.

- BUILD-017: four standard prices, eligibility, discount guard, private RLS and checkout snapshots; CI pending.

- BUILD-018: original-only checkout, trusted channels, bootstrap constraints and actual pricing race acceptance tests; CI pending.

- BUILD-019: counterparties, purchase orders/items, full receipts and canonical stock ledger provenance; CI pending.

- BUILD-020: supplier invoices, partial settlements, existing journal/fiscal gate and derived payables; CI pending.

- BUILD-021: atomic warehouse transfers and supplier settlement race/period guard; CI pending.

- BUILD-022: lot/serial/expiry metadata and guarded trace adjustments, canonical ledger, transfer concurrency tests; CI pending.

- FIX-003: update old inventory race readiness for added trace advisory lock, preserve assertions.

- BUILD-023: split trace-aware receipt and transfer allocations, existing ledger, variant-first locks; CI pending.

- BUILD-024: FEFO, exact reservation allocations, traced fulfillment and confirmed full return; CI pending.

- FIX-004: correct guard_trace_movement dollar quote in unapplied 0024.

- FIX-005: avoid shadowing return query alias by PL/pgSQL record.

- TEST-028 candidate: serial receipt, reservation and transfer race test; CI pending.

- BUILD-025: checkout total tracked allocation cap and receipt cost evidence view; CI pending. Valuation design proposed.


- BUILD-026A: added restricted valuation preview and test; CI pending, no schema tables or posting.


- TEST-030: run 45439836678 job 138607567327 at 0fcc7b0f56b4c2c360254e23fdac494debc7de5b completed success; actual logs show 29 migrations, 37 PASS suites (29 SQL + eight concurrency), 82 tables unchanged. Restricted valuation preview verified.
- BUILD-026B: one new tenant-scoped finance.valuation_policies relation, immutable method/currency, enrollment of unused ordinary physical variants under existing trace lock, permission and RLS gates, configured preview wrapper and synthetic tests. Experimental preview policy only, no operational enforcement, immutable movement allocations, journal COGS, transfer/return, or production access. CI pending.


- TEST-031: run 45440610535 job 138610366925 at e819c2a64215af4cfa45273704732ab7f86ddb7f succeeded; actual logs show 30 migrations and 38 suites PASS (30 SQL, eight concurrency). 83 prototype tables.
- BUILD-026C: refactored existing replay algorithm into one per-movement calculation source; one new append-only finance.movement_cost_facts relation with exact canonical movement and policy FKs, tenant RLS, explicit finance capture permission and existing variant lock. Requires matched invoices for all replayed receipts, rejects unknown/unsupported history, compares prior cost and sequence for exact retry. Does not post COGS or enforce costing at stock mutation; per-receipt FIFO allocation links, transfer/returns, mixed currency and concurrent capture tests remain pending. Policy/rounding and explicit post-invoice capture are provisional; CI pending. No operational access.


- TEST-032: run 45441258538 job 138612684702 at 90fb17ca07b8ecae0fc453f89e2131b00134dd5a completed success. Actual logs: 31 migrations, 39 suites PASS (31 SQL, eight concurrency), 84 prototype tables.
- BUILD-026D: one new normalized finance.fifo_cost_allocations child relation for exact outgoing-to-receipt cost provenance, same tenant/warehouse/variant composite FKs to existing movement cost facts. Single replay algorithm now emits FIFO source allocation detail; existing preview/replay signatures preserved. Capture checks allocation quantity and cost reconcile to outgoing cost and immutable retry. Moving average still uses aggregate cost facts, no artificial FIFO provenance. CI pending. No automatic costing enforcement, COGS posting, transfers/returns, or production access.


- FIX-006 / 2026-11-24 — run 45441720623 job 138614372664 at 8ef451d9d7d52f088d402a932290d62a7ae6aa37 failed after 32 migrations applied and 31 SQL suites passed. SQLSTATE undefined_column from PL/pgSQL record b shadowing receipt alias b in 0029 test (record b has no field tenant_id). Renamed both SQL aliases a/b to fa/rb in both receipt provenance assertions; quantities, costs and all assertions preserved. No production SQL change; all concurrency suites skipped by failed job. Full CI rerun required. Last fully verified baseline TEST-032: 84 tables, 31 migrations, 39 suites PASS. Candidate: 85 tables, 32 migrations. No legacy/operational access.


- TEST-033: run 45441927719 job 138615123346 at 6a5c074ab31ad720bb3e58990cd66babff982130 completed success, 32 migrations, 40 suites PASS (32 SQL, eight concurrency). FIX-006 verified. 85 prototype tables.
- BUILD-026E: added explicit positive ordinary FIFO sale COGS posting to existing journal with unique movement FK/source, matched source invoice inventory debit, expense account, order/variant locks, period gate and exact retry. No new table. Experimental, explicit posting only; zero cost, moving-average posting, returns/reversal, transfer, full account semantic mapping and dedicated races remain pending. No operational changes. CI pending.


- TEST-034: run 45442881158 job 138618565410 at 0fea83bb72e798901ba622da99127dc9361fc499 completed success. 33 migrations, 41 SQL/concurrency suites (33 SQL, eight concurrency) PASS, plus four guard unit tests. Previous renumber-only run 45442789337 passed all four guard tests and 33 unique ID validation but failed COGS delimiter; FIX-008 verified. 85 prototype tables unchanged. All 33 SQL migrations inspected for table declarations; original sequence unchanged; no new table or operational access.
- TEST-035 candidate: added two actual competing-session scenarios for cost capture and COGS posting, with observed advisory lock waits, exact retries, immutable allocation reconciliation, one balanced journal and denied conflicting account, unauthorized/cross-tenant posting. Independent synthetic fixture; no new tables or SQL migration. CI pending. Explicit FIFO COGS is experimental, not approved accounting; return reversal, moving-average posting, transfer valuation and lifecycle enforcement remain pending.

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

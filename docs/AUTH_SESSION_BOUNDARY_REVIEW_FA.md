# AUTH SESSION BOUNDARY REVIEW — REVIEW-055 (2026-11-27)

Status: design review only; no migration, runtime activation or production approval.
Baseline: main 5a1c2b628b88331d8801323ef6efbc80216e5eb8, CI 45976527824 (33/33), 87 migrations, 107 base tables, 129 distinct foundation/COGS/historical suites.

## Existing boundaries
- 0001: core.users unique (identity_issuer, identity_subject), iam.memberships primary key (tenant_id,user_id), private iam.db_principals binds trusted database login to one membership. This is not an OAuth/session registry.
- 0002: iam.current_tenant_id/current_user_id derive trusted session_user; iam.has_permission derives existing grants; platform staff assignment is separate and references core.users. Do not replace these or trust caller-set GUCs.
- 0016: analytics.sessions and analytics.app_installations are visitor/application telemetry, not login sessions or trusted device authorization.
- 0078–0087: ops.outbox_events is one transactional event source, no delivery or consumer yet. Do not add an auth-specific outbox or parallel audit store.

## Priority review of 57 groups
23 verified prototype, 20 partial, 14 absent. Prioritize missing authentication session boundary, then shared outbox/inbox delivery contracts. Financial/tax/bank/wallet, damaged/partial returns, and real restore require owner-approved policies; retain all existing ledger sources and blockers. Shared notifications/workflows/AI and backup metadata are subsequent dependent design work. No status upgrades based solely on design.

## Proposed next technical review (not an approved runtime policy)
- Scan all 87 pinned migrations before authoring 0088; reconcile any existing session/device/credential metadata.
- Reuse core.users and tenant membership via composite FK; explicitly distinguish platform sessions and customer identity, and do not assume CRM customer is IAM user. No new user or tenant master.
- Establish threat model: trusted issuer, authenticated subject, token issuance/rotation, revocation race, expiry clock, membership removal, role revocation, tenant switching, platform isolation, pooling, session fixation and replay. No raw bearer token, password, IP or device PII in source/tests. Prefer opaque non-secret session identifiers; credential verifier/keyed digest and key handling only after approved contract.
- A dormant metadata prototype, if appropriate after review, must not authenticate, authorize, issue tokens, or alter current session_user authorization. Deny default privileges, force RLS on tenant-owned rows, narrow NOLOGIN executor only if necessary, fixed search_path, no user-controlled authorization context. Reuse ops.audit_events if audit is needed. No automatic retention/delete policy or cross-tenant bypass.
- Required tests: exact migration/SQL pairing, existing full CI, cross-tenant FK/ACL/RLS, unauthenticated/unmapped principal denial, platform/tenant separation, exact retry/conflict, rollback, real concurrent lifecycle conflict, committed upgrade preserving all prior rows. Test no changes to current IAM function definitions and privileges. No policy activation until owner approves trust, token, expiry, revocation and privacy contracts.
- 0088 ID is free at baseline; reserve no migration until design and overlap scan complete. Existing main must remain untouched; all edits via separate branch and standard guarded PR/CI.

## Open policy gates
Token issuer and trust boundaries, tenant/platform session binding, session expiry/revocation timing, device approval, OAuth client scopes, refresh rotation, retention and audit/privacy. No new financial/legal/security policy in production. Existing COGS temporal issues and tenant restore remain open.

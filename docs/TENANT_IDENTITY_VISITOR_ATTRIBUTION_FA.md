# طراحی تکمیلی: مشخصات تننت، ساختار حقوقی، کاربران، بازدید و منبع جذب مشتری
**Scope**: greenfield PostgreSQL only; no ERPPlus/CommerceAI/production changes.
**Date**: 2026-11-24. **Status**: requirements approved by user; schema details are PROPOSED, NOT IMPLEMENTED.

## Gap checked against current greenfield repository
- Migration 0001 has `core.tenants(tenant_id,tenant_key,display_name,created_at)`, `core.users` (global identity), `iam.memberships`, `crm.customers`, `crm.customer_identifiers`, `crm.customer_addresses`.
- Migration 0002 defines permissions/roles/platform staff/modules/tenant grants.
- Existing 0001..0009 cover core/CRM/IAM/catalog/pricing/inventory/sales/returns/finance. **No verified implemented tenant legal profile, stakeholder/partner register, organization settings, tenant user settings, web visit/session/attribution tables.** Check code before adding migrations to avoid collisions.
- Source of truth for current state: latest `ai-handoff/PROJECT_STATE.md`; BUILD-009 (fiscal period/revenue recognition) written, full CI for 0009 not confirmed at check time. Do not create duplicate tables and do not claim runtime PASS without logs.
- The GitHub repository was **PUBLIC** at this check (2026-11-24), despite old `PROJECT_STATE.md` top claiming PRIVATE. Therefore only synthetic test data, no real legal IDs, phones, tracking IDs, credentials or tenant records in Git.

## Requirement: complete tenant / organization dossier
One existing `core.tenants` record is the canonical tenant identity; **do not create separate Tenant, Organization, Company or LegalEntity masters for the same tenant**.
- Entity type: natural person, registered legal entity, or other applicable form (configurable jurisdiction).
- Identity fields: registered name, trade/display name, trading aliases, tax identification, jurisdiction/country, registration identifier and date, legal status, business type/industry, website/domains, contact channels, timezone/currency/locale, tax mode and invoice preferences.
- Registered/billing/operating addresses, contact details and verification status; legal documents as encrypted object storage metadata, access controlled (never raw documents in Git).
- Multiple authorized representatives, shareholders/partners, ultimate beneficial owners, signatories, managers; ownership percentage/validity periods and whether person is linked to existing `core.users`.
- Partner/representative *may be a person or a legal organization*. Do not automatically create a new login user for a non-user stakeholder, and do not put stakeholders into `crm.customers` unless they are separately a genuine tenant customer.
- One user can be in multiple tenants, roles, job titles, departments, invitation status and manager assignments tenant-scoped. Distinguish platform employees from tenant employees.
- Audit every amendment to sensitive legal/ownership/account settings; restrict view/export to authorized staff, tenant admins and superadmin (audited).

## Minimal normalized candidate entities; review before migration
| New candidate | Scope/key | Reason / avoids duplication |
|---|---|---|
| `core.tenant_profiles` | `tenant_id PK FK -> core.tenants` | 1:1 detailed/legal fields; not another tenant table; legal IDs scoped and encrypted/hashed as appropriate |
| `core.tenant_stakeholders` | `(tenant_id,stakeholder_id)`; optional `user_id -> core.users` | person/legal-party relationships for partner, investor, director, signatory, representative, ownership shares and active period; not another user/customer master |
| `core.tenant_addresses` | `(tenant_id,address_id)` | tenant business/legal/billing addresses; different from `crm.customer_addresses`, which are customer-owned |
| `core.tenant_settings` | `(tenant_id,setting_key)` | tenant-level scoped settings *only where no domain-specific setting already exists*, typed/validated and version/audit; do not copy role/module/price definitions here |
| `iam.membership_settings` | `(tenant_id,user_id)` FK -> `iam.memberships` | tenant-user preferences, notification defaults, locale/timezone, job title/department if no distinct personnel schema; do not create another Users record |
| `web.visitor_sessions` | `(tenant_id,session_id)` | anonymous/pseudonymous **visit**, never a CRM customer; consent/cookie choice, started_at/ended_at, landing page, initial referrer, source UTM (allowlist), channel/site, session identity; retention/TTL |
| `web.visit_events` | `(tenant_id, event_id)` FK -> `web.visitor_sessions` via composite key | optional page/campaign/product events, bounded high-volume append-only data, retention, partitioning and rate limits; not another customer |
| `crm.customer_acquisition_events` | `(tenant_id, acquisition_id)` FK -> canonical `crm.customers`; optional FK to visitor session | first-touch / subsequent source evidence (web, WhatsApp, Telegram, Bale, CRM, ERP, in-person), verified linkage; **never duplicate Customers**; attribution rules deterministic/auditable |

**Avoid blind table growth:** if existing `ops`, `crm` or `core` schema has a table with identical semantics by the time implementation starts, extend/refactor it instead. The candidate 8 tables are a conceptual design, not blanket permission to create 8 physical tables.

## Commerce eligibility and traffic recording
- `visitor_sessions` and `visit_events` collection only when tenant has a valid Commerce **entitlement** (subscription/purchase state per agreed billing policy) **AND** superadmin-approved Commerce module enabled. Existing module grant alone is not proof of purchase.
- No Commerce module -> no Commerce web analytics collection for that tenant. CRM acquisition source events can still record WhatsApp/Telegram/Bale/in-person where those modules and lawful processing are enabled.
- Tenant can have multiple stores/sites/channels without separate visitor or customer master. Bind `store/site_id` as scoped foreign relationship if the site registry is approved.
- Source fields: source type, platform/channel, landing referrer host, UTM source/medium/campaign/content/term, affiliate/agent ID when valid, campaign id, visit timestamp, tracked click id only with lawful basis and retention. Store **source of acquisition** and **per-order attribution** as different concepts; no overwrite of immutable first touch.
- A visitor becomes associated with `crm.customers` only after a controlled identification event with confidence/proof. Same verified customer across visits within one tenant -> one customer_id. Different tenant -> separate customer profile. Anonymous visitor count is not equal to customer count.
- Security/privacy: consent/notice where applicable, avoid collecting full URLs with secrets or PII query parameters, no raw permanent IP/user-agent fingerprinting, encrypted/masked identifiers, deletion/retention rules, robots/bot screening; never trust client-supplied tenant_id, attribution cannot grant access.
- Scalability: append-only partitioned time-based events, indexes on (tenant_id, time, channel/source), derived aggregated metrics with defined freshness/retention, not duplicate mutable order/customer master.

## Examples / acceptance tests (synthetic)
1. Tenant A buys + is granted Commerce: visitor from Google/UTM -> session -> page view -> customer registers on checkout -> same canonical A customer receives acquisition evidence; dashboard shows A channel conversion. Tenant B cannot see A sessions or customer details via RLS/API.
2. A visitor is anonymous before login: session exists without customer. No `crm.customers` row created until validated identity; bots filtered by policy.
3. Tenant C lacks Commerce entitlement/grant: attempts to insert Commerce visit/session event fail; no Commerce tracking-enabled UI.
4. Tenant A owns two stores: one visitor travels between both; only one verified CRM customer for A, even if store-specific sessions remain distinct.
5. Same individual shops in A and B: two independent customer profiles; no cross-tenant linking/exposure.
6. Tenant A is legal entity with two partners (natural + corporate), one manager and one signatory: data captured with periods, authority and proof; users linked only to existing core users where appropriate.
7. Tenant B is sole proprietor: tenant profile type individual, no fabricated corporate registration requirements.
8. Tenant admin changes valid settings; tenant staff lacking permission cannot change fiscal, security or module settings; superadmin's privileged read/export logged.
9. Multi-tenant user has different settings/roles in A and B; membership removal immediately denies tenant-specific access.
10. Concurrent repeated events via idempotency key do not inflate visits/conversions; attribution first-touch remains immutable and order-level attribution historically reproducible.

## UI and reporting
Superadmin view per tenant: registration/legal/partners/contact, enabled modules and subscription/entitlement, users and roles, tenant settings, Commerce sessions/unique visitors by day, source/medium/campaign/referrer, new vs returning, known customers, registrations, conversion, orders/revenue, marketing funnel, incidents and backup status.
Tenant administrator: only own tenant analytics / own legal dossier as permitted. Platform employees: explicitly granted scope only. Sensitive partners' information should not be exposed by generic tenant analytics.

## Implementation order and dependency gates
- **First** verify latest BUILD-009 CI (do not assume PASS).
- Then implement legal dossier + IAM scoped settings using new migration (next available number after 0009) and RLS/negative/concurrency tests; consider ensuring user preference keys constrained.
- Implement Commerce subscription **entitlement** / approval gating if not already built (platform billing still pending); do NOT treat a manually granted module as equivalent to paid Commerce.
- Add visitor/session/event tables and acquisition links with tenant composite FKs, consent, retention, source classification, dedupe and synthetic tests. No parallel Customers table.
- Integrate reporting + API only when authorization, performance, and GDPR/local privacy policy have been reviewed; load testing on synthetic data.
- Every step: `WORK_LOG.md` append, `PROJECT_STATE.md`/`NEXT_ACTIONS.md` update and real GitHub commit; no legacy or production changes.

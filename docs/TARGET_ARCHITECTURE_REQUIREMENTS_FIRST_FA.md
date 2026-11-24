# TARGET_ARCHITECTURE_REQUIREMENTS_FIRST_FA
**Status:** Draft for owner review — design principles confirmed in conversation, physical DDL/ERD pending.
**Date:** 2026-11-24
**Priority:** This document is the target-system design brief. Any CURRENT_* inventory and legacy code are migration/compatibility evidence only. If they disagree, the approved requirements take precedence; document impact, do not silently reproduce old design.

## WHY this project exists
ERPPlus and CommerceAI have separate operational databases and overlapping records, schemas and synchronization paths. The project is NOT to rebuild the same database under PostgreSQL or copy EF entities/tables. It is to create a **new, clean, normalized, tenant-safe, centrally governed physical PostgreSQL database** supporting current and future programs without independent master copies. Stop and ask owner if any proposed structure duplicates the same authoritative business entity.

## Mandatory design boundary
- One physical PostgreSQL operational database with logical schemas for modules. Not one DB per tenant or one DB per app.
- Define a canonical entity **once** at the right business scope, with PK/FK/unique/check constraints, tenant isolation, field ownership, soft-delete / audit rules and required indexes. Child tables for genuinely different 1:N concepts (addresses, variants, order lines, stock ledger, images) are **normalization, not duplicate master entities**.
- Each tenant may have its **own independent assortment, images, categories, prices, stock, articles, orders, accounting and customers**; global canonical product catalog **must not be assumed**. Whether optional product templates are shared is an OPEN decision. Do NOT create duplicated catalog master + tenant mirror automatically.
- Customer master: a single canonical per-tenant profile managed by ALL channels (shop, site, app, ERPPlus, CRM, WhatsApp, Telegram, Bale, in-person). One identified customer can have **separate independent profiles in different tenants**. Cross-tenant personal data must never leak. A unique phone is NOT a universally sufficient person identity; normalize, verify, resolve ambiguity and concurrent writes safely.
- Product master: exactly one authoritative place for tenant product identity; variants, pricing, stock movements, media and category associations are separate **necessary** relations. Any price/stock write via an authorized channel updates the same source; other channels read it, with cache invalidation/events, not separate sync databases.
- Orders: one authoritative order entity per tenant, with proper order line historical price snapshots, payment idempotency, returns and accounting distinctions. Avoid generating two unrelated orders from one checkout.
- Identity and access: one identity layer, membership in multiple tenants, tenant-specific roles and permissions; superadmin can audit and access all tenant data; platform employees distinct from tenant employees; changes and module grants authorized and logged.
- Module registry and superadmin approval: one capability definition, versioning, per-tenant grants, expiry/approval trail; no hidden duplicated module enablement source.
- Platform revenue and subscription billing are separate from tenants' ledgers/accounting, though in one physical database.
- Tenant data backup/restore independently, platform code & full DB backups limited to privileged platform roles. Never use an entire shared DB PITR restore to revert only one tenant.
- Central UI for tenant performance, revenue/order counts, security incidents, errors, resource usage, backups, module assignment, audit and alerts, with per-tenant context.
- Access via secure shared service/API; **no duplicate DB synchronization APIs**. DB must not be accessible publicly. Event outbox/cache invalidation for fast authorized updates.
- Scale for thousands of tenants/users; performance based on workload, index/partition/connection pooling and tests, not blanket assumptions about engine speed.

## Design order — important
1. Extract only the **agreed business requirements** and invariants from owner conversations; place in requirement/acceptance matrix. Any ambiguity is an explicit owner decision.
2. Design a **new clean logical domain model** and hierarchical architecture from those requirements independently of legacy EF entities.
3. Produce clean conceptual ERD and **proposed** normalized relational design, including PK/FK, tenant scope, distinct physical tables vs logical modules, unique constraints and RLS design. Get owner approval.
4. In parallel, read GitHub ERPPlus/Commerce code **only to discover legacy data shape and integration expectations**. Record legacy column/table → NEW approved canonical entity mapping, transformations, collisions and data-loss risks. Never copy a table just because it exists in legacy.
5. Later reconcile with live metadata (deployed schema may differ from code), deduplicate using identity rules, run test migration in staging and only then approved production migration.
6. Build dashboard, monitoring, operations, events, backup and app adapters around the approved shared model; remove old sync after verification, not before.

## Required proposal sections for next agent
- Platform / Tenant / User / Membership / Role / Permission / Grant / Approval / Module
- Tenant-scoped Customer / ContactIdentity / Address / Interaction / SourceIdentity with unique verified profile rules
- Tenant-scoped Product / Variant / Category / Attributes / Media / Price / Warehouse / Ledger / Reservation
- Order / OrderItem / Payment / Refund / Invoice / FinancialLedger vs PlatformSubscriptionBilling
- TenantContent / Articles / Config
- Audit/EventOutbox / Observability / TenantBackupMetadata / RestoreApprovals
- Explain exact reason for each table, scope and FK; any two tables with overlapping responsibilities must be called out for redesign before approval.

## Invariants / acceptance tests
A. Customer arrives on WhatsApp, then orders on Commerce, then chats in CRM in tenant A: one canonical tenant A customer identity is updated, no second tenant A profile when match is verified; tenant B remains independent.
B. Product price is changed in one authorized app: same tenant reads updated price from another, order confirms up-to-date price, no separate product master or cross-database sync.
C. Tenant A user cannot access tenant B customer or orders through UI/API/DB RLS; platform superadmin can inspect with audit.
D. Tenant modules not active without explicit superadmin grant; staff cannot grant privileges beyond authority.
E. Restore tenant A data without altering tenant B records; protect shared FK references, encryption and audit.
F. Sales totals, payments, inventories are consistent and idempotent across all channels.
G. Every AI action logged and committed; no duplicate work or table before checking approved model.

## Current real state and limit
No new physical DB/schema was created; nothing migrated. GitHub-only legacy source audit is not blocked; live database inspection is a later migration safety gate. Source-code evidence (e.g., store-scoped unique customer index, SQL Server EF provider) identifies **problems to solve**, not characteristics to clone into target design.

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


- TEST-035: run 45443295044 job 138620081848 at 0db9805c054545b939b05f7fd1355e050a976060 completed success. 33 migrations, 42 suites PASS (33 SQL + nine concurrency), four migration guard unit tests. Actual competing cost capture and COGS locks, idempotency and tenant gates confirmed. 85 tables.
- BUILD-026F: canonical 0034 adds explicit full ordinary sellable FIFO return reversal using existing journal, unique tenant return movement FK, exact sale/return relation and original expense/asset accounts and amount. No new table. Order and variant locks; existing fiscal period and immutable balanced journal. Tests include pre-return rejection, exact retry, closed-period reversal and conservation. No automatic posting. Does not yet reintegrate returned stock into cost replay or enable valuation of resale; capture remains fail closed after returns. Return-layer provenance, moving-average posting, zero-cost policy, transfers, further concurrency and approved accounting policy remain pending. CI pending; no operational access.


- FIX-009 — run 45443813770 job 138621932950 at 0c84496d2238d44065e5ccb2fac34c7a4012db2a failed in 0034 acceptance test after guard and all 34 migrations passed; 33 SQL suites passed, concurrency skipped. Error 42702 ambiguous column reference amount in finance.reverse_fifo_cogs line 34. Renamed local amount to v_original_cost and updated both original journal line comparisons, preserving qualified l.amount and all existing assertions. No table, permission, accounting semantics or test change. Last fully verified TEST-035: 85 tables, 33 migrations, 42 suites and four guard unit tests. New CI pending, prototype only; no operational access.


- TEST-036: run 45444335208 job 138623820708 at 6a53d994df36bd00036244d744b87270f2351e74 completed success; 34 migrations, 43 suites PASS (34 SQL + nine concurrency) and four migration guard tests. FIX-009 verified. 85 tables.
- BUILD-026G: canonical 0035 extends existing replay function (no duplicate tables or valuation API). Only full ordinary FIFO returns with exact original captured sale, confirmed COGS and reversal journal, original invoiced receipt allocations and sales access are admitted. Restores historical quantities/cost at end of FIFO queue, retains original receipt IDs and consolidates recurring receipt layers when consumed. Existing capture/journal APIs reused; no second inventory debit. Updated 0034 regression to reject unreversed returns and verify captured reversed returns; dedicated 0035 tests resale cost and journal conservation. Provisional FIFO return re-entry timing/order, no moving-average returns, transfer valuation, partial/damaged/zero-cost return, automatic posting, production approval or dedicated return concurrency. New CI pending. No operational access.


- FIX-010 — run 45444927977 job 138625943750 at 25cc668fb1b17b689033fbde44a0f58f1d6629aa failed in 0034 regression with FAIL confirmed return capture after all 35 migrations and ID guard applied; 33 SQL suites passed, remaining suites skipped. The assertion combined two volatile capture calls and a read of their writes in one SQL expression; order and snapshot visibility are not guaranteed. Split write, exact retry and persisted row assertions into separate statements in 0034 and 0035, with explicit actual counts and separate error labels. Also separated two resale capture calls. No assertions removed, no migration/runtime semantics changed. This is a suspected fixture issue, not yet a verified root cause; new CI must confirm. Last full verified TEST-036: 85 tables, 34 migrations, 43 suites, four guard tests. No operational access.


- TEST-037: run 45446005665 job 138629833448 at 44c83fff7fcd630b4e099bbef2e1515c20a41b7f completed success, 35 migrations, 44 SQL/concurrency suites (35 SQL + nine concurrency), four migration guard unit tests. FIX-010 and FIFO resale provenance verified. 85 tables unchanged.
- BUILD-026H: canonical 0036 introduces one shared explicit COGS posting implementation for FIFO and moving_average, retains existing strict FIFO wrapper without duplicate posting logic; existing journal source FK, idempotency, period and permission gates reused. Moving-average positive confirmed sale cost from captured immutable facts; every preceding positive pool movement must be an invoiced purchase receipt debited to the same inventory account, including depleted receipts (conservative restriction pending accounting approval). Mixed account pool rejected, exact retry, no fabricated FIFO allocations. Synthetic tests verify 1320 COGS and 880 asset balance, wrong account/method and closed period. No table, no production access or policy approval. Moving-average return, transfer, zero-cost handling, lifecycle and concurrent moving-average tests pending. New CI pending.


- TEST-038: run 45446414562 job 138631301536 at 97756def76543e792a30c5f029a02288c4dae549 completed success; 36 migrations, 45 SQL/concurrency suites (36 SQL + nine concurrency) PASS and four migration guard tests. Shared moving-average posting verified; 85 tables.
- BUILD-026I: canonical 0037 extends existing return replay and shared COGS posting for moving_average; one shared reversal implementation with strict compatibility FIFO wrapper, same journal sources, historical exact cost from captured sale and reversal. Pool accepts confirmed return debit only to the same inventory asset; all preceding purchases still must match. No fictitious FIFO layers. Test changes rate via a later receipt, checks original 1320 returned, resale 2290, net COGS 2400, no duplicate debit, rejection before reversal, wrong method/account and closed period. No new tables. Provisional full ordinary sellable returns only; transfers, zero cost, tracked/partial/damaged returns, automatic lifecycle and dedicated return concurrency remain pending. CI pending; no production access.


- TEST-039: run 45447390713 job 138634807713 at 01b420d7dac44ecf8ca0f082ede752321934740c completed success; 37 migrations, 46 SQL/concurrency suites (37 SQL + nine concurrency) PASS, four migration guard tests. Moving-average return and resale verified; 85 tables.
- BUILD-026J: canonical 0038 implements ordinary moving-average interwarehouse cost replay and atomic paired capture using existing transfer_lines and cost facts. No new tables, no transfer journal, transfer movement excluded from consumed COGS, exact signed pair reconciliation, private existing cost writer, variant lock and same permissions/RLS. Tests cover source/destination isolated capture rejection, exact retry, roundtrip quantity/value conservation, no new journal and blocked downstream COGS after transfer-in pending asset account provenance. Conservative capture requires whole histories in both warehouses to be replayable in source-then-destination order; complex uncaptured dependency chains fail closed. FIFO transfer, tracked transfer, destination COGS account mapping, cross-account reclassification, approved policy and dedicated transfer cost concurrency remain pending. New CI pending; no production access.


- TEST-040: run 45448040617 job 138637116976 at 99964953c72573165a5a11ee4fe63203af236059 completed success; 38 migrations, 47 SQL/concurrency suites (38 SQL + nine concurrency) PASS and four migration guard tests; exact transfer cost pairs verified. 85 tables.
- BUILD-026K: canonical 0039 extends shared COGS posting to same-asset moving-average transfer provenance. Private recursive cutoff validator follows exact earlier paired transfer cost facts through warehouses to all preceding confirmed purchase/return journal debits, deduplicates nodes and rejects mixed account provenance, including remote inputs. No new table, no transfer journal or account reclassification. Updated 0038 regression to verify destination posting with correct account and reject wrong account. New 0039 tests cover destination/roundtrip COGS, remote mixed account rejection, balanced asset/cost and private helper permissions. Conservative history-wide input rule including exhausted inputs; cross-account transfers, FIFO, tracked, partial/zero-cost return and complex dependency chains remain pending, no production policy approval. CI pending; no operational access.


- TEST-041: run 45448694965 job 138639477153 at 0013124130b576811f240ce5f62fb539652fc925 success; 39 migrations, 48 suites (39 SQL + nine concurrency), four guard tests. Recursive transfer asset provenance verified, 85 tables.
- BUILD-026L: canonical 0040 extends existing FIFO replay and paired transfer capture, preserving original invoiced receipt IDs and exact source cost allocations across warehouses. Replaces only receipt-side same-warehouse FK with tenant+variant+movement FK backed by unique constraint; outgoing warehouse FK unchanged. No table. Incoming FIFO layers appended in original receipt chronological order (provisional policy; not exact physical ordering of mixed restored layers). Tests cover paired atomicity, two receipt costs, roundtrip, original remote receipt allocation, destination COGS, full sellable return and resale, wrong account and permission. No transfer journal; same-asset receipt proof for COGS. Complex unrecorded dependency chains, tracked stock, zero/partial/damaged returns, account reclassification, lifecycle gates and dedicated cost concurrency remain pending. New CI pending; no production access.


- TEST-042: run 45449124330 job 138641037866 at 609d53b8c2d1902c358bd6cb0b105eed598f0ad5 completed success; 40 unique migrations, 49 SQL/concurrency suites (40 SQL + nine concurrency), four migration ID unit tests. FIFO transfer, cross-warehouse provenance, destination COGS/return/resale verified; 85 tables.
- TEST-043 candidate: expand existing verified COGS concurrency suite and fixture, not a duplicate harness or migration. Five actual competing lock races instead of two: initial cost capture, COGS posting, paired FIFO transfer capture, destination full-return reversal, and capture of restored return cost. Verify exact first/retry counts and identical journal ID, signed paired costs, blocked capture before reversal, tenant/permission rejection, immutable fact totals and source/destination quantity/value, 5 balanced journal headers, unchanged net COGS 1240 and inventory 960. Same PostgreSQL 16 synthetic CI. No schema/runtime changes; suite count remains 49, individual race cases increase by 3. New CI pending; no production access. Moving-average concurrency, lifecycle enforcement, tracked valuation, complex chain capture and accounting approval remain pending.


- TEST-043 verified: run 45453244380 job 138655716755 at 18adb5816bf1ed4dde9b6815c97332eca9f9a4ab success; 40 migrations, 49 SQL/concurrency suites (40 SQL + nine concurrency), four guard unit tests; all five observed COGS contention races passed. 85 tables.
- BUILD-026M: canonical 0041 read-only tenant-scoped inventory_cost_issues and explicit assert_inventory_cost_ready, based on existing stock ledger, receipt evidence, immutable cost facts, journals and paired transfer lines. Reports missing cost/invoice/COGS/reversal, unsupported movement, mismatched purchase cost, unpaired transfer and zero sale cost awaiting policy. Requires finance/inventory/procurement/sales read and enabled modules; unknown or unconfigured scope fails closed; empty configured warehouse permitted. No table, no automatic operational block, no period-close change, no profit certification or full ledger audit; readiness covers this warehouse/variant snapshot only, not all accounting and not transaction locking. Tests include pending and resolved stages, unsupported movement and tenant/permission gates. Pending CI. Next approval-dependent lifecycle/locking and comprehensive reconciliation, moving-average races and tracked/complex transfers. No operational access. Earlier lookup of incorrect 0009 filename returned 404; corrected to canonical 0009_finance_lifecycle.sql, read only.


- FIX-011: run 45463597151 job 138692481291 at 2b87e1fa16799dd157e3a49f366d55e7721642d9 failed in 0041 acceptance test with syntax error near BEGIN. All 41 migrations and migration ID guard passed; 40 SQL suites passed, concurrency skipped. Read-back found two END $; and one DO $ BEGIN instead of double-dollar delimiters in the test (JS replacement-string expansion). Corrected only those three delimiters using literal callback replacement, verified all three DO blocks have matching delimiters. No SQL runtime changes, no test assertions removed. Last fully verified baseline: 40 migrations, 49 suites (40 SQL + nine concurrency, five COGS races), four guard tests, 85 tables. New CI pending; no operational access.


- TEST-044: run 45463986659 job 138693842767 at 1284fd4aa06521355e217a4bb4269870d47161a6 success; 41 migrations, 50 suites (41 SQL + nine concurrency), four guard tests. FIX-011 and lifecycle diagnostics verified; 85 tables.
- BUILD-026N: canonical 0042 extends existing read-only inventory_cost_issues (same readiness API, no table) with invoice journal amount/type/currency checks against whole supplier invoice, COGS signed amount/type/currency checks against immutable fact, return journal exact original account/amount reversal and returned fact match. After basic lifecycle checks pass, replays configured warehouse/variant and compares each captured sequence, quantity, cost, invoiced status and exact FIFO sources; replay check violation yields scope-level issue. Synthetic fault injection via privileged test transaction and savepoints, including temporary immutable trigger disable ONLY in disposable CI and rollback, validates balanced but wrong invoice/reversal and changed sale cost/allocation/sequence; normal API cannot mutate facts. No automatic posting/closure, no complete tenant-wide financial certification or account-balance reconciliation. Scope snapshot only, may require load testing. New CI pending. No production access.


- TEST-045: run 45467042707 job 138704599957 at 0f285a80a540254828e7c68555342e81cd06b0ad success; 42 migrations, 51 suites (42 SQL + nine concurrency), four migration guard tests. Exact replay and journal fault injection verified. 85 tables.
- TEST-046 candidate: extend same existing COGS concurrency harness with five additional moving-average two-session lock races (capture, COGS posting, paired transfer, reversal, return cost capture), using existing unused variant and separate synthetic asset/expense accounts, no duplicated fixture or migration. Expect exact retry counts/IDs, 1320 historical initial COGS, paired 330 transfer and return, 880 net inventory, 1320 net expense, no FIFO allocations, ten total journal headers across both scenarios and readiness checks in both warehouses. Tenant/permission and wrong-method checks. No runtime/DDL changes. Suite count remains 51; ten actual COGS races pending CI. No production access; next tenant-level reconciliation, complex chains, tracked valuation and policy approval.


- TEST-047: run 45475840661 job 138735731458 at b37d5aa5df13e211498a7b2c4d542d61814ac1d8 success; 42 migrations, 51 SQL/concurrency suites (42 SQL + nine concurrency), four migration guard tests; ten observed lock races, five FIFO and five moving-average, verified. 85 tables.
- BUILD-026O: canonical 0043 tenant-wide read-only inventory reconciliation reuses existing per-scope diagnostics and canonical ledger, reports missing valuation policy even without facts, compares signed captured value to inventory-source asset journal net separately per currency, reports each inventory-related asset account and outside journal activity (including net-zero outside activity), explicit conservative tenant readiness assertion. No table, stored balance, account mapping or auto posting. Outside activity is a review flag, not necessarily erroneous; totals are currency-level comparison, NOT independently attributed expected balance per account, and not full financial certification or locked period close. Tests cover clean FIFO, missing facts, two currencies/methods, unconfigured scope, manual offset, tenant isolation and permission. New CI pending. Complex chain capture, tracked valuation, approved accounting and performance/period-lock review pending; no production access.


- FIX-012: run 45578648148 job 139082801809 at 775b58592165d8a5c9e43892fa5d2d2ddf9d2a6c failed at 0043 synthetic test with record a has no field account_id; PL/pgSQL local preview record a collides with SQL alias a in two asset-activity assertions. All 43 migrations applied, 42 prior SQL suites passed; concurrency skipped. Changed only both conflicting SQL aliases to aa, retaining preview variables and all assertions. No runtime/DDL changes. Fully verified baseline 42 migrations, 51 suites (42 SQL + nine concurrency; ten COGS lock races), four guard tests, 85 tables. New CI pending. No production access.


- TEST-048: run 45578934697 job 139083768266 at 429e9672dc8c7832d77d78fc856ef91ce7396a55 success; 43 migrations, 52 suites (43 SQL + nine concurrency), four guard tests, ten COGS races; tenant reconciliation and FIX-012 verified; 85 tables.
- BUILD-026P: canonical 0044 factors existing replay into one read-only optional inclusive prefix engine and full replay wrapper; one private prefix cost writer and existing full private wrapper. Existing transfer capture now walks the historically connected warehouses for the same tenant/variant under variant lock, processes transfer pairs in outgoing chronological order then validates full histories/pairs, all in one transaction. No tables or duplicate costing algorithms. Both methods tested on A->B->C->A with later uninvoiced receipt forcing rollback of all tentative facts/allocations, then exact retry, per-warehouse balance, destination sale/receipt lineage, tenant totals, private writer and cutoff access. New behavior captures all connected histories, not just requested transfer; conservative fail-closed if any later unsupported/unconfirmed movement. Replay repeated per transfer, performance/large history limits not benchmarked; strict chronology, tracked valuation and financial policy still pending. CI pending. No operational access.


- TEST-049: run 45581403955 job 139092072763 at dc802a9407f6ce07efaeb9a620452cc937919dde success; 44 migrations, 53 suites (44 SQL + nine concurrency), four guard tests and ten COGS races; 0044 connected transfer capture, rollback and remote COGS provenance verified; 85 tables.
- TEST-050 candidate: extend the existing COGS concurrency harness to accept a different second statement and add one actual two-session chain contention scenario per valuation method; two different transfer IDs in the same three-warehouse component must yield first=6 new facts, second=0 with observed advisory lock wait. Reuse existing synthetic variants/tenants, add only one synthetic warehouse. Then eight cycles (24 transfers, 48 new cost facts) per method, timed capture and retry logged as CHAIN_TIMING; check 61 facts per variant, 28 exact pairs per variant, conserved quantity and value, no new journals, readiness and no moving-average FIFO rows. 60s statement timeout is only CI ceiling; sample includes client overhead and is not production capacity/load certification. No DDL/runtime changes; 12 actual race cases pending new CI, 53 suites unchanged. Next tracked valuation design and targeted performance review; no operational access.


- DESIGN-0045: reviewed tracking policies, lots/serials, allocated receipt/transfer, reservation allocations, tracked return keys, existing cost facts, FIFO allocation and journal boundaries; added staged proposed trace valuation design and acceptance criteria to existing valuation design doc, no new table/migration/runtime change. Explicit provisional serial specific identification / lot-restricted FIFO, never equate FEFO with financial costing. First 0045 read-only trace evidence, then policy/replay/capture/journals in increments. TEST-050 run 45582369761 job 139095338216 at 9410c90335794e4b2b27b04278315deca3e2bc67 is in_progress; no new test pass claimed. No operational access.


- TEST-051: TEST-050 run 45582369761 job 139095338216 at 9410c90335794e4b2b27b04278315deca3e2bc67 success; 44 migrations, 53 suites (44 SQL + nine concurrency), four guard tests and twelve COGS races. CHAIN_TIMING FIFO 1191ms capture/1170ms retry, moving-average -263ms capture (INVALID wall-clock discontinuity)/341ms retry. 85 tables. No production benchmark claim.
- BUILD-026Q: 0045 read-only tracked_movement_evidence, one canonical movement lookup with four module/permission gates, exact traced identity, receipt/invoice, paired multi-line transfers, consumed sale allocation and full returned allocation/source evidence. Reject unsupported or missing/ambiguous evidence, tenant isolation; no cost fact, policy, journal or table writes. Tests cover split receipt/one invoice, four-line transfer, FEFO sale allocation, full return identity, unsupported adjustment and permissions. Also fix timing harness using monotonic_ns and nonnegative assertion; rerun timings. New CI pending. Valuation policy/engine/COGS still unsupported for tracked variants; no operational access.


- TEST-052: run 45584291044 job 139101830912 at 9e35012d01077f482be9ad09c7c13d40d822d787 success; 45 migrations, 54 suites (45 SQL + nine concurrency), four guard tests and twelve observed COGS races. Tracked evidence verified. Valid CHAIN_TIMING (monotonic wall elapsed including client): FIFO 691ms capture/678ms retry; moving_average 258ms capture/256ms retry, 24 extra transfers and 48 new facts each. Synthetic only, 85 tables.
- BUILD-026R: canonical 0046 extends only existing valuation_policies method constraint with explicit experimental lot_fifo and serial_specific. Same configuration API and variant lock, tracking-first enrollment before stock/reservations, exact immutable retries, ordinary methods unchanged and reverse enrollment guarded to prevent ordinary policy + tracking mismatch. Configured tracked preview fails closed; existing capture engine rejects new methods until supported, no financial facts or posting activation. Tests include invalid method/identity/order, post-stock enrollment, exact retries, read/write permissions, tenant isolation and pending readiness. README corrected stale planning/private/CI statements using confirmed public repository metadata and TEST-052 checkpoint; no visibility change. New CI pending. Next shared tracked replay/prefix, then multi-line transfers and tracked COGS/returns; policy remains provisional. No production access.

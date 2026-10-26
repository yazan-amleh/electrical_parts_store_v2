# V2 release-parity execution checkpoint — 2026-10-27

Status: **NOT production-ready**. Reference: V1 `انشاء-الشجرة-الجديدة`. V2: `audit/systematic-v1-parity-20261023`. No V1 data sync, Firebase deployment, or base-branch merge.

## Acceptance rule

A module is accepted **only** after these distinct gates pass: (1) V1 current-source action/screen inventory, (2) equivalent V2 user-visible flows, including loading/empty/error/RTL/mobile/desktop, (3) correct role and tenant boundaries, (4) balanced accounting + inventory effects, (5) success/retry/duplicate/race failure testing, (6) emulator and **deployed independent V2 test-environment** acceptance, (7) actual visual and print/export comparison. Source code existence, simulated widget tests, and a green GitHub Actions build do **not** satisfy the final release gates.

## Release workstreams

| Workstream | Source parity | Automated safety | Real Firebase E2E | Visual signoff |
| --- | --- | --- | --- | --- |
| Startup, store onboarding, auth, user admin | Partial | Extensive, not exhaustive | Open | Open |
| Dashboard, shell, RTL, theme, narrow navigation | Partial | Partial | Open | Open |
| Catalog, nested categories, units, inventory | Partial | Partial | Open | Open |
| Sales, returns, point-of-sale, invoices and sales reports | Partial | Partial | Open | Open |
| Purchases, purchase orders, partial receipts, reversals | Partial | Partial | Open | Open |
| Parties, voucher lifecycle, cheques, balances, cash/banks | Partial | Partial | Open | Open |
| Chart, journal, audit, statements, close and multicurrency | Partial | Extensive, non-certifying | Open | Open |
| Offers, repairs, notifications, chat, settings and exports | Partial | Partial | Open | Open |
| Native Android/iOS (if in release scope) | Not built | N/A | Open | Open |
| Independent production deployment, backups and recovery | N/A | CI only | Open | Open |

## Approved V1 sales workflow and the current V2 split

- V1 `lib/views/screens/sales_screen.dart`: sales reporting screen with **تفاصيل المبيعات**, **الأصناف الأكثر مبيعاً**, **ملخص العملاء**; search, batch selection, invoice printing, PDF and Excel exports, and several per-view actions. This is **not** the same as V2's sales posting screen.
- V2 `features/sales/presentation/sales_page.dart`: transactional point-of-sale/cart, basic payment methods, discount and tax; its source is available and is undergoing retry/tenant/amount safeguards.
- V2 `features/reports/presentation/sales_analytics_page.dart`: period analytics by product, category, customer and payment method. Do **not** count this as V1 report-tab/action parity without matching search, selected invoice batches, customer summaries, formatting and export workflows.

### Sales risk fixes submitted for CI

1. A retried sale with an unchanged cart reuses the same `Sale`, ID and idempotency key; the prior implementation created a fresh ID for each request.
2. An acknowledged outbox-queued sale cannot be posted again from the same screen. A deliberate new-cart action warns that the prior queued transaction is **not canceled**.
3. Inactive items are excluded, cross-store products and mixed sale currencies cannot enter the same cart, and sales write actions require a sales-authorized role.
4. Products/customers fetched for a prior store/user are discarded; posting responses must belong to the active session before modifying UI.
5. Widget regression tests exercise retry identity, queued warning, role visibility, inactive products and mixed currencies.

Remaining sales release requirements: V1 all screens and report export parity; actual draft/returns and reversal scenarios; authorization/idempotency with concurrent users; offline queue recovery and reload; quantities, discounts, multiple currencies and tax posting reconciliation; real store test with Firebase Functions/Firestore/Storage; narrow-device and printed-invoice visual checks. None is certified by this checkpoint.

## Mandatory rollout gate

Do not deploy or merge merely because CI succeeds. Verify roles, privileged service accounts, close-period writer boundaries and real backup/restore recovery in an **isolated V2** environment. Obtain an explicit deployment decision from the owner. The existing manual deploy workflow checks out `v2/port-v1-complete`, not this audit branch; approving a separate deployment action requires a deliberate branch/release review.

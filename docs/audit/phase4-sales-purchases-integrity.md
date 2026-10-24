# Phase 4 — sales, purchases and inventory posting integrity

Date: 2026-10-23

## Scope and immutable baseline

- Repo: `yazan-amleh/electrical_parts_store_v2`, isolated branch `audit/systematic-v1-parity-20261023`; base `v2/port-v1-complete`.
- V1 is only a UI/feature reference. No V1 source/customer data was changed.
- No production Firebase writes, deployment, merge, backfill, mutation of historical ledgers, or migration.
- This is one slice of accounting stage 4, **not** overall sales/purchase/returns certification.

## Real posting flows traced

- Purchase: `postPurchase` / order-receipt use of `postPurchaseInTransaction` -> inventory receipt movements -> stored product quantities and inventory valuation -> purchase invoice and detail lines -> purchase journal/lines -> supplier party ledger/balance when credit -> inventory, input tax and settlement/payables GL balance projections -> idempotency markers.
- Sale: `postSaleInTransaction` -> price/cost and stock checks -> invoice/lines -> product stock reductions and movements -> revenue, receivable/cash, output tax, COGS and inventory journal -> customer ledger/balance on credit -> GL projections -> idempotency markers.

## Confirmed source defects fixed

**Purchases**
1. A matching purchase key and ID acknowledged a changed request without comparing quantity, cost, discounts, accounts or invoice metadata. Added normalized request SHA-256 fingerprint for new requests and exact old invoice + header + complete ledger line checks for legacy marker replay.
2. Unchecked subtotal/grand-total, per-product quantity/cost and aggregate inventory arithmetic could leave safe-integer boundaries. Added checked arithmetic.
3. Existing product inventory cost was recalculated from a rounded average unit price even if a separate authoritative `inventoryValueMinorUnits` was persisted. Now use stored inventory value when present; retain legacy fallback if not present and reject corrupt/negative/zero-stock-nonzero-value projections.
4. GL and supplier projections were updated using `storedInt(value,0)` on existing corrupt values. Now fail closed with account/party identity/currency/debit-credit-net validation before posting.
5. New purchase journal line documents include currency for strict ledger reading.

**Sales**
1. Added equivalent invoice fingerprint and historical original invoice/ledger validation to reject altered idempotent retries.
2. Checked subtotal, cumulative COGS, stock issued by product, sale gross/net arithmetic, GL debits and credits.
3. Existing invalid product costs, stock quantities, inventory values, customer balances and GL projections are rejected rather than silently cast/defaulted to zero.
4. COGS and inventory journal lines previously used duplicate `lineNumber` when produced in the same `push`. New entries have distinct ordered line numbers. Historical duplicate numbering remains supported in the legacy replay verifier.
5. Service-only sale and optional zero-tax account paths preserve legitimate zero deltas; they do not create inventory movements.

## Files changed in this slice

- `functions/accounting/purchase_integrity.js`
- `functions/accounting/sale_integrity.js`
- `functions/index.js`
- `functions/purchase_integrity.test.js`
- `functions/sale_integrity.test.js`
- `functions/package.json`

## Verified CI evidence

Source commit: `d59b039f9b43ea402f2bffc614b86fc1273609a4`

Actions: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39940092860 — **SUCCESS**.

- 108 Flutter tests PASS
- 20 Firestore/Storage security-rules tests PASS
- 60 Node/Cloud Functions emulator tests PASS, 0 FAIL
- `flutter analyze`, Dart formatting and `flutter build web --release` PASS
- New tests in this slice: 8 purchase + 10 sales emulator cases (concurrent posting, exact replay, legacy replay, purchase cost-basis preservation, stock balances, credit/tax, corrupt inventory/GL/customer/supplier, unsafe amounts, insufficient stock, service-only sale).

**Important:** local emulator/compilation evidence does not imply deployed Firebase E2E correctness or production readiness.

## Open accounting gaps (must NOT be marked complete)

- **Return/refund flows:** No standalone return/refund path was identified by pathname in V2 or the V1 main tree; this is not proof return behavior is absent from V1 screens. Audit embedded buttons and business rules before designing return/reversal journal and inventory restocking.
- **Receipt idempotency:** `receivePurchaseOrderInTransaction` has an independent receipt key/ID replay branch needing payload fingerprints and exact receipt/posting checks; `createPurchaseOrderInTransaction` still sums order totals without safe accumulation.
- **Full depletion rounding:** Sale COGS uses the stored rounded average cost per unit; a stock issue that reduces quantity to zero may leave a rounding remainder in `inventoryValueMinorUnits`. This requires explicit cost-allocation and accounting-policy tests; do not silently zero or invent adjustments.
- **Stock/GL cross-projection reconciliation:** These isolated tests confirm a transaction's deltas, not a whole-store replay of all journals versus `account_balances`, party ledgers, inventory movements and current product valuation. Missing inventory opening balances and historical adjustments must be surfaced, not fabricated.
- **Concurrency across different features:** Sale vs inventory adjustments vs purchase on the same product, refunds and stock units remain to be characterized with real conflict tests.
- **Multi-currency, tax policy, cost valuation policies, reversals, high-volume pagination** remain open.
- **V1 UI parity:** Detailed V1 sales screens (including several alternative detail, search, export and analytics views) have not all been ported pixel-for-pixel to V2; UI acceptance remains open.
- **Native platforms / real Firebase environment:** Android/iOS registration and actual V2 Firebase deployed end-to-end testing remain open.

## Next gate

Review purchase-order receipt/idempotency and embedded return behavior; design lossless, read-only ledger-vs-inventory reconciler and require passing accounting policy tests before rewriting any historical balances.

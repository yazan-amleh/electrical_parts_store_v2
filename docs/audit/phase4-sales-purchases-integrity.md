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

## Later closures verified on the current audit branch

The original 2026-10-23 gap list below was partially superseded by later
audit slices. Do not reopen already-proven defects without new evidence.

- **Purchase-order receipt replay integrity:** closed by the dedicated
  purchase-order receipt hardening. New receipt markers carry a normalized
  request fingerprint; legacy fingerprintless receipts are verified against
  the completed order, purchase and journal evidence before an exact retry is
  acknowledged. Safe checked accumulation is also used for purchase-order
  totals. See `phase4-purchase-order-receipt-integrity.md`; its recorded
  source commit is `886eb10361758167f857d6b2f676914035f7067c` and its
  verification run is `39942358564`.
- **Full stock-depletion rounding:** closed for sale posting by commit
  `180f87f67fe7e96f8b8b713735d30a68b59e43ed`. When the last units are
  sold, any residual difference between the rounded average unit cost and the
  authoritative stored inventory valuation is allocated to the sale COGS and
  its line/movement/journal consistently. Quantity zero must end with
  inventory value zero. GitHub Actions run `40544502079` passed.
- **Sale versus manual stock race:** characterized by commit
  `fd35d4b75c19ce4c63e826044c912b73fb381446`. A sale and a negative
  adjustment competing for the last units serialize through Firestore
  transactions: only one commits, the other fails closed, and the posting
  epoch advances once. Run `40545291000` passed.
- **Manual inventory command integrity:** hardened by commit
  `e7a4eea59e6084f134fb89b3d4edbad58249d2bd`. New idempotency markers
  include an immutable request fingerprint, legacy retries are verified from
  the original movement, malformed stored stock/value fields fail closed,
  quantity/value arithmetic is checked, and a full manual depletion must
  remove the exact remaining valuation. Run `40546205380` passed.
- **Whole-store read-only reconciliation:** later Phase-4 slices added
  checkpointed ledger, journal-header, orphan-path, stored-balance and
  inventory/currency reconciliation plus a unified non-certifying report.
  These detect many cross-projection inconsistencies but deliberately do not
  claim an immutable point-in-time accounting snapshot.

## Open accounting gaps (must NOT be marked complete)

- **True return/refund flows:** the audit found that V2 exposed
  `saleReturn` and `purchaseReturn` as generic stock-only movements. Those
  new manual paths are now blocked because they changed inventory without the
  corresponding financial reversal. Historical movement records remain
  readable. A real return must reference the originating business document
  and atomically reverse/adjust stock, tax, settlement/party balances,
  revenue/purchase effects and COGS/inventory as applicable.
- **Manual opening-balance and adjustment accounting policy:** generic
  inventory movements can change stock valuation without creating a GL
  journal. The mutation epoch detects the change, and reconciliation can flag
  divergence, but the correct counter-account/business policy has not been
  specified. Do not invent an opening-equity or adjustment account silently.
- **Immutable accounting cutoff:** the checkpointed audits detect
  instrumented source changes but are not a Firestore historical snapshot.
  Privileged/Admin out-of-band writes remain an operational boundary.
- **Full line-identity historical reconciliation and source provenance:** the
  unified audit compares strong independent aggregates and paths, but matching
  totals can still conceal offsetting historical differences. Opening stock
  provenance must be evidenced, not fabricated.
- **Multi-currency, return/reversal policy, tax edge cases and historical
  compatibility** still require source-specific acceptance scenarios.
- **V1 visual/UI parity:** exact responsive screenshots, printed invoices and
  all alternative V1 workflows remain acceptance gates even where equivalent
  V2 logic exists.
- **Native/deployed V2 E2E:** Android/iOS registration (if in release scope)
  and an isolated deployed V2 Firebase end-to-end run remain open.

## Next gate

Audit the accounting semantics of manual opening-balance/adjustment movements
and the real V1 return behavior before creating any new financial reversal
contract. Continue UI/print parity and isolated deployed-V2 E2E independently;
do not rewrite historical balances to make audits pass.

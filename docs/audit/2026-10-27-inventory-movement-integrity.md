# Inventory movement integrity follow-up — 2026-10-27

Status: **implemented and CI-verified on the isolated audit branch; not a production sign-off**.

Repository: `yazan-amleh/electrical_parts_store_v2`  
Branch: `audit/systematic-v1-parity-20261023`  
No production deployment, historical rewrite, V1 mutation or base-branch merge.

## Why this follow-up was required

The generic `postInventoryMovement` path remained materially weaker than
the sale/purchase posting paths:

1. an idempotency key could be replayed with the same movement ID but altered
   quantity, cost, date or source data and still be acknowledged;
2. malformed persisted quantity/cost fields could be coerced through legacy
   fallback behavior instead of failing closed;
3. quantity/value arithmetic did not consistently use the checked safe-integer
   helpers;
4. a manual full depletion could leave quantity zero with residual inventory
   value;
5. the manual UI exposed `saleReturn` and `purchaseReturn` as stock-only
   movements even though no matching financial reversal was posted.

## Implemented controls

Commit `e7a4eea59e6084f134fb89b3d4edbad58249d2bd`:

- adds `accounting/inventory_movement_integrity.js` with a normalized SHA-256
  fingerprint covering store, movement identity, product, type, quantity,
  unit/total cost, currency, source metadata, description and occurrence time;
- stores that fingerprint on new inventory idempotency markers;
- verifies fingerprintless historical retries against the original movement
  before returning `already_posted`;
- rejects changed same-key retries with `already-exists`;
- validates persisted quantity, purchase cost and inventory valuation as safe,
  non-negative integers and rejects zero-stock/nonzero-value corruption;
- uses checked safe-integer addition for stock quantity and valuation changes;
- requires a full depletion to remove the exact remaining stored valuation;
- when the manual UI removes the complete remaining quantity, it submits the
  product's authoritative `inventoryValue`, not a recomputed rounded amount;
- removes `saleReturn` / `purchaseReturn` from the generic new-movement
  command/UI while retaining historical enum rendering.

The return restriction is deliberate: a stock-only return is not a valid
financial return. A later business-return contract must atomically handle
the original document, settlement/party balance, tax, revenue/purchase
effects, COGS/inventory and stock.

## Cross-feature concurrency evidence

Commit `fd35d4b75c19ce4c63e826044c912b73fb381446` adds an emulator race
between a sale and a negative manual stock adjustment for the same final
1,000 milli-units. Firestore transaction retries serialize the product
projection: one operation commits, the competing operation fails with
`failed-precondition`, only one inventory movement remains, the final stock
and valuation are zero, and the posting epoch advances once.

The related sale full-depletion correction is commit
`180f87f67fe7e96f8b8b713735d30a68b59e43ed`: residual rounded-average
cost is allocated to COGS only when the product is fully depleted so the sale
line, sale header, inventory movement, inventory projection and GL journal
share the exact same cost.

## Verification

- Sale full-depletion correction: Actions run `40544502079` — **SUCCESS**.
- Sale vs manual-stock race: Actions run `40545291000` — **SUCCESS**.
- Manual movement hardening: Actions run `40546205380` — **SUCCESS**.

For the final hardening run, functions syntax, Dart formatting,
`flutter analyze`, Flutter tests, Web release build, Firestore/Storage
security-rule tests and the serialized Cloud Functions/emulator suite all
passed.

## Remaining accounting gate

Manual `openingBalance` and generic `adjustment` movements can still alter
inventory valuation without creating a corresponding GL journal. The
server-maintained mutation epoch and reconciliation scanners can detect the
source change/divergence, but they do not choose the correct counter-account.

That policy must be defined from the intended accounting contract before
implementation. Do **not** silently invent opening-equity, shrinkage,
gain/loss or other counter-accounts, and do not rewrite historical balances
to force reconciliation.

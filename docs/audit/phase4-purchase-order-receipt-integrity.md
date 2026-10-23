# Phase 4 — Purchase-order receipt integrity, 2026-10-23

## Scope

Audited purchase order receiving in `functions/index.js`, including the nested invocation of `postPurchaseInTransaction`. Source branch: `audit/systematic-v1-parity-20261023` from `v2/port-v1-complete`. No V1 code or client data modifications. No Production Firebase writes, deployment, migration or merge.

## Confirmed deficiencies and committed fixes

1. **Receipt idempotency mismatch:** an existing receipt key was accepted if it belonged to the same purchase order, regardless of changed receipt ID, payment method, tax, posting account identities or posted date. New receipts store a normalized SHA-256 request fingerprint in `purchase_order_receipt_idempotency`. Altered requests fail with `already-exists`.
2. **Unmarked completed receipt:** an already completed order with the same receipt ID was acknowledged without an idempotency marker. Now the system fails closed rather than claiming an unverified result.
3. **Old V2 receipts:** historic receipt markers lacking a fingerprint are compared with original completed order, purchase document and journal header, and the three possible journal posting account identities and exact line values. Historic lines may omit redundant currency; a mismatching account or posting date is rejected. No historical marker is rewritten.
4. **Malformed quantity:** a stored `receivedQuantityMilliUnits` string, fractional, negative or unsafe integer was previously read as zero through `storedInt`. It now fails rather than re-receiving potentially incomplete stock.
5. **Unsafe order total:** `createPurchaseOrderInTransaction` now uses checked safe-integer accumulation of order line totals.
6. **CI stability:** previous source-identical actions after an audit-doc commit intermittently failed with `3 INVALID_ARGUMENT: Transaction is invalid or closed` during a historical party-payment Firestore-emulator collection query. Node test files now run with `--test-concurrency=1` to avoid test-file interference from shared emulator state. The new CI run is green; this is not proof that all emulator or production transaction races have been eliminated.

## Files changed

- `functions/accounting/purchase_order_receipt_integrity.js`
- `functions/index.js`
- `functions/purchase_order_receipt_integrity.test.js`
- `functions/package.json`

## Exact verification

Source commit: `886eb10361758167f857d6b2f676914035f7067c`

GitHub Actions run https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39942358564 — **SUCCESS**:

- 108 Flutter tests PASS
- 20 Firestore/Storage security-rules tests PASS
- 67 Cloud Functions/Node emulator tests PASS (0 failures), including 7 new purchase order receipt tests: concurrent receiving, changed tax/payment method/receipt ID, fingerprintless replay with historical posting check, missing receipt marker, corrupt received quantity, cancelled order
- Dart formatting, Flutter analyzer and `flutter build web --release` PASS

These tests validate the isolated path and do not constitute complete business acceptance or real Firebase E2E.

## Open gates and next steps

- **Refunds and returns:** A standalone return/refund feature was not identified by filename in the V1 or V2 trees. This does not prove that V1 has no embedded return actions. Audit exact V1 screens/business paths before implementing any refund/reversal design.
- **Inventory depletion and rounding:** full-quantity sales may leave valuation residue due to rounded average cost. Accounting treatment must be specified and tested without silently changing balances.
- **Read-only reconciliation:** `auditAccountingIntegrity` already exists, but its `collectionGroup('lines')` query includes line collections outside `journal_entries`. Validate strict parent path and completeness, remove silent numeric coercion in audit calculations, and use safe paginated processing for large stores before certifying historical balances. Do not backfill or repair by manipulating amounts.
- **Return- and source-specific journal invariants**, stock valuation policies, multi-currency, idempotency of other business flows, historical compatibility, actual V2 Firebase registration/device E2E and full V1 UI/feature parity all remain open.

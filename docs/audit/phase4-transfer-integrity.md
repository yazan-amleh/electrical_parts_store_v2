# Phase 4 — Transfer integrity slice (2026-10-23)

## Scope and branch

Source: `v2/port-v1-complete`; execution: `audit/systematic-v1-parity-20261023`. All changes are in draft PR #1 only. There has been no deployment, merge, V1 modification or Production data write.

## Trace of data flow

Flutter account transfer command -> callable `postAccountTransfer` -> transaction `postAccountTransferInTransaction` in `functions/index.js` -> store membership role validation -> transfer and idempotency documents -> journal header/lines -> two account-balance projections. The transfer journal is double-entry: the destination is debited and the source is credited for the same ILS minor-unit amount.

## Deficiencies found and addressed

- T-001: A repeated idempotency key with the same transfer ID but *different amount or accounts* was previously acknowledged as `already_posted`, without comparing the original transfer. Fixed with normalized SHA-256 fingerprint of the transfer fields, stored on new transfer and idempotency documents. Historical records without fingerprints are compared against their persisted transfer fields and linked journal/marker before a replay is acknowledged.
- T-002: Existing invalid balance values were previously silently replaced with zero through `storedInt(value, 0)`. Fixed by reuse of strict `readBalanceForPosting`, checking tenant, account, currency and debit-credit/net reconciliation.
- T-003: Summing a valid transfer amount with a previous debit/credit balance could exceed JavaScript's safe integer limit. Fixed with `checkedMinorAdd` on debit, credit and net; reject atomically and preserve prior documents.
- T-004: No targeted emulator regression tests existed for the above transfer failure modes. Five emulator tests now cover concurrent replay, different-amount replay, historic fingerprintless replay, malformed balance projection and cumulative overflow.

## CI evidence

Committed source: `5bc8d94938836248574289ca021e970192fc0368`.

GitHub Actions success: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39929657881

- 108 Flutter tests: PASS
- 20 Firestore/Storage rules tests: PASS
- 19 Node Functions/emulator tests: PASS, 0 failed
- Dart formatting, Flutter analyzer and `flutter build web --release`: PASS

## Remaining accounting acceptance gates

- V2 `postExpense`, sales/purchases, party payments, cheques and inventory still contain separately implemented balance mutations and need auditing, exact replay guarantees, limits and tests.
- Existing multi-source balance projections need a read-only ledger vs balances reconciliation procedure before any repair plan is approved.
- A historical transfer marker without a hash is checked against stored transfer fields and journal header but does not constitute a complete audit of historic journal lines.
- Journal queries must be made lossless and paginated; `collectionGroup('lines')` path filtering **after query limit** is not sufficient to prove full ledgers.
- Race/reversal/multiple-currency/permissions and actual V2 Firebase end-to-end tests remain open.
- Native Android/iOS deployment and full V1 UI parity remain open.

**Phase 4 is not complete.** This slice is source and emulator verified, not a complete accounting-system certification.

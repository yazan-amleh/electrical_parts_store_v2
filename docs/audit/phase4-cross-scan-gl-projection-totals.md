# Phase 4 — independent stored-GL totals versus indexed-ledger evidence

Date: 2026-10-24. Branch: `audit/systematic-v1-parity-20261023` (draft PR #1).
No V1 changes, production deployment, accounting writes, or merges.

## Gap closed

Before this change, the reverse `account_balances` scan verified each
projection's tenant, chart account, currency, integer amounts, and internal
debit-minus-credit net. A projection changed *after* the per-account journal
scan could still pass the reverse validation by maintaining its own net.
The consolidated report might say `observed_aggregates_agree_non_atomic`
because the projection scan did not aggregate independent financial sums.

The reverse scan now accumulates separately for **each currency**:
- valid stored balance document count;
- debit and credit turnover (minor units);
- positive debit and negative credit closing balance sides.

The map is stored transactionally in the existing checkpoint alongside
the pagination cursor and issue counts. Only individually valid,
non-header, chart-backed, tenant-matching projections are included.
Malformed/unknown balances remain counted as invalid with independent
findings, not silently assigned to a guessed currency.

The checkpoint schema version advances from **1 to 2**; an older partially
scanned checkpoint is rejected on advance. A new run must be started.
The invariant `valid balance documents + invalid balance documents =
balances checked` is validated each call; per-currency safe-integer
overflow and more than 16 currencies fail closed.

## New consolidated cross-run test

`getUnifiedAccountingAuditReport` now includes
`checks.storedBalanceAgreement`, comparing the later stored-projection
aggregates to the earlier indexed-ledger trial balance **by currency**,
independently for:
- debit turnover;
- credit turnover;
- closing debit and credit sides.

Comparison is withheld until both scans are complete
(`comparable:false, allAgree:null`). Otherwise, discrepancy in *any*
currency causes `STORED_BALANCE_TOTALS_DIFFER_FROM_LEDGER` and
`verdict:issues_found` even if every stored balance is internally
arithmetically valid and the older ledger-to-journal scan agreed.
The unified response schema advances from **2 to 3**.

This is not an FX conversion and **never** nets ILS, USD, or JOD
against one another.

## Explicit limitations

- **NO immutable cutoff and NO Firestore historical snapshot.** Source
  changes can occur between and within audits; matching aggregates can
  conceal offsetting changes, deleted documents, and unchanged totals.
- This is stronger *inconsistency evidence* than the previous report,
  not evidence that the data are immutable or complete.
- A torn read after page pagination may still evade checks when values
  happen to produce identical totals.
- The comparison does not replace per-account/posting validation or
  the path-oriented orphan-line census.
- No automatic fixes, reposting, migration, UI changes or deployment.
  The audit remains non-certifying: `certified:false`,
  `accountingCutoffApplied:false`, `consistency:'non_atomic'`.

## Tests

New emulator cases check correct ILS/USD grouping, detection of a
self-consistent stored projection changed between the independently
completed ledger and reverse scans, and no false complete comparison
while scanning. Unit tests check cumulative safe-integer overflow,
currency-group limit, persisted-counter invariants, and mixed-currency
netting errors. CI must pass on the final audit-branch HEAD before
marking the feature verified.

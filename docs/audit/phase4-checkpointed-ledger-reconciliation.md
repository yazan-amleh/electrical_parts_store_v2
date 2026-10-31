# Phase 4 — checkpointed GL balance-evidence reconciliation

Date: 2026-10-24  
Branch: `audit/systematic-v1-parity-20261023`, draft PR #1.

## Implemented, read-only source accounting

The prior historical document enumeration is still available and unchanged.
This new flow separately processes journal lines **per known chart account**
in resumable pages. Each scan checks debit/credit arithmetic, ledger account
and currency identity, parent journal availability/posting status, and
the resulting totals against persisted `account_balances` projections.

Callable API (authenticated active owner/admin/accountant):
- `startAccountingLedgerReconciliation({storeId})`
- `advanceAccountingLedgerReconciliation({storeId,runId})`

For each account, bounded collection-group query:
`lines.where('storeId','==',storeId).where('accountId','==',accountId)`
sorted by full document name, 40 rows per page plus one probe.
Full reference paths distinguish journal lines from invoice lines and
foreign-tenant paths. Unique journal headers are read and checked within
each page's transaction. The full page of source reads, cumulative debit,
credit, warning evidence, and cursor are committed transactionally.

Progress saved under
`stores/{storeId}/accounting_ledger_runs/{runId}`:
last completed chart account, active account, absolute cursor path,
running debit/credit, counted journal lines, bounded issue samples,
page/document/account counts, mismatched-account count.

One result per completed account is stored under the same run's
`account_results/{accountId}`. Each account result includes totals,
matched flag, issue count and up to 20 sample issues. Nothing in the GL,
journal source, inventory, sales, purchases or balance projections is
modified. Repeated final advance is idempotent. Concurrent advances of
the same run serialize via Firestore transactions; another user cannot
advance the run.

A matching account means **only** that this non-atomic scan of indexed
journal lines found no issue or mismatch against its projection. The
entire run never returns a `healthy`, `certified`, or point-in-time
accounting conclusion. Every response sets
`scope: known_chart_accounts_indexed_ledger_lines`,
`consistency: non_atomic`, `certified:false`,
`accountingCutoffApplied:false`.

The required `lines` collection-group composite index is declared in
`firestore.indexes.json`; checkpoint and result read/write access
from clients is denied by `firestore.rules`.

## Test coverage

Backend emulator cases cover valid two-sided account balances,
corrupted projection net, invalid journal currency/money, invoice decoys,
resuming >40 documents per account with concurrent calls, revocation,
unauthenticated access and invalid checkpoint rejection.
Firestore emulator tests prove clients cannot forge financial evidence.

**Acceptance:** associate this change with a successful GitHub Actions run
before marking code verified.

## Still unresolved (must not certify or deploy)

- Missing/wrong embedded `storeId` or `accountId` makes a ledger line
  invisible to this indexed scan. Orphaned lines and unknown accounts need
  independent cross-checks; it is not complete financial-history coverage.
- The state of journals or projections can change between calls.
  **There is no fixed accounting cutoff or consistent read timestamp.**
- This does **not yet reconcile journal-header totals**, aggregate trial
  balance across every account/currency, opening balances, stock COGS,
  reverse postings, party balances, or multi-currency revaluation.
- Runs and result documents need explicit retention/cost throttling
  policies. No UI automatically calls these endpoints.
- No V1 changes, production deployment, actual ledger correction,
  backfill, or V1/V2 data migration is performed.

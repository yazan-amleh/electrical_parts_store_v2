# Phase 4 — independent reverse scan of all stored GL balances

Date: 2026-10-24. Branch `audit/systematic-v1-parity-20261023`.

## Rationale

The chart-driven reconciliation reads each known `accounts/{id}` and
its `account_balances/{id}`. It can therefore miss stored balances
whose IDs no longer exist in the chart of accounts. A journal audit
cannot necessarily detect an orphan projection either. Such records
must not be silently called financially complete.

## Implementation (read-only)

Authenticated active owner/admin/accountant callable endpoints:
- `startAccountingBalanceProjectionScan({storeId})`
- `advanceAccountingBalanceProjectionScan({storeId,runId})`

An independent, bounded read of
`stores/{storeId}/account_balances` ordered by full document name.
One transaction reads up to 40 balance documents (+1 pagination
lookahead), and looks up the corresponding chart account by the **actual
balance document ID**. The scan never trusts the mutable embedded
`accountId` when deciding which account to inspect.

Each balance checks:
- corresponding chart account exists and belongs to the tenant;
- stored balance is not attached to a non-posting chart header;
- embedded `storeId`/`accountId` and account/balance currencies match;
- debit and credit amounts are nonnegative safe integers;
- signed net value is safe and equals debit minus credit.

The server-owned checkpoint lives under
`stores/{storeId}/accounting_balance_path_runs/{runId}`. It stores a
cursor, bounded samples and aggregate counters: all balances checked,
invalid stored documents, missing chart accounts, header balances,
currency mismatches and invalid money/net values. Advancing the same
run is serialized by Firestore transactions, and completion is
idempotent. Security rules deny client read/write of checkpoints.
No original account, journal, projection or inventory record is changed.

## Consolidated report change

`getUnifiedAccountingAuditReport` **now requires**
`balanceRunId`, referring to a fourth independently completed V2
audit. Failure to provide an existing valid run is a callable error;
an unfinished run produces `verdict: incomplete`, not a falsely
positive summary. A completed scan with invalid balances creates
`issues_found` and detailed findings under
`checks.storedBalances` regardless of whether the first three
independent scans agreed.

The output `schemaVersion` is now 2 and includes
`runIds.balanceRunId`. Existing clients/workflows of this unpublished
audit-only callable must be updated to provide the fourth run. This
does not change any V1 interface or user-facing accounting report.

## Explicit limits

- Source scans remain **non-atomic across calls**; there is no
  immutable accounting cutoff or consistent point-in-time snapshot.
- This is a stored-balance census, not an independent recomputation of
  balances from every underlying debit and credit.
- Balances inserted/deleted/updated before a paging cursor between
  calls can evade discovery; stable historical versioning remains
  necessary for certification.
- Run records must still receive retention/cost/rate controls and
  lifecycle orchestration before broad deployment.
- Do not merge, deploy or claim system-wide financial sign-off solely
  on passing CI.

## Acceptance

Emulator tests cover normal stored projections, nonexistent chart
accounts, corrupt identity/money/currency, non-posting header
projections, paginated concurrent execution, invalid checkpoint
rejection, revocation and unified report findings. Firestore
security-rules tests reject forged reverse audit checkpoints.

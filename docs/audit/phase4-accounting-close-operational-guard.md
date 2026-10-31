# V2 — controlled accounting freeze, evidence-only close, and reopen

Implemented 2026-10-24 on draft audit branch only. **No Firebase deployment,
no merge, no V1 write or migration.**

## Closure protocol

1. The active store **owner/admin** invokes
   `beginAccountingClose({storeId,throughDate:'YYYY-MM-DD'})`. A validated UTC business cutoff is required. An atomic Firestore transaction reads
   membership and sixteen mutation-epoch shards, changes the
   `accounting_period_control/current` document to `status:locked`,
   and creates a separately retained `accounting_close_events/{closeId}`
   event. No client can forge these records.
2. The system **immediately prevents new financial writes** through the
   instrumented V2 Cloud Functions. All protected transaction handlers read
   the exact close-control document in their transaction *before* changing
   source data. A competing begin/commit on that document forces an
   optimistic Firestore retry; its retry then sees the lock and fails closed.
   Protected paths include journal posting, transfers, expenses,
   party receipts/payments, purchases and sales, cheque settlements,
   repair operations, purchase-order receipts, inventory movements, and
   chart modifications. Existing idempotent retries never become a
   partial write.
3. While locked, the authorized auditor starts and completes all four
   historical checks (ledger, journal-header lines, orphan-path census,
   reverse account-balance census). Since instrumented writes are locked,
   their posting epoch stays unchanged across the scan. Out-of-band
   privileged sources still require organizational access restrictions.
4. The active store **owner/admin** invokes
   `finalizeAccountingClose({storeId,ledgerRunId,journalRunId,orphanRunId,
   balanceRunId})`. One transaction reads membership, the current close,
   all four immutable run-checkpoint results and current revision shards.
   It rejects incomplete, contradictory or stale evidence. The result
   stores the run identifiers, the close event and a retained `closed`
   write block. Financial posting does **not** resume automatically. After reopening, the closed-through UTC date is retained and posting commands with dates on or before it remain prohibited.
5. To resume posting, owner/admin must explicitly invoke
   `reopenAccountingClose({storeId,reason})` with a 12–400 character
   explanation. An immutable activity event records who reopened, why,
   and which close was unlocked. **The old close evidence remains
   historically non-certifying**, particularly after reopening.

## What has NOT been certified

- This is a **global operational posting freeze** during the audit, followed by a monotonic UTC closed-through business-date guard after reopening. It is **not** an immutable Firestore historical snapshot nor a regulator-certified close.
- Firebase Admin SDK and other privileged service identities bypass
  Firestore rules, so unauthorized imports/scripts/console edits are
  outside the lock. Production IAM must restrict edit permissions,
  supply separate service accounts for read-only auditors, log
  privileged database mutations and require controlled import/migration
  tooling. No in-code logic can override administrator credentials.
- Four audits can still omit historical records if the initial source
  was corrupt in ways not discovered by their indexes; balanced
  postings are not proof of valid underlying business transactions.
  Monetary totals from independent postings still require
  reconciliation against parties, inventory, taxes and actual bank
  statements and a reviewed historical cutoff/version scheme.
- `certified:false`, `immutableHistoricalSnapshot:false`,
  and the `NO_IMMUTABLE_ACCOUNTING_CUTOFF` finding remain deliberately
  present. **Do not label the controlled close as a regulator-certified
  balance or a historical accounting sign-off**.
- Before production: run data-scale tests, permission/rollout checks,
  Flutter workflow acceptance, financial reversal tests, period boundary
  checks and a human-reviewed migration/rollback plan.

## Test gates

Firebase Emulator tests cover freezing before source scans, immediate
journal/inventory/chart write denial, four-scan finalization, stale and
missing evidence rejection, owner/admin permissions, reasoned reopening,
transaction idempotency and unchanged financial projections while
locked. Rules tests deny forged client close controls and events.
All existing Firebase/Flutter/CI suites must pass.

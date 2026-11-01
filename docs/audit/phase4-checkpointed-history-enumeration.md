# Phase 4 — checkpointed historical source enumeration (first executable slice)

Date: 2026-10-24  
Branch: `audit/systematic-v1-parity-20261023`, draft PR #1.

## Actual scope: **not** a certified reconciliation

This adds a *durable enumeration foundation*, not a historical trial balance
or general ledger balance certificate. The existing bounded
`auditAccountingIntegrity` remains unchanged and is not bypassed.

Two **new** authenticated callable endpoints:

- `startAccountingHistoryScan({storeId})` creates a server-owned checkpoint
  document under `stores/{storeId}/accounting_audit_runs/{runId}`.
- `advanceAccountingHistoryScan({storeId, runId})` reads at most 101
  documents from the current **allowlisted** direct collection, counts
  at most the first 100, and updates cursor + counts atomically through
  a Firestore transaction. The extra document is a completion probe.
  Each invocation advances one page. When a phase ends the next phase starts
  on a subsequent invocation; the final state is
  `status: enumeration_complete`, **not** `healthy` or `certified`.

Phases (server-defined, no arbitrary client collection path):

`accounts`, `account_balances`, `journal_entries`, `parties`,
`party_balances`, `party_ledger_entries`, `products`,
`inventory_movements`.

The cursor is a document ID ordered by `__name__` in one direct
collection. It is persisted in Firestore and refreshed on each invocation,
so a process restart or caller reconnect need not restart the count.
Transactions serialize competing advances; failures cannot commit partial
checkpoint state. Completed runs are idempotent for further calls.
Only the creating user, **while still** active owner/admin/accountant in
that store, may advance the run. Server-managed checkpoints are
client-inaccessible under Firestore Security Rules.

Each response explicitly exposes:
`scope: document_inventory_only`, `certified: false`,
`consistency: non_atomic`, per-collection counts, global document count,
phase, and current run status. It does **not** expose financial records or
claims about opening balances, debit/credit, currencies or stock totals.

This implementation stores audit metadata, **not** accounting entries,
balances, product stock or historical financial records.

## CI and tests

Added `functions/accounting_history_scan.test.js` to backend emulator CI:
- resume across page boundaries and eight collections, repeat-safe final
  response and untouched source documents;
- concurrent advances cannot double count a page;
- reject unauthenticated, unrelated and deactivated memberships;
- reject corrupted persistent checkpoints without source mutations.

Added a Firestore rules test proving an owner, accountant or stranger
cannot directly read/write the audit run checkpoints.

**Verification condition:** record a passing GitHub Actions run for the
final commit before considering this slice verified.

## Deliberately unfinished phases / risks

1. This is **document enumeration**, not journal-line enumeration, a debit/
   credit aggregation, a financial reconciliation, or an export. Nested
   journal subcollections and indexed orphan discovery are not included in
   this new runner yet.
2. The source is **non-atomic across steps**. Inserts/deletions or changes
   between pages can change the dataset and lead to missed, duplicated or
   out-of-date values. A real financial sign-off needs an auditable posting
   cutoff, source versioning or a consistent snapshot strategy.
3. No retention/TTL policy, per-user active-run cap, automated scheduler,
   scheduled throttling, or resumable per-account aggregation exists yet.
   Every page consumes read/write operations when invoked; test on isolated
   V2 Firebase first.
4. No client UI or automatic loop calls these endpoints in this slice.
5. This does **not** remove the 10,000-per-collection/30,000-overall limit
   of `auditAccountingIntegrity`. It provides the safe checkpoint mechanism
   to build a separate verified full-history reconciler afterward.
6. Android/iOS Firebase setup, full V1 UI parity, accounting reversals,
   real V2 E2E, performance and release acceptance remain open.

No production deploy, V1 changes, financial postings, ledger correction,
balance rewrite or V1/V2 data migration.

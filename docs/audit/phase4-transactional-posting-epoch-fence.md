# Phase 4 — transaction-bound, sharded posting-change fence

Date: 2026-10-24. Branch `audit/systematic-v1-parity-20261023`.
**Audit-only implementation.** No deploy, merge, accounting data repair,
V1 synchronization, historical migration or financial certification.

## Problem

The four existing V2 audit scans (account-ledger, journal headers,
journal-orphan paths, and stored GL balances) were individually
checkpointed but could read different financial eras. Even when
per-currency turnovers and closing totals were equal, a set of new
balanced postings could arrive between audit runs and be overlooked
by simple aggregate checks.

## Backend posting epoch

The nine V2 server-side journal posting transaction paths
(manual journals, account transfers, expenses, party payments, purchases,
sales, cheque settlements, repair invoices, repair advances/payments)
now call `markJournalPosting(tx, storeRef, journalRef.id, FieldValue)`
**inside the same Firestore transaction** that writes journal headers,
lines, and GL balance projections.

A deterministic SHA-256 hash of the journal-entry ID selects one of
16 server-owned documents under
`stores/{storeId}/accounting_posting_epochs/{00..15}`.
Each committed financial posting increments that shard's sequence,
using Firestore's atomic increment, and records server update time.

- If the posting transaction rolls back, neither journal/GL nor
  its shard update commits.
- An idempotent replay of a previously posted request returns before
  reaching this update. No duplicate revision or journal is written.
- The sixteen shards reduce, but **do not eliminate**, hotspot risk;
  load testing, maximum write throughput and shard-count sizing are
  release-gating work.
- Firestore rules deny all client reads/writes to these internal shard
  documents. Server/Admin credentials remain trusted.

## Audits

Every new audit run saves a 16-integer `postingEpoch` baseline.
Every `advance...` checks the current epoch **inside its Firestore
transaction**, before advancing the cursor and writing checkpointed
evidence. If it differs, the run becomes terminal
`status:source_changed` and does not produce misleading completion.

The unified report reads all four run checkpoints and the current
posting shards in a single Firestore transaction. If the saved epochs
disagree with each other or with current values, it returns
`verdict:source_changed`, `complete:false`, with finding
`BACKEND_FINANCIAL_POSTING_EPOCH_CHANGED`.

The report includes `postingEpochGuardApplied:true` and
`checks.postingEpoch` showing cross-run and current matches.
All existing evidence remains explicitly non-certifying:
`certified:false`, `accountingCutoffApplied:false`,
`sourceSnapshotGuaranteed:false`.

The four audit checkpoint schemas are bumped: ledger v4, journals v4,
orphan paths v2, reverse balances v3. Their old, partially completed
checkpoints cannot be promoted into a fenced audit; restart them.
Unified response schema version is now v4.

## What this does NOT guarantee

The posting epoch is **not** an immutable historical cutoff and does
not provide a true Firestore snapshot across requests. It currently
covers only the identified server journal/GL posting transactions in
`functions/index.js`.

Not covered by the epoch:
- manual Firebase Admin writes, imports, scripts or Cloud Functions
  outside the marked posting paths;
- chart-of-accounts changes performed through client-authorized
  `accounts` writes;
- modifications to existing documents that bypass the normal posting
  code, unversioned legacy data, deletions, restorations or migrations;
- unrelated party/inventory projections without a journal posting.

The audit may still have untracked or compensating historical changes,
and its financial results **must not** be certified.
Before any production deployment, audit all other server/client
mutation paths, design immutable append-only accounting events or a
true versioned cut-off protocol, evaluate costs and contention at
sustained write throughput, and adopt explicit backfill/migration
policies for existing stores.

## Regression tests

Tests must prove: a real manual journal posting increments one shard
exactly once, concurrent replay does not increment again, aborted
posting leaves no shard; all four in-progress scans detect a
transactional posting as `source_changed`; independent completed
runs captured before/after a posting never get combined into a clean
report; shard tampering fails closed; clients cannot forge the source
marker; and the complete existing Flutter/Firestore test matrix passes.

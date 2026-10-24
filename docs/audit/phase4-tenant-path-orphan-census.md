# Phase 4 — bounded tenant-path orphan journal line census

Date: 2026-10-24. Audit-only branch
`audit/systematic-v1-parity-20261023`. No production deployment.

## Purpose

Previous account and header audit readers covered:
- chart-account-indexed journal lines with the **correct embedded** `storeId`;
- direct journal lines under **existing** header documents.

Firestore can retain `journal_entries/{missingHeader}/lines/{line}` when
the journal header itself is deleted. If those descendants also have
a missing/wrong `storeId`, they are absent from both preceding scanners.
This new audit independently enumerates line documents by their
**actual Firestore document paths**, never by an embedded identifier.

## Endpoints

Only active owner/admin/accountant membership may call:

- `startAccountingOrphanPathScan({storeId})`;
- `advanceAccountingOrphanPathScan({storeId,runId})`.

The creating user and tenant are fixed by the server-owned checkpoint at
`stores/{storeId}/accounting_orphan_path_runs/{runId}`. Firestore security
rules reject every client read/write. No source accounting record changes.

The collection-group `lines` query is ordered by the **full**
document name, starts at the requested store's document reference, and
advances with a persistent full-path cursor. It reads at most 41 group
documents per request (40 used + one probe), **regardless of the
number of stores or historical records**. Traversal stops at the first
document outside the exact `stores/{storeId}/` path prefix. Other
`lines` collections (invoices etc.) may be traversed but are never
reported as journal lines. One foreign document can appear as a
pagination end sentinel; no foreign path/content is returned to users.

For journal line paths precisely matching
`stores/{storeId}/journal_entries/{entryId}/lines/{lineId}`, the scan
reads the **actual parent** journal header and counts missing headers.
Orphan evidence is reported whether embedded line.storeId matches,
is wrong or is absent. Only up to 20 orphan path samples are retained
per run. The cursor and counts commit atomically inside a transaction,
avoiding double counting on overlapping advance invocations.

## Strict budgets and semantics

Maximum 100,000 **scanned collection-group documents per run**.
This includes invoice/non-journal `lines` records. If the store's
line history exceeds this budget, status becomes `budget_exhausted`,
**never `enumeration_complete`**. This is a budget, not proof the
source collection is bounded. There is no synchronous unlimited scan.

Responses always include `certified: false`,
`consistency: non_atomic`, `accountingCutoffApplied: false`.
This is an orphan-census observation, not proof of an immutable journal
or a point-in-time balance sheet. Changes to paths/parent headers while
a run is progressing can affect the census.

## Remaining checks

- Implement actual immutable accounting periods/as-of cutoff and a
  stable snapshot/version boundary; this scan does NOT supply one.
- Merge this census with the journal, GL/trial-balance and coverage
  results into a user-facing **non-certifying** audit summary.
- Determine retention/TTL and rate limits for historical scans,
  validate performance/cost at realistic scale, and complete V1 UI
  parity and production-like V2 Firebase acceptance tests.

No V1 data is accessed or migrated. The audit PR remains draft.

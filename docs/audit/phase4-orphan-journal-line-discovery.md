# Phase 4 — indexed orphan journal-line discovery

Date: 2026-10-24  
Scope: read-only V2 accounting audit, isolated branch
`audit/systematic-v1-parity-20261023`, draft PR #1.

## Failure mode

The earlier audit loaded `stores/{storeId}/journal_entries` and scanned each
*existing* journal document's `lines` subcollection. Firestore also permits
`stores/{storeId}/journal_entries/{deletedHeader}/lines/{lineId}` when the
intermediate header document does not exist. Such an orphan was invisible to
parent traversal, so even a numerically balanced report might have missed it.

## Implemented

1. Keep direct per-journal scans as the authoritative accounting source,
   including documents whose embedded `storeId` is missing or invalid.
2. Add an independently bounded discovery query:
   `db.collectionGroup('lines').where('storeId', '==', storeId)`, paginated
   in document-path order. It may return sale/purchase invoice lines too.
3. Verify the full *reference path*, never just the embedded `entryId`:
   `stores/{storeId}/journal_entries/{entryId}/lines/{lineId}`.
   Never report lines under `sales`, `purchases`, other tenants, or other
   arbitrary nested paths as journal orphans.
4. Compare that reference-path `entryId` against the complete scanned
   journal-header ID set. Emit `ORPHAN_JOURNAL_LINE` with the full reference
   path when the parent header is absent. This is an audit issue only;
   no cleanup, journal recreation, postings or balance mutations.
5. Account for all indexed discovery reads **including invoice lines** in
   the same 30,000-document scan budget; maximum per discovery collection:
   10,000. When the budget is exhausted, return `status: incomplete`
   instead of certifying an incomplete dataset.
6. Return `checked.indexedLineDiscovery` and
   `orphanDiscoveryCoverage: matching_embedded_store_id_only`.
   Flutter now surfaces the indexed read count and this limitation.

## Indexing requirement

`firestore.indexes.json` declares a collection-group ascending single-field
index for `lines.storeId` via `fieldOverrides`. The index must be available
in the isolated V2 Firebase environment before running the callable there.
This commit has not deployed the index or any Cloud Function to production.

## Tests

- Pure unit tests: valid orphan detection, invoice/foreign-store path
  exclusion, invalid journal-ID set, and exhaustion of a zero-document
  read budget.
- Emulator tests: a nested ledger line under an actually absent journal
  header produces an orphan issue without mutating that header or line;
  a foreign-store line with a spoofed embedded `storeId` does not appear
  as a tenant-owned orphan.
- Flutter model test: verifies coverage metadata and indexed document count.

**Acceptance:** a successful GitHub Actions run for the final code commit
must be observed before marking this change test-verified.

## Explicitly unresolved coverage / release gates

- An orphan ledger line with a *missing or incorrect embedded storeId* is
  not found by this indexed query. Discovering **all** such records demands a
  different, authorized path-scoped historical export/index strategy, not
  a global unrestricted cross-tenant scan.
- Store-wide group scans include invoice lines and cannot certify very
  large stores at the single-call limit. The next architectural gate is
  checkpointed/resumable accounting reconciliation with persistent cursors,
  bounded costs and a controlled reporting cutoff.
- This audit is `consistency: non_atomic`: querying headers and descendants
  at different times is not a point-in-time certified snapshot.
- No opening-balance normalization, balance recalculation, historical
  backfill, automatic financial correction, production deployment, V1
  modification or V1/V2 data migration has occurred.

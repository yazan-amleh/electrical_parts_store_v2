# V2 migration status

V2 is a new application and a new data set. It is not synchronized with V1 during the current operating year.

## Current branch

- Repository: electrical_parts_store_v2
- Branch: v2/foundation
- Database policy: Firebase first, behind repository contracts
- V1 production data: untouched
- V2 production writes/deploys: not performed

## Completed foundation

- Layered Flutter modules with domain, data and presentation boundaries.
- Firebase access isolated in repositories and Cloud Functions.
- Atomic posting for journal entries, account projections, party projections and inventory effects.
- Idempotency for retriable commands and an offline command outbox.
- Firestore rules proposal and emulator tests.
- Accounting audit callable and UI.
- Repair workflow and accounting contract.
- Cash/bank overview, canonical operational reports and CSV clipboard export.
- CI checks for JavaScript syntax, formatting, analyzer, Flutter tests and Firestore rules.

## Release gates still open

1. Complete remaining UI parity and responsive review.
2. Finish PDF/print report adapters, pagination/aggregation for large reports,
   and the remaining advanced analytics.
3. Expand emulator scenarios, including concurrent retries and cheque bounce.
4. Run a clean-data acceptance pass with representative store workflows.
5. Configure the separate V2 Firebase project, then deploy only after the
   rules and functions review is approved.

No V1 customer or transaction migration is implied by this document. Migration, if desired after year-end, will be a separate audited project.

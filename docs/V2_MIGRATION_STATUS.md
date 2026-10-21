# V2 migration status

V2 is a new application and a new data set. It is not synchronized with V1 during the current operating year.

## Current branch

- Repository: electrical_parts_store_v2
- Branch: v2/port-v1-complete
- Database policy: Firebase first, behind repository contracts
- V1 production data: untouched
- V2 production writes/deploys: Storage and Cloud Functions intentionally deferred; Firebase Auth, Firestore rules and direct reads are being verified

## Implemented V2 parity slices

- Layered Flutter modules with domain, data and presentation boundaries.
- Firebase access isolated in repositories and Cloud Functions.
- Atomic posting for journal entries, account projections, party projections and inventory effects.
- Idempotency for retriable commands and an offline command outbox.
- Firestore rules proposal and emulator tests.
- Accounting audit callable and UI.
- Repair workflow and accounting contract.
- Cash/bank overview, canonical operational reports, sales analytics, CSV clipboard export, PDF/print/share adapters, secure chat with attachment storage, notification-token registration, and participant-only push delivery.
- CI checks for JavaScript syntax, formatting, analyzer, Flutter tests, Firestore rules, and Storage rules with emulator coverage.
- Storage emulator coverage for participant-only chat attachment read/write, outsider denial, path spoofing denial, and owner-only deletion.
- Cheque settlement emulator coverage for concurrent customer-bounce retries, idempotent replay, balanced customer-side reversal, and supplier-bounce reversal.
- Notes, activity log and the store assistant are wired through repository contracts with user/store-scoped access.
- A clean-data domain acceptance scenario covers a fresh store workflow across sales, purchases, customer/supplier payments, repair commands, balanced ledger projections, cross-store rejection, and idempotent replay.

## Recently closed gates

- Secure Storage attachment rules are verified in CI (16 passing).
- settleCheque is verified in CI under concurrent retries and repeated replay (2 passing), including customer and supplier bounce accounting paths.
- Notes ownership and read-only activity-log rules are verified in the Firestore emulator; note domain behavior is covered by Flutter tests.

## Release gates still open

1. Finish responsive and print visual review across representative V1 workflows.
2. Review all PDF/print layouts on phone and desktop, including the V1-specific documents now implemented.
   Operational reports and sales analytics use paginated reads with a visible safety cap.
3. Run the server-backed clean-data acceptance pass with representative store workflows; the domain-level fresh-store scenario is now covered.
4. When billing is upgraded to Blaze, deploy Cloud Functions and Storage rules, then run the server-backed smoke test. Until then, do not use Storage uploads or callable posting flows against production.

No V1 customer or transaction migration is implied by this document. Migration, if desired after year-end, will be a separate audited project.

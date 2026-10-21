# Electrical Parts Store V2

V2 is a clean rebuild of the electrical-parts and accounting platform.

## Direction

- V1 remains a separate live product until the end-of-year transition.
- V2 starts with fresh data and a separate Firebase project.
- Posted journal entries are the accounting source of truth.
- Drafts never affect balances or reports.
- Stored balances are rebuildable projections, not independent truth.
- Every business command is idempotent.
- UI depends on application use cases and repository contracts, never directly on Firebase.
- Firebase is the first adapter; the domain and application layers remain database-portable.


## Implemented accounting commands

- Sales and purchases post journal lines, inventory movements, stored balances, and party projections atomically.
- Customer receipts and supplier payments update the party subledger and control accounts atomically.
- Operating expenses support cash, bank, card, and supplier-credit posting with optional input tax.
- Internal transfers move value between liquid asset accounts through a balanced journal.
- All callable commands validate tenant membership, account type/control type, currency, idempotency, and posting roles.
- Transient callable failures can be saved in the Firestore outbox and retried safely later; expired processing leases are recoverable.
- The V1-to-V2 screen inventory is tracked in `docs/v1_feature_parity_matrix.md`.

## Current branch

The `v2/port-v1-complete` branch contains the V2 parity implementation: authentication, store membership, inventory, sales, purchases, parties, accounting, offers, repairs, reports, notes, activity log, chat, settings and Firebase access. V1 remains untouched.

## Local setup

1. Install Flutter and Dart.
2. Run `flutter pub get`.
3. Add the new V2 Firebase configuration files locally; never commit credentials.
4. Run `flutter analyze` and `flutter test`.

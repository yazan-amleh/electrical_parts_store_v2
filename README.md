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

## Current branch

The `v2/foundation` branch contains the initial project and accounting-domain foundation. Feature parity with V1 will be ported module by module and verified with acceptance tests.

## Local setup

1. Install Flutter and Dart.
2. Run `flutter pub get`.
3. Add the new V2 Firebase configuration files locally; never commit credentials.
4. Run `flutter analyze` and `flutter test`.

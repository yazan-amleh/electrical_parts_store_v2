# Session hardening: live membership and tenant switching — 2026-10-23

## Verified implementation

Compared against V2 source branch `v2/port-v1-complete`. Auth/session improvements exist on the isolated `audit/systematic-v1-parity-20261023` development branch; **not merged or deployed**.

### Actual changes

- `StoreMembershipWatcher` is a separate optional domain interface, keeping existing read-only fakes/repositories compatible.
- Firestore `getMembership` and selected store lookup use `Source.server` so authorization is not granted from an offline cache.
- Firestore member snapshots are observed with metadata changes; cached-only results cannot grant a `ready` session. If connectivity is lost, the UI withdraws the ready state; a fresh server snapshot restores it.
- Missing or inactive membership removes the current membership and opens the store setup/recovery path; changes of active role update `AuthSessionController.membership`.
- Session generation checks plus watcher cancellation prevent stale responses and old-store snapshot events from reopening previous tenant sessions after store selection, signout, or newer auth events.
- `AuthGate` keys the entire stateful AppShell by user + store + role, forcing its stateful views/navigation to be rebuilt when the security principal changes.
- An authenticated user can open `تغيير المتجر` from the app drawer; switching attempts to unregister notifications for the old tenant.
- Failed membership lookup exposes a store-selection escape hatch rather than trapping the user in the generic error screen.
- The member reader tolerates omitted redundant `storeId`/`userId` fields on older V2 documents (the document path authenticates their identity) but requires `isActive == true` and rejects any mismatched identity fields.

### Confirmed test results

GitHub Actions: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39914172464

Source commit: `860c99dc5114330a99c2864d9cda7a260037565a`.

- 102 Flutter unit/widget tests: PASS. Seven new tests cover live revocation, role downgrade, old-store event isolation, logout, offline watcher fail-closed/reconnect recovery, delayed login after signout, and mismatched tenant membership.
- 20 Firestore/Storage rules emulator tests: PASS.
- 8 Cloud Functions/Node emulator tests: PASS, 0 failures.
- Dart formatting and `flutter analyze`: PASS.

### Important unresolved release gates

- No live device build exists: `android/**` and `ios/**` scaffolding and real V2 Firebase app registration identifiers are absent. Fail-closed configuration support is already in source; it is not a device registration.
- No complete, deployed Firebase V2 E2E test has been run. Membership watcher behavior is tested with a controlled stream fake and Firestore rules are separately tested in the emulator. A real Firestore snapshot lifecycle test should verify revocation on connected devices and the offline/online transitions.
- The selected-store preference is **not** an authorization grant. The server always checks active membership, and each financial Cloud Function must independently verify it.
- User invitation and multi-store discovery are not complete; existing-store selection requires a store ID and a pre-provisioned membership.
- Runtime Firebase, Storage, Functions, notification permissions and platform IDs need end-to-end tests in an isolated V2 environment before release.
- Full UI parity with V1, accounting correctness and all other features are separate acceptance gates.
- Any store-scoped background tasks and device notification subscriptions require targeted tests on switching/revocation.
- **No deploy, production data write or V1 source/customer-data modification was performed.**

## Next execution order

1. Confirm source test suites stay green while preparing a safe, isolated V2 Firebase environment.
2. Finish Android/iOS scaffolding from registered V2 app identities; do not invent IDs or reuse Web app ID.
3. Add end-to-end tests of auth restoration, actual Firestore membership streams, owner/member role transitions and device token handling.
4. Confirm store invite/discovery/selection UX and permission matrix.
5. Continue into full accounting-foundation contract and postings/ledger audits after session lifecycle gates.

## Web release build acceptance (non-deploy)

Additional commit `04a8d18cafe82bb603149dd4e01d45d4dbe904d1` added a mandatory Web Release CI compilation step.

Run https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39914641471 verified **PASS** for:
- Dart formatting and Flutter analyzer
- Flutter tests: **102 passed**
- `flutter build web --release`: **PASS**, generated `build/web`
- Firestore / Storage rules: **20 passed**
- Cloud Functions emulator: **8 passed, 0 failed**

This is a compile-only check: no Hosting deploy, no remote Firebase writes, no browser login or device E2E. Android/iOS app registration/scaffolding and final V1 parity remain blocked/unverified.

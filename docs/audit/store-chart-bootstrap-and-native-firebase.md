# V2 store bootstrap + native Firebase readiness — 2026-10-23

## Bootstrap change: new stores only

The server-only callable `createStore` now validates the **version 2, 27-account** default chart and uses a **single Firestore transaction** to create:

1. `stores/{autoId}` with owner, name, currency ILS, `initialChartVersion = 2` and `initialChartAccountCount = 27`;
2. `stores/{autoId}/members/{uid}` with active owner membership;
3. `stores/{autoId}/accounts/{accountId}` for the 27 definitions in `functions/default_chart_of_accounts.json`;
4. `user_store_preferences/{uid}` for selection and replay protection.

Accounts are non-posted definitions only. **No journal entries, account balances, opening capital, cash or inventory values are invented.** The trial balance query intentionally resolves absent balances as zero. All writes either commit together or roll back together.

Manifest validation rejects duplicate IDs/codes, missing or non-header parents, mismatched parent/child types, duplicate control account types, malformed currencies and invalid account shapes. A JavaScript test compares the backend manifest **account-for-account** to the current Flutter `DefaultChartOfAccounts.forStore` definitions. Changes to either side must keep them in sync and pass CI.

Repeat `createStore` calls by the same account return the previously created `createdStoreId`, with no re-seeding or resetting existing chart definitions. This change does **not** backfill existing stores, alter historic journals, or repair existing balance differences.

### Chart version 2 — return/opening prerequisites (2026-10-27)

The template now also contains two posting accounts proven by the V1 posting
contract:

- `3400` — **حساب الأرصدة الافتتاحية**, equity, credit-normal, child of
  `3100`. V1 uses it as the counter-account for opening inventory/cash.
- `4200` — **مردودات المبيعات**, revenue/contra-revenue, **debit-normal**.
  V1 debits it when a sales return is posted.

This version bump only changes future store provisioning. Existing stores are
**not** silently mutated. Before return/opening workflows are enabled for an
existing V2 store, a separate explicit chart-upgrade gate must verify that
codes/IDs `3400` and `4200` are absent or compatible; it must never reset
balances or overwrite a conflicting account.


### Limitations / validation gates

- Completing bootstrap does not prove correctness of all posting use cases; the accounting stages require their own E2E and concurrency tests.
- The `createStore` callable is scoped to an authenticated Firebase user, not a production release by itself.
- Test first on V2 isolated Firebase emulators and then an approved non-production Firebase environment.
- No automatic migration/backfill is run on stores created with prior V2 code. Do not silently seed any established accounting books.

## Firebase platform reality

At audit time the repository contains `web/**` but no tracked `android/**` or `ios/**` Flutter platform projects. The current `lib/firebase_options.dart` includes a Web app registration for `electrical-store-v2-prod` but **does not contain native Firebase application registrations**.

The source now supports **fail-closed native configuration entry points** through compile-time Dart defines. This is preparation, **not** proof of a native app build or functioning device sign-in. It deliberately rejects missing values, a Web Firebase app ID masquerading as native, and a mismatched sender ID. `AppBootstrap` additionally checks the initialized Firebase project against `FIREBASE_PROJECT_ID`.

To finish Android and iOS setup (not yet performed):
1. Decide the final V2 Android application ID and iOS bundle ID — do not assume V1 identifiers.
2. Register these two apps under the **V2 Firebase project only**. Obtain genuine Android and iOS Firebase configuration values (never reuse V1 or the Web `appId`).
3. Restore checked-in platform scaffolding with Flutter CLI after choosing native IDs: `flutter create --platforms=android,ios --project-name electrical_parts_store_v2 .`. Specify the proper application/bundle IDs as part of native platform setup; a default `com.example` identity is not acceptable for release.
4. Configure the platform-specific Firebase project and any required native integration files for Authentication, notifications, and Storage. Verify native build settings, signing and permissions.
5. Provide the matching `--dart-define=FIREBASE_ANDROID_API_KEY=...`, `FIREBASE_ANDROID_APP_ID=...`, `FIREBASE_ANDROID_SENDER_ID=...`, `FIREBASE_ANDROID_PROJECT_ID=...`, `FIREBASE_ANDROID_STORAGE_BUCKET=...` on Android. On iOS use `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_SENDER_ID`, `FIREBASE_IOS_PROJECT_ID`, `FIREBASE_IOS_STORAGE_BUCKET`, and `FIREBASE_IOS_BUNDLE_ID` instead.
6. Build/test startup and full Authentication + create-store + reload-membership flow on physical native devices against an **isolated V2 test environment**, not production.
7. Only after approvals, plan release/deployment and migration strategy; do not deploy or write production financial data.

Use native Firebase app identifiers and runtime values appropriate to the same registered project; public client Firebase options are not server Admin credentials. Firebase Admin credentials must never be embedded in Flutter.

## Completion flags

| Check | State |
|---|---|
| Server-side atomic chart + owner bootstrap | Verified PASS in GitHub Actions run 39912061538 |
| Dart/backend chart manifest drift gate | Verified PASS in GitHub Actions run 39912061538 |
| Native configuration fail-closed validation | Verified PASS (including 5 native config tests) in run 39912061538 |
| Native Flutter Android/iOS project scaffolding | BLOCKED — no platform registrations/package IDs |
| Real Firebase V2 application end-to-end sign-in | NOT RUN |
| Production deployment/financial writes | NOT AUTHORIZED; NOT RUN |
| V1 data / source modifications | NONE |

### CI evidence (source commit `106e8490abcb6549e7cc9c4ad8c50f6ebb57fea7`)

- https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39912061538 — SUCCESS
- Flutter: 95 passed; Firestore and Storage rules: 20 passed; Functions/node emulator: 8 passed, 0 failed.
- Formatting and Flutter analyzer: passed.
- Real device and deployed non-production Firebase testing: **not performed**; still mandatory.

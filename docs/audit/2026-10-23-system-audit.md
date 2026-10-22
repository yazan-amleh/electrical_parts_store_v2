# System-wide audit — baseline (2026-10-23)

> **Audit in progress — NOT a production-readiness statement.**
> This file is based on direct inspection of repository trees and selected source files through the connected GitHub repository. No Flutter runtime, Firebase emulator, Firebase deployment, device UI, or real accounting transaction was executed during this initial audit. V1 and both databases remain unchanged.

## Immutable comparison baseline

- V1 repository: `yazan-amleh/electrical_parts_store`, branch `main`, commit `dd5a920ffee4ffadce4f3f421e3c52cc0dc2812e`, **462 tracked blobs**.
- V2 repository: `yazan-amleh/electrical_parts_store_v2`, branch `v2/port-v1-complete`, commit `7e57cce91341ed33bb5f2d8edfc350329cd16859`, **298 tracked blobs**.
- V2 source branch is 866 commits ahead of `main` and zero commits behind at inspection time; do **not** use `main` as the V2 feature-complete baseline.
- Work branch: `audit/systematic-v1-parity-20261023` from exact V2 source commit.
- **Scope exclusion:** `lib/salon_booking/**`, salon and bookings. No transfer or synchronization of V1 customer/store data.
- The audit branch is not the branch targeted by the manually triggered production deployment workflow, which currently checks out `v2/port-v1-complete`; no deployment authorized.

## Verified architectural paths

### V1 actual startup and UI
```
lib/main.dart
  -> Firebase.initializeApp
  -> _initializeServices (Get.put controllers)
  -> MultiProvider (also creates controller instances)
  -> GetMaterialApp / AuthController
  -> LoginScreen OR HomeScreen
  -> home_screen.dart navigation + drawer / feature screens
  -> V1 controllers + services -> Firebase
```
Relevant evidence: `lib/main.dart`, `lib/controllers/auth_controller.dart`, `lib/views/screens/home_screen.dart`, `lib/views/widgets/custom_drawer.dart`, `lib/routes/app_routes.dart`.
This is a behavior/UI reference, **not** an architecture to copy.

### V2 actual startup and write paths
```
lib/main.dart
  -> AppBootstrap.initialize (APP_ENV, USE_FIREBASE, FIREBASE_PROJECT_ID, STORE_ID)
  -> Firebase.initializeApp(DefaultFirebaseOptions.currentPlatform)
  -> explicit AppDependencies (Firebase repositories, Cloud Functions, StoreSession)
  -> AuthSessionController.start / FirebaseAuth authStateChanges
  -> StoreMembershipRepository.getMembership(stores/{storeId}/members/{uid})
  -> AuthGate -> LoginPage or AppShellPage
  -> feature presentation -> repository -> Firestore read
                                      -> callable Cloud Function write
                                      -> command outbox on selected transient failures
Independent entry points:
functions/index.js -> onCall handlers, onDocumentCreated chat notification
firestore.rules; storage.rules; scheduled/manual CI and deploy workflows
```
Confirmed V2 structure: `lib/core`, `lib/app`, `lib/features/<feature>/{domain,data,presentation,application}` (application only where needed), `lib/infrastructure`, `functions/index.js`, `test/**`, `firestore_rules_test/**`.

## Confirmed defects and gaps, ordered by severity

| ID | Severity | Direct evidence | Impact | Required remedy / evidence gate |
| --- | --- | --- | --- | --- |
| A-001 | P0 Android / iOS | `lib/firebase_options.dart` throws `UnsupportedError` for Android and iOS; `AppBootstrap.initialize` invokes it at startup whenever Firebase is enabled | Native app cannot finish Firebase initialization | Register real **V2** per-platform Firebase apps and config; native start + sign-in smoke test. Do not invent app IDs |
| A-002 | P0 onboarding | `AuthSessionController.register` only creates Firebase Auth user, then immediately loads `stores/{storeId}/members/{uid}`; no owner/store provisioning occurs in that flow | Newly registered account without existing membership reaches authorization error | Design and implement secure owner bootstrap + invite/join flow; test clean database, duplicates, unauthorized user and concurrent creates |
| A-003 | P0 bootstrap contract | `firestore.rules` allows `stores/{storeId}` creation with matching `ownerId` but limits `members/{userId}` create to `canManageStore`, which itself requires an existing active membership | A brand-new owner cannot self-create the first membership through client-side rules | Atomic, server-authorized bootstrap or guarded rules relying on `getAfter`, with owner takeover and race tests |
| A-004 | P1 tenant selection | `AppRuntimeConfig.fromEnvironment` defaults `STORE_ID` to `v2-dev-store`, even in production; session is bound to that one store | Registration does not imply store creation/selection; multiple-store workflow cannot be claimed | Decide and implement store discovery/selection plus explicit bootstrap/membership lifecycle; no implicit cross-store privilege |
| A-005 | P1 platform/env integrity | `FIREBASE_PROJECT_ID` is exposed as runtime config but `AppBootstrap` initializes the compiled Firebase options without checking their project ID against it | User-supplied configuration can differ from actual connected project unnoticed | Add fail-closed Firebase project ID guard, with isolated unit tests |
| A-006 | P1 UI parity | V1 `LoginScreen` is a 661-line animated/gradient screen with remember-me toggle; V2 `LoginPage` is a separate 212-line simple Card. V1 `HomeScreen` contains bottom navigation and custom drawer; V2 `AppShellPage` implements separate module navigation. V1 uses `NotoSansArabic` in one theme; V2 uses a different theme and assets | Equivalent function cannot be counted as visual/behavioral parity | Port the original V1 widgets and styles through V2 view-model/actions; verify pixels, every button and responsive states |
| A-007 | P1 backend maintainability | `functions/index.js` has ~7,656 lines / ~229 KB and contains numerous financial callable handlers and independent event triggers | Large change blast radius, harder to review transaction boundaries | Create thin stable exported endpoints; extract authenticated commands, posting engines, projections and notifications in small steps with emulator regression |
| A-008 | P1 acceptance coverage | `docs/V2_FEATURE_PARITY_MATRIX.md` marks many modules “Complete” while explicitly states full responsive UI review is planned and end-to-end server-backed accounting scenarios remain partial | Current “Complete” labels cannot prove V1 parity or production readiness | Maintain screen/action-level matrix with separate code/UI/data/security/test signoffs |
| A-009 | P1 V1 bootstrap | `lib/main.dart` creates `AuthController` through both `Get.put` and `ChangeNotifierProvider` | Potential separate session instances if copied into V2 | Preserve UI only; single V2 auth session and explicit dependencies |

**Not yet proven:** correctness of balances, inventory valuation, reversal consistency, idempotency under concurrent requests, data-loss resistance, Firebase deployment state, all UI parity, and real-device success. Existing source tests are evidence of intent, not evidence of a successful run in this audit.

## Target architecture (pragmatic feature-first clean boundaries)

1. **Presentation:** V1-derived Flutter screens/widgets/themes and router; no direct Firestore, FirebaseAuth, or financial mutation calls. View-models expose states/actions.
2. **Application:** use cases orchestrate one business operation, enforce access preconditions, return typed success/failure and idempotency keys.
3. **Domain:** pure validated models (money in integer minor units, quantity scaled integers, balanced journals, reversal rules, costing and tax policies); no Firebase dependencies.
4. **Repository interfaces:** stable contracts for reading and command posting.
5. **Data adapters:** Firestore query/mapping/Storage; Cloud Functions command adapters with user-facing error taxonomy and retry-safe outbox.
6. **Backend authority:** authenticated tenant-scoped callable endpoints; transactionally committed journal, stock and party postings; exactly one fact model with documented projections. No client-written financial projections.
7. **Infrastructure:** DI, environment guard, logging, auditing, tenant context, navigation, secret-free configuration. No V1 Firebase project references in V2.

Do not rewrite posting logic wholesale. First characterize the existing accounting contract with deterministic and emulator tests, then extract behavior-preserving modules. Keep public callable names unchanged.

## Execution order and exit criteria

| Gate | Scope | Must pass before feature signoff |
| --- | --- | --- |
| 1 | Baseline, code inventory, architecture + visual parity matrix, prioritized issues | Reproducible commit-pinned catalogs; tracked open gaps; zero V1 writes |
| 2 | main, config, platform Firebase, DI, lifecycle, errors, navigation shell | Native/Web startup in supported environments, project isolation, no accidental V1 connection, reproducible error states |
| 3 | login, register, reset, logout, membership, store owner bootstrap and permissions, original V1 auth UI | Fresh-account full onboarding on isolated V2 Firebase/emulator, restore/revoke/session races, UI screenshot/action parity |
| 4 | chart, balanced journal, ledger, balances, reversal, financial reports | Trial balance and all sources agree; duplicate/retry/concurrency/currency/rounding/reversal emulator tests |
| 5 | products/categories/units/inventory, V1 UI | Nonnegative policy where applicable, inventory and COGS reconciliation, concurrent stock tests, visual parity |
| 6 | sales/purchases/orders/returns, V1 UI | Accounting + inventory atomicity, idempotency and partial failure rollback, receipt/return scenarios |
| 7 | parties/payments/cheques/cash/banks/transfers/taxes/expenses | Party subledgers reconcile to GL; settled/reversed cheque cases; authorization per role |
| 8 | offers, repairs, reports, print/export, analytics, chats, notifications, notes, settings, user admin, activity log and any inventory leftovers | Every V1 non-excluded screen/button present; explicit role, RTL, states and export checks |
| 9 | complete regression on V2 test environment | Startup-to-report E2E; mobile/desktop visual baselines; server-backed clean-data flows; release sign-off |

Every feature must pass: source trace, contract, fix, V1 UI port, unit test, emulator integration, visual diff and regression; unexecutable tests remain **BLOCKED**, not **PASSED**.

## Environment / operational blockers

- This GitHub-based audit can inspect and commit repository source but cannot run Flutter or Firebase emulators from GitHub file operations alone.
- Native Firebase registration IDs and Android/iOS package details cannot be inferred from the Web app's Firebase configuration.
- Real V2 Firebase deployment, production writes and financial data changes require explicit approval and a separate verified release procedure.
- Any issue found in Cloud Functions or Firestore rules must be validated with isolated emulators before considering deployment.

## Next changes (non-production)

1. Land audit inventory and action-level parity matrix.
2. Add fail-closed Firebase project ID check; source-controlled unit coverage.
3. Specify/test owner bootstrap with server authority and tenant isolation, then implement as independent commit.
4. Port V1 login/register/reset styling while replacing V1 auth logic with V2 repository/controller logic.
5. Continue through all modules, preserving export names and accounting invariants.

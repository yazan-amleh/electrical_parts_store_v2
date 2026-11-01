# Auth UI port report — V1 → V2 (2026-10-23)

## Source baseline and scope

V1 main `dd5a920ffee4ffadce4f3f421e3c52cc0dc2812e`:
- `lib/views/screens/auth/login_screen.dart`
- `lib/views/screens/auth/register_screen.dart`
- `lib/views/screens/auth/reset_password_screen.dart`

V2 target: `audit/systematic-v1-parity-20261023`, based on `v2/port-v1-complete`.

## Implemented in V2

- `lib/features/auth/presentation/v1_auth_visuals.dart`: V1 blue/indigo gradients, three source-specific curve painters, 1500ms fade/slide, rounded elevated cards, logo-shaped circle, borders, error banner and primary buttons.
- `lib/features/auth/presentation/login_page.dart`: original email/password field hierarchy, show/hide password, remember-me, forgot-password navigation, login button and original-style supporting footer. Responsive wrap for remember/reset on narrow RTL phones (initial widget test caught a **38px RenderFlex overflow**, now fixed).
- `lib/features/auth/presentation/register_page.dart`: V1 name/email/password/confirmation order and navigation, connected to V2 AuthSessionController. Never grants V1 `superAdmin` or writes V1 collections.
- `lib/features/auth/presentation/reset_password_page.dart`: V1 reset layout, validators, success SnackBar and return navigation, using V2 reset repository.
- `pubspec.yaml`: SharedPreferences for saving a **remembered email only**; no plaintext password, Auth tokens or financial data stored by this feature.
- `test/auth/v1_auth_visual_parity_test.dart`: compact phone widget tests for field hierarchy, register/reset navigation, validation, and email-only remember-me.

**Branding boundary:** V1 at this commit contains photography/salon names and `assets/icon/logo.png`. Salon/booking was explicitly excluded; V2 uses electrical-store wording and an electrical-services icon instead. These substitutions are intentional, not claims of pixel-identical design. The image tiling pattern associated with the old salon logo was also not copied.

## Verified in GitHub Actions

Run: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39865212354
Commit: `752a2464aedfdb1a4f9e54900d54d76be266d8c5`

- Dart formatting: PASS
- Flutter analyzer: PASS
- Flutter unit/widget tests: **89 PASS**, including all three new V1 auth UI tests
- Firestore and Storage rules emulator tests: **19 PASS**
- Cloud Functions emulator tests: **5 PASS, 0 FAIL**

No emulator result establishes a production deployment or real-device visual parity.

## Acceptance gaps remaining

1. Compare actual V1/V2 rendered screenshots on narrow Android, tablet and Web/desktop with equal typography and locale. Automated screenshot/pixel diff has NOT run.
2. Determine final replacement branding/logo with the owner; never reintroduce salon/booking semantics to V2.
3. Confirm RTL keyboard/inset behavior and accessibility using real devices, not widget tests alone.
4. Confirm Android/iOS platform registration and native Firebase initialization; `firebase_options.dart` currently throws on native platforms.
5. Test complete V2 deployed Firebase flow with a real test account (registration → create store → owner membership → signout → restored session); no production write/deploy without approval.
6. Create and validate a default chart of accounts for new stores before allowing accounting posting.
7. Port every remaining V1 UI screen and action; passing these three UI tests does not close system-wide V1 parity.

## Acceptance state

**Auth UI source port: implemented and widget-tested. Pixel parity: OPEN. Real Firebase/device E2E: OPEN.** No V1 repo or customer data changed.

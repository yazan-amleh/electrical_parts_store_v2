# V1 personal account settings → V2 checkpoint (2026-11-01)

Branch: `audit/systematic-v1-parity-20261023`. No merge/deploy and no changes to V1.

## Delivered in V2 code

- A standalone **المعلومات الشخصية** page reachable from the existing store settings screen, separately from store membership administration.
- Current user's display name, sign-in email and email-verification state loaded from Firebase Authentication, not from Firestore store documents or guessed state.
- Editing the display name with length checks and expected-user-ID guard both before and after asynchronous operations.
- V1-style **تغيير كلمة المرور** with current/new/confirmation inputs, hide/reveal affordances and busy/validation/error/success states.
- Password changes require Firebase Authentication **reauthentication with the current password**. No password persisted to Firestore, shared preferences, logs or other storage; no password update for a different signed-in UID.
- A stale profile load for an earlier user cannot overwrite the new session's profile.

## Not yet at V1 parity

- **Profile avatar upload**: V2 now has a private owner-only gallery/file-upload path with Storage rules and validation. V1 camera capture, file-picker platform QA and optional deletion/cleanup remain pending.
- **Phone number and email changes**: Firebase Authentication email ownership requires a verified email-change flow; phone verification requires its own OTP workflow. V2 shows the login email read-only rather than claiming these are implemented.
- **Full V1 theme editor and language settings**: V2 now updates root MaterialApp theme/accent/locale, but advanced header/table styling and translation of feature screens remain.
- Browser/mobile screenshots and Firebase Auth emulator E2E (including wrong password, recent login, provider not supporting password, session switch and network errors) are release gates. Widget tests alone are not real Firebase proof.

## Next audit candidates

Theme/dark mode and language settings, then authenticated profile avatar, then a screen-by-screen visual review of V1 vs V2 (responsive, RTL, busy/empty/error and permission states). This checkpoint does not mark the system as fully migrated or production-ready.

## Addendum — app appearance and private avatar

- Added app-wide light/dark/system theme plus four accent colors using Material 3; updates occur live via the root MaterialApp.
- Saved mode/accent/language via SharedPreferences keys scoped to the signed-in Firebase UID; signing out restores safe default appearance and another user's settings never load into the active session.
- Language choice changes Flutter's standard material/widget/Cupertino locale and direction only. **Full English translation of V2 feature strings remains pending**, clearly disclosed in the UI; it is not considered V1 language parity.
- Added an owner-only account avatar path `users/{uid}/avatar/photo`, private reads, size cap 2 MB and MIME whitelist JPEG/PNG, with a file-picker/upload/preview on the personal profile page.
- The profile image intentionally uses authenticated Storage reads rather than a public download-token URL. The client checks image header bytes as well as the size, while Storage rules enforce owner/MIME/size independently.
- Requires storage emulator/security tests plus real-browser and mobile camera/gallery smoke tests before release. Camera capture is not currently implemented; gallery/file selection is.
- V1 theme editor includes additional header/table customization and translation coverage not yet migrated. **Do not mark visual or localization parity complete.**

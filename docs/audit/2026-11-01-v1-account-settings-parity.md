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

- **Profile avatar upload**: V1 permits camera/gallery. V2 deliberately does not upload to Storage without a scoped path, rules, MIME/size checks, cleanup and device/camera QA.
- **Phone number and email changes**: Firebase Authentication email ownership requires a verified email-change flow; phone verification requires its own OTP workflow. V2 shows the login email read-only rather than claiming these are implemented.
- **Full V1 theme editor and language settings** require separate app-wide theme/locale state; adding settings-only toggles without actually updating the app is not accepted.
- Browser/mobile screenshots and Firebase Auth emulator E2E (including wrong password, recent login, provider not supporting password, session switch and network errors) are release gates. Widget tests alone are not real Firebase proof.

## Next audit candidates

Theme/dark mode and language settings, then authenticated profile avatar, then a screen-by-screen visual review of V1 vs V2 (responsive, RTL, busy/empty/error and permission states). This checkpoint does not mark the system as fully migrated or production-ready.

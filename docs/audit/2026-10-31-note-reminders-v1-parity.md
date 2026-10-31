# V1 reminders → V2 delivery checkpoint (2026-10-31)

**Scope:** implementation on `audit/systematic-v1-parity-20261023` only.
No V1 changes, no Firebase deployment, no production notification send.

## Implemented (code)
- V1 note dates and `none/daily/weekly/monthly` repetition are persisted on each V2 note.
- Client sets `reminderNextAt` for server-side due queries, preserving UTC recurrence.
- Scheduled `dispatchNoteReminders` (every 5 minutes, UTC) queues due note events in the V2 database.
- One deterministic event per **store + owner + note + occurrence**; Firestore transactions advance the next due time and create the record atomically.
- Event delivery uses the existing per-store, per-user FCM token infrastructure; active store membership is checked again at send time, and invalid registration tokens are removed.
- Recipient can view the latest 100 reminder events through **Notes → bell icon → Reminder inbox**, even with no registered device.
- Firestore rules block client-created or modified events; owner-only read/list is enforced.
- Queue and delivery are bounded to 60 items each per run, and failed sending has up to three claims with two-minute leases.
- Past reminders older than 24 hours are skipped rather than blasting users with stale alerts. For repeating reminders, the next future occurrence is retained.

## Prerequisites before live use
1. **Owner approval for billing:** Cloud Scheduler and Firebase Functions usage may incur charges. Do not deploy or enable scheduled work until explicitly authorized.
2. Configure and deploy the V2 Firebase project only, including indexes, rules, and Functions; confirm the correct V2 project ID, correct service account, app Firebase config, and region.
3. FCM registration permission and valid token are necessary for Push. Verify actual Android, iOS, and Web background delivery individually; browser Push may need its own service worker and VAPID configuration.
4. Run emulator rules and Functions unit tests first, followed by real *isolated staging* E2E cases (single, recurring, modified, archived, deactivated member, no device, invalid token, repeat trigger, offline/clock skew).
5. **Existing notes written before the `reminderNextAt` field** are not automatically migrated; resaving an existing note populates the scheduling field. A backfill plan would be needed if there are many existing V2 notes.
6. Google FCM is not an exactly-once transport. Deterministic queue events prevent repeated enqueueing; retries or crash-after-send can still produce a duplicate push, so the event identifier must be used for client deduplication in a later app-level delivery-hardening pass.

## Acceptance limits
- The code is not evidence of successful live push delivery, real Firebase scheduling, or pixel-perfect V1 interface parity.
- In-app feed is read-only with 100 latest records in current store/user scope.
- No SMS fallback or billing-dependent feature is enabled.

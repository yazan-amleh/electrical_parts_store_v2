# V2 controlled accounting close — operator runbook and privileged-writer boundary

**Draft-audit branch only. No production Firebase changes or V1 mutation.**
Date: 2026-10-25.

## User-visible close workflow

The Accounting Audit page, for active store owners/admins, now exposes
a server-backed **Accounting Close** panel. No action is automatic.

1. **Begin lock** — select a UTC closing business date and explicitly
   confirm the freeze. The transaction saves the monotonic business
   cutoff and blocks journal, stock-valuation and chart changes routed
   through protected V2 Cloud Functions.
2. **Start checks** — create four checkpointed source-audit runs while
   the lock is active. Their IDs are registered on the current lock
   record. Existing runs can be resumed after a browser reload.
3. **Continue checks** — process up to eight bounded progress batches
   per operator action. Each batch executes one safe Firestore page
   across each unfinished scan. Resume until all four are complete;
   source-change, coverage-budget and mismatch findings block finalization.
4. **Finalize** — verify all four checkpoints originated *strictly
   after the active lock began*, agree by currency, match the registered
   run IDs and the frozen posting epoch, and are complete without audit
   findings other than the explicit non-certification notice.
5. **Reopen** — require a detailed reason and log a durable event.
   Operational posting is resumed but *all dated transactional postings
   on or before the closed-through UTC date remain rejected*. A new
   close date must be strictly later than the prior one.

The panel will not show financial-closure controls to an inactive
member or to a role other than owner/admin. Source UI never obtains
direct write access to close controls or audit checkpoints.

## Privileged-admin boundary: still a deployment blocker

Firestore security rules apply to **client SDK requests**. They do
**not** prevent a Firebase Admin SDK, service account, console
administrator, export/import operation or external credential holder
from writing directly to accounting source documents or modifying
close-control documents. The per-store fence guarantees only writers
that participate in its transaction protocol.

For production the operator must complete, outside this repository:
- Inventory every service account, application, scheduled job, import
  worker, console operator, backfill and migration able to write
  Firestore. Record owner, purpose, permissions and expected collections.
- Remove broad Cloud Datastore/Firestore write privileges from
  read-only analytics, reports and audit services; use separate identities
  for imports and posting services with the minimum scopes achievable
  under the actual Google Cloud IAM and database controls.
- Require every privileged accounting mutation worker to call the same
  close-control guard **inside the same transaction** and increment the
  store posting-change fence whenever relevant source data change.
- Enable and retain Google Cloud audit logging for privileged
  administrative changes and review alerts covering protected
  `stores/*/{accounts,account_balances,journal_entries,
  inventory_movements,accounting_period_control,...}` paths.
  Ensure monitoring and logging retention are scoped and tested with
  the deployment project and its billing / logging policies.
- Prohibit ad-hoc console data edits during a close. If a migration is
  necessary, establish an explicit maintenance protocol and invalidate
  affected close reports, capturing before/after checksums and source
  generations. Do **not** reuse old audit-run checkpoints.
- Test 2 concurrent posting attempts versus the begin-lock transaction,
  idempotent replays, batches with large tenant data, forced timeout,
  reopen and backdate rejection, mixed currencies, reversals, and
  restore-from-backup behavior on a nonproduction clone.
- Validate tenant membership, owner/admin recovery, browser refresh,
  interrupted batch resume and all V1 UI workflows against an agreed
  parity checklist. Approval of a single CI suite is not proof of
  every business feature or preexisting historical record.

These infrastructure/IAM actions have **not been executed** here and
must not be represented as protected by the new in-app locking code.

## Auditing vs financial certification

The four checkpointed scans and the unified report are strong
read-only consistency evidence against several classes of corrupted
postings, balances, header references and orphan lines. They cannot
alone prove completeness of records written before instrumented
tracking existed, existence of valid external bank settlements,
period-end inventory valuation, correct revenue recognition/taxes,
or an immutable historical posting/event ledger.

The implementation deliberately returns `certified:false` and
`immutableHistoricalSnapshot:false`. The human financial signoff
and production readiness gate remain separate.

## Regression coverage

- Old/mixed/fake audit run IDs fail finalization; only four scans
  started after the *current* lock can complete.
- Stored run IDs and progress survive refresh.
- Reopen preserves the previous cutoff and rejects dated back-posting.
- Rules block all client attempts to forge the control or audit state.
- A static source-mutation contract test checks all known V2 transaction
  paths have the lock guard before their writes and confirms dated
  journal/inventory posting paths enforce closed business dates.
- Final CI must pass the Flutter, Firestore rules and Functions Emulator
  test suites before the draft is considered verified.

**Release gate:** keep PR #1 draft and undeployed until the privileged
write inventory, IAM rollout plan, data-scale proof, reversal acceptance
and cross-feature parity checks are completed and explicitly approved.

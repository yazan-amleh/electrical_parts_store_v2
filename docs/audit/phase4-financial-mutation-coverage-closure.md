# Phase 4 — accounting-source mutation coverage closure (V2)

Date: 2026-10-24. Branch: audit/systematic-v1-parity-20261023.
This is an **implementation ledger**, not a financial certification.

## Protected mutation surface

| Source mutation | Entry point | Auth / write path | Same-transaction mutation epoch |
|---|---|---|---|
| Manual journal | postJournalEntry | guarded V2 callable | Yes |
| Account transfer | postAccountTransfer | guarded V2 callable | Yes |
| Expenses | postExpense | guarded V2 callable | Yes |
| Party payments | postPartyPayment | guarded V2 callable | Yes |
| Purchases | postPurchase | guarded V2 callable | Yes |
| Sales | postSale | guarded V2 callable | Yes |
| Cheque settlement | settleCheque | guarded V2 callable, limited replay-safe retry | Yes |
| Repair invoice/delivery | deliverRepair | guarded V2 callable | Yes |
| Repair advance/payment | postRepairAdvance and related repair payment path | guarded V2 callable | Yes where a journal is created |
| Standalone stock valuation movement | postInventoryMovement | guarded V2 callable | Yes, including no-journal movements |
| Chart account create/metadata edit | mutateChartAccount | owner/admin callable only | Yes |
| Direct client journal/header/line/GL balance write | Firestore rules | Always denied | No write possible with client credentials |
| Direct client account create/update/delete | Firestore rules | Always denied | No write possible with client credentials |

All transactions use 16 server-owned posting/change shards; their
revision is captured and compared throughout the **four checkpointed
historical audit scans** and their unified report. The marker is bumped
once per actual committed transaction, not on a replay that returns
before any write. A changed marker makes an in-progress audit terminal
`source_changed` and invalidates cross-run comparisons.

**Account chart operation:** use
`mutateChartAccount({storeId,operation:'create'|'update',account:{...}})`.
Account creation permits non-control account definitions. Editing permits
name, description, sort order, active flag and validated hierarchy parent;
account identity, currency, financial classification and control type
remain immutable once created. This deliberately prevents changing the
financial meaning of historical postings. A Flutter command repository
is provided to call this function. Existing read-only account queries
are unchanged. Any UI that previously wrote Firestore account documents
directly **must be wired to this callable before relying on it**; simply
changing the rules without migrating that UI would block its writes.

## Boundaries we cannot certify

- A series of Firestore reads over many transactions is **not** an
  immutable source snapshot or true historical closing-cutoff. This
  change detects instrumented mutations rather than preventing them.
- Firebase Admin SDK credentials bypass Firestore client security rules.
  An administrator/import/script/unknown privileged Cloud Function can
  write journals, balances, charts or historical metadata without
  updating this epoch. That cannot be prevented by rules alone;
  privileged write access must be restricted operationally and all
  external mutation jobs must go through the same fence protocol.
- Party directory/contact metadata and product commercial attributes
  can be updated through permitted client workflows. This version
  fences *ledger/GL, chart and inventory valuation sources*, not every
  nonfinancial directory or business metadata field.
- A full account structural redesign and import of legacy chart
  classifications requires a separately reviewed controlled migration.
  No automatic historical reclassification or balance rebuild is
  attempted.
- Chart and inventory epoch revisions may conservatively invalidate a
  GL audit even if the edit did not affect ledger amounts. Safety is
  prioritized over reducing re-scan frequency.
- A valid time-scoped close requires an **immutable posting/event-log
  model**, documented versions for *all* backdated modifications,
  controls on external privileged writers, and explicit cutoff/close
  orchestration. Never set `certified:true` merely because these
  source counters agree.
- Some V1 UI screens and full functional parity are outside this
  specific mutation-coverage batch; they require their own integration
  and end-to-end acceptance.

## Verification gates

- Chart account creates/updates, parent/tenant validation, owner/admin
  role enforcement, immutable classifications, duplicate/no-op calls,
  historical-audit invalidation.
- Client rule enforcement denies account and GL writes even for owner.
- Inventory-only valuation writes, idempotent replay, and rejection
  of invalid negative-stock writes without partial epoch increments.
- Existing cheque posting concurrency, full Functions emulator suite,
  Flutter analysis/tests/web build and Firestore security rules tests.

No production deployment, merge, V1 mutation, financial correction or
new opening-balance seed is authorized by this change.

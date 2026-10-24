# Phase 4 — stock movement currency audit guardrails

Date: 2026-10-24

Repository: `yazan-amleh/electrical_parts_store_v2`  
Branch: `audit/systematic-v1-parity-20261023` (draft PR #1, not merged)

## Defect and impact

Previously `auditAccountingIntegrity` could return `healthy` for a store
where every product quantity, stored stock valuation, and inventory GL
projection matched numerically, even though an inventory movement was stored
in USD for an ILS-denominated product. The aggregate checked the numeric
values but never compared the movement currency with the product currency.

A second currency for the same product also had no explicit conflict diagnostic.
This could create misleading conclusions in a multi-currency store.

## Behavior added (read-only)

- `INVENTORY_MOVEMENT_PRODUCT_CURRENCY_MISMATCH`: an explicitly recorded
  movement currency differs from its product's currency.
- `INVENTORY_MOVEMENT_MULTI_CURRENCY`: at least two **explicit**, distinct
  movement currencies exist for the same product.
- `INVENTORY_MOVEMENT_CURRENCY_INVALID`: an explicitly present currency
  field is empty or is not a non-empty string.
- Legacy movements with no currency field use the product's currency only
  for the in-memory valuation comparison. Absence is unknown provenance,
  not evidence for a second currency.

These findings are errors: audit status is `issues_found`, even if stock
and GL numeric amounts happen to match. No conversion, forced reconciliation,
inventory adjustment, backfill, posting or historical balance rewrite occurs.

## Regression fixtures

`functions/accounting_audit_integrity.test.js` now includes five Firebase
emulator cases covering:

1. Wrong currency on a movement with quantity, value and GL fully matching.
2. Two explicitly distinct movement currencies with fully matching totals.
3. Legacy movement with omitted currency (no invented issue).
4. Legacy unknown currency followed by a conflicting explicit currency
   (product mismatch, but no falsely claimed two *known* currencies).
5. Explicitly invalid currency string.

**CI verification pending for the final PR head.** Source/test commits are
not evidence of a successful run. Attach the passing GitHub Actions run and
commit SHA before marking this slice verified.

## Unchanged release gates

- Default `auditAccountingIntegrity` retains the bounded read-only scan
  (10,000 documents per collection, 30,000 overall), and signals incomplete
  rather than pretending a larger scan succeeded.
- Collection reads remain `consistency: non_atomic`; this does not certify
  a point-in-time accounting balance.
- Full-history checkpointing, reporting cutoff/snapshot consistency and
  orphan journal-line discovery are still needed.
- Original opening stock provenance, costing, zero-stock rounding, returns,
  reversal and cross-feature race behavior require accounting acceptance.
- Entire V1 UI/feature parity, isolated V2 Firebase device E2E and native
  setup are separate unfinished gates.

No V1 source or data, production ledgers, Firebase deployment or PR merge
has been modified by this phase.

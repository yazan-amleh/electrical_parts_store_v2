# Phase 4 — unified accounting audit evidence (read-only)

Date: 2026-10-24. Draft PR #1 on
`audit/systematic-v1-parity-20261023`.

## Why

Three checkpointed scanners now exist for one isolated V2 store:

1. `accounting_ledger_runs`: account postings, stored projections and
   per-currency trial-balance evidence.
2. `accounting_journal_runs`: direct journal header vs line totals,
   account-reference issues and potentially unindexed entries.
3. `accounting_orphan_path_runs`: tenant-path line enumeration even
   when orphan journal lines lack the embedded `storeId`.

The independent audits are not a single accounting snapshot. The new API
combines them **without rereading or modifying any source finance record**.

## Callable

`getUnifiedAccountingAuditReport({storeId, ledgerRunId, journalRunId, orphanRunId})`

Only authenticated active owners/admins/accountants may read the report.
The three run IDs must already exist, all belong to the **same tenant
and the caller who started them**, and have the expected checkpoint
schemas. Missing, foreign-owned and corrupt checkpoints fail closed.
The Firestore read transaction reads the three trusted checkpoint
documents together; it does not save or mutate a new report document.

Return shape (high level):

- `verdict`: `observed_aggregates_agree_non_atomic`, `issues_found`,
  `incomplete`, `source_changed` or `empty_scope`.
- `complete`: true only when ledger, journal **and** orphan census
  reached their respective complete status. A budget-exhausted scan
  can never cause a complete verdict.
- `checks.ledger`: compared accounts, mismatches, and separately
  reported ILS/USD/JOD or other currency trial-balance evidence.
- `checks.journal`: inspected entries, direct lines, malformed account
  references and unindexed-risk counts.
- `checks.orphanPaths`: tenant-path read counts, missing-header lines
  including wrong/missing embedded storeId, up to 20 sample paths.
- `checks.crossRun`: debit/credit and line-count comparisons **by
  currency**, from independently accumulated journal and ledger runs.
- `checks.directPathCoverage`: compare the path census count of journal
  lines with an existing parent against the direct journal scan
  `linesChecked` value, **only if all runs completed**.
- `findings[]`: fixed issue codes and counts; includes permanent
  `NO_IMMUTABLE_ACCOUNTING_CUTOFF` to prevent certification.

Both an empty scope and superficially matching aggregates keep
`certified: false`, `accountingCutoffApplied: false`,
`sourceSnapshotGuaranteed: false`, `consistency: non_atomic`.
A complete readout only means the individual passes reached their
configured scope limits; it does NOT assert the original source state
was immutable while they ran.

## Operational usage

Start one ledger run, one journal run and one orphan path run for the
same authenticated store/user, advancing each to a terminal state.
Then call the read-only unified report endpoint with the resulting
run IDs. It may also be called while scanning to obtain a truthful
`incomplete` readout. Every call rechecks membership and tenant/run
ownership. The returned report is not a persistent ledger balance,
nor does it perform any posting, backfill, automatic repair or
transactional freezing of production data.

The existing separate `compareAccountingAuditCoverage` remains
available and unchanged. The new callable reuses the same strict
ledger and journal checkpoint schema/integrity checks and the
orphan scanner's own integrity validator.

## Release gates left unresolved

- Immutable or versioned source postings and a consistent accounting
  cutoff for point-in-time verification.
- Full line-identity reconciliation: aggregate totals or counts can
  agree coincidentally despite different underlying lines.
- Opening balances, all party account balances, inventory/COGS,
  reversals, monthly/yearly closing and full multicurrency policies.
- Cost/rate throttling and retention of historical checkpoint records.
- Actual Firebase V2 configuration testing, UI parity with V1,
  complete functional E2E and final permission/architecture review.

No deployment, merge, V1 data access or modification to production
financial source documents is part of this implementation.

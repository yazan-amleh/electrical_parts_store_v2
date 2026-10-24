# Phase 4 — cross-run ledger/journal indexed coverage check

Date: 2026-10-24. Audit branch `audit/systematic-v1-parity-20261023`.
**Read-only** reconciliation evidence, **not** a financial audit certificate.

## What is implemented

The two existing checkpointed financial scans are now bridged:

- Account/GL scan (`accounting_ledger_runs`) stores the total count of
  *genuine nested journal lines seen by the accountId+storeId index* per
  currency, next to debit/credit turnover and closing debit/credit sides.
  Invoice lines are ignored in these indexed journal-line counts.
- Journal header scan (`accounting_journal_runs`) stores per-currency
  direct nested line counts, debit and credit money sums for every existing
  journal header, including direct lines with missing or wrong embedded
  tenant/account IDs. The existing strict account-reference validation
  and `potentiallyUnindexedLines`/missing-account counters are preserved.
- Both summaries checkpoint together with their corresponding last
  account or journal-entry page using a Firestore transaction. Competing
  advances cannot apply the same page twice.

New authenticated, **non-mutating** callable:

`compareAccountingAuditCoverage({storeId, ledgerRunId, journalRunId})`

Each request requires active owner/admin/accountant membership and
ownership of **both** audit runs by the requesting user in the same store.
Both server-owned checkpoint documents are read in one transaction, but
the scanned source data remains non-atomic across audit steps.

The response has bounded sorted per-currency evidence:
`indexedJournalLines`, `directJournalLines`,
`indexedDebitMinorUnits`, `directDebitMinorUnits`,
`indexedCreditMinorUnits`, `directCreditMinorUnits`, and three separate
agreement booleans. There is no FX conversion or cross-currency summation.

A line under an existing header with a missing `storeId` or a nonexistent
`accountId` can appear in the direct scan but not the account-indexed
scan. Counts and/or amounts then disagree. A tenant-indexed orphan line
under a missing journal header can appear in the account scan but not
the direct header walk; that also leads to differences. Neither source
is modified or repaired.

Verdicts: `incomplete`, `source_changed`, `issues_found`,
`cross_run_difference`, `empty_scope`, or
`aggregate_coverage_agrees_non_atomic`. The last name means only
*these aggregates agreed*; it is **not** exhaustive proof of line
identity, chronological history, journal correctness or balance-sheet
integrity. Individual per-account and per-journal violations always
prevent a clean aggregate verdict.

Responses explicitly declare:
`certified: false`, `consistency: non_atomic`,
`accountingCutoffApplied: false`.

## Compatibility

Journal checkpoint schema was raised from v2 to v3, ledger checkpoint
schema from v2 to v3. Previously created partial audit jobs cannot
safely be resumed as if they had been counting all direct/indexed
lines; callers need a new run after deploying this isolated V2 code.
Cloud Function read/write access is checked server-side, and existing
Firestore rules already prohibit client edits to checkpoints or results.

## Remaining release gates

- A stable, verifiable as-of posting cutoff, and immutable/versioned
  source history for long-running scans. Two different scan passes can
  agree by coincidence while source data changes, so this is **not**
  a point-in-time guarantee.
- Complete orphan discovery with missing/wrong embedded storeId when
  the journal header itself is absent; neither of these bounded scans
  guarantees that coverage.
- Source-level line identity reconciliation (rather than solely count
  and money sums), opening balances, party balances, inventory valuation,
  reversals, accounting periods, and V1 UI parity.
- Retention/rate limiting of checkpoint documents, live Firebase E2E,
  and security/performance release review.

No production Firebase deploy, data migration or modification to V1.

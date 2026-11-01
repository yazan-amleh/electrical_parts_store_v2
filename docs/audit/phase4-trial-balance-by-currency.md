# Phase 4 — resumable, currency-isolated trial balance evidence

Date: 2026-10-24. Scope: audit branch `audit/systematic-v1-parity-20261023`.
This is NOT a certified trial balance or a production release.

## Implementation

Extended `advanceAccountingLedgerReconciliation({storeId,runId})` to
accumulate **per-currency** financial totals when an account reaches its
final indexed-ledger page. The accumulator and the per-account evidence
are written **in the same Firestore transaction** as the checkpoint;
competing advance calls cannot double-count a completed account.

Each currency keeps separate safe-integer minor-unit totals:

- `debitTurnoverMinorUnits`, `creditTurnoverMinorUnits`: gross debit
  and credit postings from the scanned, tenant-indexed journal lines.
- `debitClosingMinorUnits`, `creditClosingMinorUnits`: sum of individual
  account net balances split into positive (debit) and negative (credit)
  sides. These values are *not* the same as gross turnover.
- Counts of posting accounts and accounts with reconciliation issues.
- Boolean turnover and closing-balance comparisons.

Currencies **never net against one another**; ILS, USD and JOD remain
separate, without exchange-rate assumptions or conversion.

The parent checkpoint persists an `trialBalanceByCurrency` map and
posting-account/unclassified counts. Its response adds
`trialBalance: {verdict,complete,certified,accountingCutoffApplied,
consistency,source,postingAccountsCompared,unclassifiedPostingAccounts,
currencies[]}`.

Verdict values:
- `incomplete` while scanning;
- `source_changed` if a paged account or its stored balance changed;
- `issues_found` for account errors, currency classification failures
  or GL/projection mismatches;
- `out_of_balance` when all known account projections match but a
  currency's trial-balance turnover or closing sides do not;
- `no_posting_accounts` for a truly empty chart with no posting accounts;
- `balanced_indexed_evidence_only` when indexed totals agree without
  visible issues, **never** a certified financial sign-off.

## Chart headers

Valid `isHeader: true` chart nodes are **non-posting** and excluded
from trial-balance sums. A header with no lines or balance projection is
not an accounting error. A header with lines or a direct balance
projection creates a specific audit issue. This avoids false positives
from the default chart's ordinary grouping accounts.

Accounts whose currency is not a valid three-letter uppercase code or
whose tenant identity is incorrect are not guessed into any currency.
They increment `unclassifiedPostingAccounts`, create a detected issue,
and prevent the balanced verdict.

Totals are checked for JavaScript safe-integer overflow. A run supports
up to 16 currency groups to bound the checkpoint document size; more
groups cause an explicit failed-precondition rather than silent truncation.

## Limited source drift protection

For an account spanning multiple pages, persist the Firestore revision
timestamps (`updateTime`) of its chart-account document and its stored
balance projection. Before processing subsequent pages, compare both
revisions to the initial readings. Any mismatch stops the run with
`status: source_changed`; it does not silently restart or submit a
matched account result.

This guard does NOT freeze journal lines or earlier completed accounts,
and is **not** a historical cut-off. Real immutable-source/versioned
accounting boundaries, comprehensive orphan/account-index coverage,
opening balances, historical reversals, cross-service reconciliation,
inventory costing and full source-consistency remain future work.

## Compatibility and deployment

The private checkpoint schema is bumped from 1 to 2. A checkpoint
created with the older schema will reject advancement rather than
produce fabricated historical trial-balance totals. Start a new
read-only V2 audit run after the new callable is deployed to the
isolated V2 environment; there is no automatic migration.

Tests cover ILS/USD separation, per-currency balancing, wrong stored
projections despite balanced underlying postings, non-posting chart
headers, unclassified currencies, safe-integer overflow, corrupt
checkpoint rejection and changed chart/balance documents between pages.

**Acceptance:** record a passing CI run for the final commit; do not
deploy, merge or mark financially certified until the remaining release
gates are complete.

No real journal, GL balance, financial posting, source inventory or
V1 data is written or corrected. Only code, tests, and documentation
are committed to the isolated audit branch.

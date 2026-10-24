# Phase 4 — durable journal-header / direct-line reconciliation

Date: 2026-10-24. Target: `audit/systematic-v1-parity-20261023`
(draft PR #1, no deployment, no production data changes).

## Problem and change

The earlier bounded `auditAccountingIntegrity` detects journal-header
debit/credit mismatches but cannot traverse unbounded history in one callable.
The newer per-account `accounting_ledger_runs` aggregates indexed lines by
chart account and compares `account_balances`, but does not itself persist
a verified-by-header total for every journal.

Added independent, server-authorized callables:

- `startAccountingJournalReconciliation({storeId})`
- `advanceAccountingJournalReconciliation({storeId,runId})`

Active owner/admin/accountant membership is verified on each operation.
The creating identity and tenant are pinned to the server-created
`stores/{storeId}/accounting_journal_runs/{runId}` record. Any client
read/write, including child `entry_results`, is disallowed by Firestore rules.

Each advance uses an ordered direct `journal_entries` scan and traverses
one header's **actual** `lines` subcollection in batches of 40 plus one
lookahead. The running debit/credit sums, line count, sampled violations
(maximum 20), header revision and cursor are committed transactionally with
the progress record. Competing advances serialize via transaction retries.
One `entry_results/{entryId}` record is created after the final page of
each header; repeated calls after completion return the same non-certifying
status. Integer overflow fails closed.

This verifies:
- journal header tenant, posted status and nonempty currency;
- each direct line's store/entry/account identity and currency;
- nonnegative safe-integer debit/credit with exactly one positive side;
- independently, the summed debit and credit against each header amount;
- balanced, nonempty posted journal evidence.

If the parent header disappears or its Firestore `updateTime` changes
*between pages*, the run becomes `source_changed`; no per-entry completion
record is written for the changed header. This guard does **not** capture
all possible child-line mutations in a changing history.

The response always declares:
`scope: existing_journal_headers_and_direct_lines`,
`consistency: non_atomic`, `certified: false`,
`accountingCutoffApplied: false`.

## CI acceptance

New emulator scenarios cover balanced data, credit-only header mismatch,
missing embedded storeId and invalid line currency/money, 92-line
checkpoint/resume under competing calls, header update during pagination
(fail closed), membership revocation, malformed checkpoint, and unchanged
source financial records. Firestore security rules tests cover direct access
to run and entry-result documents.

Final GitHub Actions run for the latest commit must pass before this slice
is marked verified.

## Explicit gaps to close before financial sign-off

1. The run only starts from **existing journal headers**. Descendant lines
   beneath deleted headers need the separate orphan finder; wrong/missing
   embedded identifiers and historical migrations also need an
   independent, comprehensive source accounting.
2. Journal-line additions/deletions/revisions between pages can escape
   header-revision detection. Each transaction sees one consistent page
   but the entire run is **non-atomic**. A genuine immutable posting cutoff
   or consistent snapshot is required.
3. No aggregate trial balance, cross-currency policy, complete opening
   balance validation, inventory valuation/COGS sign-off, party-balance
   reconciliation, reversals or end-to-end environment validation is
   represented by this result.
4. There is not yet a UI workflow, TTL/retention or global active-run cap.
   The callable reads only when invoked; each step consumes Firebase reads.

No V1 files or data were changed. No GL documents were corrected or
re-posted. The PR must remain draft until all release gates are met.

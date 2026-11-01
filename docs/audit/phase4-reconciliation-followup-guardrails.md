# Phase 4 — reconciliation follow-up: bounded concurrency and ledger diagnostics

Date: 2026-10-23

## Context and approval boundary

Repo `yazan-amleh/electrical_parts_store_v2`, branch `audit/systematic-v1-parity-20261023`, draft PR #1. This is a **read-only audit logic and emulator regression** change. The live V2 database was not audited, written, deployed or migrated; V1 and V1 customer data were untouched. There has been no merge.

The earlier paginated audit code was CI green, but this source review discovered another budget risk and two diagnostic issues. All three are fixed here.

## Changes

1. **Shared journal-line scan budget, not parallel full-history scans:** The initial `readJournalAuditLines` launched up to 8 `readAuditPages` concurrently, each with the entire remaining document budget. Eight large journal subcollections could therefore collectively read significantly more than the 10,000-line cap before responding incomplete. It now uses bounded round-robin pages, sharing the **remaining global limit**, with at most 8 journal subcollections queried concurrently and one small page per active journal per round. It uses an extra-record probe to distinguish exactly-full scans from incomplete scans. A small in-flight overshoot of at most the number of concurrently active journals is possible for the sentinel check; results still fail closed as `incomplete` if more than the limit is found.
2. **Validate account currency against actual ledger line:** A journal line against an existing account with a different currency is now flagged as `JOURNAL_LINE_ACCOUNT_CURRENCY_MISMATCH` even if it is the only line for that account. This supplements multi-currency and balance-projection comparisons.
3. **Correct debit/credit header diagnostics:** A credit-only header discrepancy used to emit a misleading debit mismatch issue because both were inside a combined condition. Debit mismatch and credit mismatch are now reported independently, with correct expected/actual values.

## Tests added

- Bounded concurrent journal scans with several large journals and a global line cap.
- Exact-boundary journal scans return complete when no extra row exists.
- Firestore emulator detects an account currency different from its journal line.
- Firestore emulator reports a credit-only journal header mismatch without inventing a debit mismatch.

## Exact verified CI evidence

Source commit: `df7d86db12059c053f40473d1f3aed066146b28e`

GitHub Actions run: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/40004406101 (**SUCCESS**)

- Flutter tests: **110 passed**
- Firestore/Storage security rules tests: **20 passed**
- Backend/Node Functions emulator tests: **89 passed**, 0 failed
- Flutter analyzer, Dart formatting and Web release build: **PASS**

Total: **219 passing automated tests** for this source revision.

## Known limits and next execution gate

- The read-only callable remains bounded at 10,000 documents per collection and 30,000 overall. It does **not** support full history for arbitrarily large stores. Build checkpointed/resumable audit runs with job state and retained output rather than raising limits indefinitely.
- The scan remains `consistency: non_atomic`. Multiple collections read at different times are not a certified accounting snapshot. Formal financial sign-off requires snapshot/read-time consistency or a controlled, auditable posting freeze with a fixed reporting cutoff.
- Orphan journal-line documents whose parent journal header no longer exists cannot be found by direct parent traversal alone.
- Finance must validate opening inventory values and the zero-stock cost-rounding policy before accepting an absolute stock/GL reconciliation.
- Exact V1 UI/feature parity, return/refund reversal behavior, real isolated V2 Firebase device E2E and multitenant performance testing are not finished.

No automatic financial corrections or recomputation/backfill of historical balances were performed.

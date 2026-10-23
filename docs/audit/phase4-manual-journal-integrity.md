# Phase 4 — Journal integrity slice (2026-10-23)

> **Scope:** one slice of the complete accounting audit. Code committed to the isolated audit branch; do not interpret as approval of all financial workflows. This audit did not change data, execute production writes or deploy Cloud Functions.

## Traced operational path

Flutter `manual_journal_page.dart` -> `FirestoreAccountingRepository.postJournalEntry` -> authenticated callable `postJournalEntry` in `functions/index.js` -> `parseJournalEntryCommand` -> `db.runTransaction(postJournalEntryInTransaction)` -> journal header + journal lines + `account_balances` projections + `idempotency_keys`. Query/read path: `FirestoreAccountingQueryRepository` for account list, projected balance, trial balance, account ledger.

## Confirmed deficiencies from inspected code

- [J-001] Manual journal parser summed valid **individual** safe minor-unit integers using unchecked JavaScript `+=`; total could become an unsafe floating-point integer.
- [J-002] Cumulative account debit/credit arithmetic was unchecked and could overflow even when the new journal was small.
- [J-003] Existing balance document fields were retrieved using `storedInt(value, 0)`; invalid or corrupt existing values could be silently interpreted as zero and overwritten.
- [J-004] Duplicate idempotency key and matching entry ID returned `already_posted` without checking journal contents, so changed amounts could receive a misleading acknowledgement.
- [J-005] Flutter balance-query readers cast fractional numbers with `toInt`, defaulted missing data to zero and could silently skip account-balance records not matching their store.
- [J-006] `collectionGroup('lines')` for ledger reads did not explicitly guard the parent journal-entries collection, risking inclusion of unrelated `lines` documents when their indexed fields match.

## Changes implemented — no historical data rewritten

- `functions/accounting/journal_integrity.js`: safe-integer additions, persisted balance identity/currency/net verification, deterministic SHA-256 journal fingerprint and full historic-entry replay comparison.
- `functions/index.js`: apply these checks to **manual** `postJournalEntry` only. Store fingerprint with journal and idempotency record; on retry verify same business payload or reject. Historic journals lacking fingerprints are verified against stored header and full line collection before accepting retries. A failed validation aborts the entire Firestore transaction.
- `lib/features/accounting/data/mappers/account_balance_firestore_mapper.dart`: strict expected tenant/account IDs, currency, minor units, and net reconciliation.
- `lib/features/accounting/data/repositories/firestore_accounting_repository.dart`: missing balance document represents zero on a brand-new account; **existing** malformed documents now return an error instead of silently masking corruption.
- `lib/features/accounting/data/repositories/firestore_accounting_query_repository.dart`: strict balance projection parsing and orphan projection detection in trial balance; filter GL lines by the journal parent path and reject malformed ledger line identity/currency/amounts.
- `functions/manual_journal_integrity.test.js`: six server-backed emulator tests covering concurrent/repeated posting, changed replay, legacy replay, unsafe aggregate, accumulated overflow and corrupt existing balance.
- `test/accounting/account_balance_firestore_mapper_test.dart`: six Flutter unit tests for strict balance data.

## Verification policy and caveats

- Tests run in GitHub Actions; report a PASS **only after observing the completed workflow**, not merely after adding test source.
- The full ledger cannot be considered proven with a 500/5000-row limit, `collectionGroup` post-query path filtering and no historical pagination/reconciliation.
- Trial-balance account and balance reads are currently two separate queries, not a single point-in-time accounting snapshot under concurrent postings.
- Unchecked `storedInt` and arithmetic persist in **other** posting handlers (sales, purchases, transfers, expenses, cheques, inventory, etc.). This initial fix deliberately does not claim to repair or test them. Characterization tests and safe migrations are required for every handler.
- No generalized reversal/posting-backout API has been verified by this slice.
- Multi-currency and account schema migrations require separate tests; never infer from the ILS initial chart that other currencies have been verified.
- A Firestore emulator success is not real Firebase Production validation.
- V1 remains the immutable UI/feature reference; no data transfer or production deployment.

## Exit gate

Not complete until: full manual journal CI and emulator evidence, ledger vs balance reconciliation tests, reversed/voided entry strategy, all other financial callable commands characterized and audited, UI parity, and isolated real V2 Firebase end-to-end transactions.

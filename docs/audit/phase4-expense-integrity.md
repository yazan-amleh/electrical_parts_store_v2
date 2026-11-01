# Phase 4 — expense posting and supplier-balance integrity

Date: 2026-10-23

## Scope, current status

Source: `v2/port-v1-complete`; working branch: `audit/systematic-v1-parity-20261023`. **This is one financial workflow, not a full accounting-system acceptance.** No V1 modifications, customer-data migrations or Production deployment.

## Data-flow trace

`postExpense` callable -> `parseExpenseCommand` -> `postExpenseInTransaction` -> membership check -> expense ID/idempotency reservation -> verify expense account, settlement/payables and optional input-tax account -> expense/journal/lines -> supplier party ledger/balance (credit expenses) -> account balances -> idempotency records, all in one Firestore transaction.

## Confirmed defects repaired in source

- **E-001 unsafe amount+tax:** individually safe minor-unit integers could sum to a number beyond JavaScript's safe range. Now rejected before any write.
- **E-002 unsafe replay:** an existing expense idempotency key with the same expense ID but changed amount/metadata previously returned `already_posted`. New entries store a deterministic fingerprint. Legacy entries without one are checked against the expense, complete journal lines and journal header/marker before acknowledging a retry.
- **E-003 corrupted GL projections:** invalid stored account balance fields previously defaulted to zero, allowing a write that masked discrepancies. Existing projections must now reconcile exactly and belong to the same tenant/account/currency.
- **E-004 corrupted supplier balances:** credit expenses previously defaulted invalid supplier balance fields to zero and used unguarded arithmetic. Added strict party balance identity, currency, debit/credit/net consistency and safe integer checks.
- **E-005 phantom supplier:** credit expense posting did not verify a same-store active supplier before creating payable ledger/balance documents. It now rejects nonexistent, inactive or cross-store suppliers.
- **E-006 journal lines:** newly posted expense journal line documents now include currency for strict GL query validation. Historical V2 expense lines may omit redundant currency, and the legacy retry verifier accepts that only if the journal header currency is verified.

## Files

- `functions/accounting/expense_integrity.js` — fingerprint and complete legacy replay comparisons.
- `functions/accounting/journal_integrity.js` — strict party balance projection reader.
- `functions/index.js` — safe expense validation and atomic journal / supplier / GL projections.
- `functions/expense_integrity.test.js` — 8 emulator tests covering cash/credit/tax, replay, historical markers, tenant-scoped suppliers, supplier corruption and safe integer overflow.
- `functions/package.json` — include new regression suite.

## Release / acceptance gaps

- The GitHub CI pass for this exact source commit must be recorded **before** reporting these changes tested. A prior green run does not apply to later commits.
- Other flows (party payments, cheques, sales, purchases, inventory, returns) still have their own financial mutation paths, and must receive equivalent characterization and corruption/replay tests.
- Real V2 Firebase test-environment E2E, full historical GL reconciliation, reversals, multi-currency and V1 UI parity remain open.
- No database backfill, historical mutation or silent balance correction is included.

## CI

**PASS**, GitHub Actions run https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39931227395, source commit `f9b52d38df064b9d38ebe91c5a1ca66bd4f4de07`: 108 Flutter, 20 Firestore/Storage rules, 27 Backend emulator tests, 0 failures; Dart formatting, Flutter analyzer, and Web Release build also passed. Includes eight new expense tests. This is emulator/source validation only, not a deployed Firebase E2E or all-feature financial certification.

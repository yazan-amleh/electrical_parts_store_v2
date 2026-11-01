# Phase 4 — party payments and cheque settlement integrity

Date: 2026-10-23

## Scope

This is a security/accounting hardening slice of V2 on `audit/systematic-v1-parity-20261023`. The original V1 repo/customer data and V2 Production were untouched. Draft PR #1 is not merged or deployed.

### Party payments

`postPartyPayment` creates `party_payments`, `party_ledger_entries`, the customer/supplier `party_balances` projection, balanced journal/lines, GL `account_balances`, and idempotency markers in one Firestore transaction. It performs active membership and party/account authorization checks.

Confirmed source defects corrected:

- P-001: Matching key + payment ID wrongly acknowledged a *changed* request. New requests use a SHA-256 fingerprint over payment details, cheque metadata, and posting account IDs.
- P-002: Pre-fingerprint V2 retries now validate the persisted payment, journal header and entire set of journal lines. Old cheques that were subsequently cleared/bounced are valid unchanged retries, not silently treated as new transactions.
- P-003: Invalid party or GL projection numbers and identity/currency mismatches were silently defaulted to zero before writing. Now they fail closed without partial writes.
- P-004: Cumulative debit/credit/net additions use safe-integer arithmetic.
- P-005: New party payment journal lines include currency, enabling strict GL ledger parsing while legacy verification tolerates missing redundant currency on old lines.

### Cheque settlement

`settleCheque` clears or bounces a cheque and posts a balanced journal, the cheque status and GL projections atomically. A bounce also posts the party ledger and restores party receivable/payable balance.

Corrected source defects:

- C-001: An existing settlement marker with matching cheque ID and action was enough to acknowledge a *different* date or bank/account selection. New markers include the exact normalized command fingerprint; old markers are validated against the completed cheque, journal header, idempotency marker, and both journal lines.
- C-002: Bounce party balances and GL accounts now reject corrupt existing debit/credit/net data instead of resetting it to zero.
- C-003: Updated party/GL balances use safe-integer additions to block overflow.

### Files

- `functions/accounting/party_payment_integrity.js`
- `functions/accounting/cheque_settlement_integrity.js`
- `functions/index.js`
- `functions/party_payment_integrity.test.js`
- `functions/cheque_settlement_integrity.test.js`
- `functions/package.json`

### Exact verified CI evidence

Source commit: `12b064b469d2c501f5e0761e32afb6ba045f39b3`.

GitHub Actions: https://github.com/yazan-amleh/electrical_parts_store_v2/actions/runs/39937085046 — **SUCCESS**:

- Flutter tests: 108 pass
- Firestore/Storage security rule tests: 20 pass
- Functions/Node emulator tests: 42 pass, 0 fail (new party payments and cheque settlement coverage)
- Flutter analyzer / Dart format / Web Release compilation: pass

Emulator tests include concurrency, duplicate requests, changed payloads, historical replay, customer/supplier cash and cheque postings, tax-independent flows, role and tenant denial, malformed party/account projection, balance overflow, cheque clearance and bounce. These are local emulator verification, **not a deployed test environment or financial certification**.

### Unfinished gates

- Sales, purchases, refunds, cash/bank/counterparty integrations, returns, other cheque variants, inventory valuation, reversals, auditing/reconciliation and all UI parity still require independent treatment.
- GL and party balance projections are derived data: verify them against the full immutable journal, not by mass-changing figures. A read-only reconciliation report is required.
- Historic marker matching verifies original entries; it does not independently prove all historical ledger and party projections are correct.
- Account permissions, races across **different** financial operations and recovery from network interruption still need end-to-end tests on an independent V2 Firebase test environment.
- Android/iOS scaffolding/registrations and full V1 UI parity remain incomplete.

**No production deployment, no merge, no V1 writes, and no V1→V2 data sync.**

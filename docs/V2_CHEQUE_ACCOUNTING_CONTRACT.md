# V2 cheque accounting contract

This contract defines the only supported accounting transitions for customer and supplier cheques in V2.

## Source of truth

- Every cheque operation creates a balanced journal entry through the atomic server command.
- account_balances is a materialized projection maintained in the same transaction as the journal.
- party_ledger_entries and party_balances are projections of the same transaction; they are never used as a replacement for the journal.
- The cheque document stores lifecycle metadata and links to the initial and settlement journal entries.

## Accounts

| Account | Role | Normal side |
| --- | --- | --- |
| 1130 | Incoming cheques under collection | Debit |
| 2210 | Issued cheques payable | Credit |
| 1140 | Customer receivables | Debit |
| 2110 | Supplier payables | Credit |
| 1121 | Main bank | Debit |

## Customer cheque lifecycle

| Event | Debit | Credit |
| --- | --- | --- |
| Receive cheque from customer | 1130 | 1140 |
| Clear cheque in bank | 1121 | 1130 |
| Bounce cheque | 1140 | 1130 |

A customer cheque increases the bank only when it is cleared. A bounce restores the customer's receivable and writes a debit party-ledger entry.

## Supplier cheque lifecycle

| Event | Debit | Credit |
| --- | --- | --- |
| Issue cheque to supplier | 2110 | 2210 |
| Pay issued cheque through bank | 2210 | 1121 |
| Bounce cheque | 2210 | 2110 |

An issued supplier cheque reduces the supplier payable immediately but does not reduce the bank until it is paid. A bounce restores the supplier payable and writes a credit party-ledger entry.

## Safety rules

- A cheque can move only from pending to exactly one terminal state: cleared or bounced.
- Settlement is idempotent and rejects a second terminal transition.
- The settlement transaction reads all documents before writing any document.
- Account ids are validated for store, currency, type, control type, and distinctness.
- Client screens call the repository port; Firebase paths and callable names stay inside infrastructure.

# V2 feature parity matrix

This matrix keeps the V1 surface visible while V2 is rebuilt on a new data set. It is a delivery checklist, not a claim that every item is production-ready.

## Implemented and wired

| V1 area | V2 status | V2 entry point |
| --- | --- | --- |
| Authentication and store membership | Complete | features/auth |
| Dashboard and low-stock summary | Complete | features/dashboard |
| Products, services, units, prices and categories | Complete | features/inventory, features/categories |
| Inventory movements and atomic stock effects | Complete | features/inventory |
| Sales and point of sale | Complete | features/sales |
| Offers and offer orders | Complete | features/offers |
| Purchases and purchase orders | Complete | features/purchases, features/purchase_orders |
| Customers and suppliers | Complete | features/parties |
| Customer/supplier payments and party statements | Complete | features/payments, features/parties |
| Cheques and settlement lifecycle | Complete | features/cheques |
| Chart of accounts | Complete | features/accounting |
| Manual journal, ledger and account statements | Complete | features/accounting |
| Trial balance, income statement and balance sheet | Complete | features/accounting |
| Accounting integrity audit | Complete | features/accounting_audit |
| Expenses and input tax | Complete | features/expenses |
| Cash, banks and internal transfers | Complete | features/transfers |
| Repairs intake, parts, advances, invoice and delivery | Complete | features/repairs |
| Operational reports by period | Complete | features/reports |

## Still required before V2 delivery

| Area | Status | Scope |
| --- | --- | --- |
| Report export and printing | Partial | Operational reports, sales analytics, repair requests and payment receipts, and category inventory support PDF/print/share; V1-specific formats still need final visual review |
| Advanced product/category/customer sales analytics | Implemented | Sales analytics page with product, category, customer and payment-method aggregation, paginated reads and a visible safety-cap warning |
| Chat and notifications | Implemented | Secure participant-scoped rooms, direct/group text, unread counters, attachment upload rules, device token registration and participant-only push notification function are wired; production deployment and device QA remain release gates |
| Salon and booking workflows | Planned | V1 includes bookings, calendar, photography options, customers, workers, work sessions, discounts and booking expenses; V2 vertical slice is next and will use atomic inventory/accounting commands |
| Store settings and user administration UI | Complete | Store profile, members, roles and preferences (owner transfer/invitations remain separate) |
| Full responsive UI parity review | Planned | Compare every V1 workflow on phone and desktop |
| End-to-end emulator scenarios | Planned | Sales, purchases, payments, cheques, repairs and year-end flows |

## Accounting source-of-truth policy

- Posted journal entries and their lines are the accounting facts.
- account_balances is a transactional projection maintained in the same transaction as the journal.
- Party statements use party_ledger_entries; party_balances is a projection.
- Inventory quantities and value use inventory movements and the product projection maintained atomically.
- Cash and bank screens read control accounts and account_balances; they do not create a second cash ledger.
- Reports read posted V2 documents and must not read legacy report collections.

Every item marked complete still requires its matching emulator scenario and UI review before release.

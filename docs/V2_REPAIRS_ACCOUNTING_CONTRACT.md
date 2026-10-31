# V2 Repair Accounting Contract

## Scope

The repair workflow reuses the existing "parties" customer master and "products" inventory master. It does not create a second customer or product system.

All monetary values are sent as integer minor units. Quantities are sent as integer milli-units.

## Lifecycle

1. Receive the device with status "received".
2. Move it through "diagnosing", "inProgress", and "ready".
3. Add stock parts before invoicing. A product may appear only once in a repair.
4. Post an optional cash, bank, or card advance before invoicing.
5. Deliver the repair. Delivery posts the invoice and the stock issue atomically.
6. Post settlement payments after the invoice. A cheque is a settlement payment, never an advance.
7. A delivered or cancelled repair cannot be edited.

## Invoice posting

For a repair with invoice total T, parts cost C, and customer advance A:

- Debit customer receivable 1140 by T.
- Credit repair revenue 4110 by T.
- If C is greater than zero, debit cost of sales 5100 and credit inventory 1150 by C.
- If A is greater than zero, debit customer advances 2130 and credit customer receivable 1140 by A.
- The customer party ledger records the invoice debit and advance application credit.
- The account balance projections are updated in the same transaction.
- Each stock product, movement, and idempotency record is updated in the same transaction.

The invoice is rejected if the product is inactive, a service, in another store, has insufficient quantity, or would create a negative inventory value. Repair parts are issued at their exact share of the current inventory carrying value; a full depletion removes the remaining inventory value exactly rather than relying on a rounded displayed unit cost.

## Payments

A pre-invoice advance posts:

- Debit the selected cash/bank/card account.
- Credit customer advances 2130.
- Record the payment as an advance for the repair.

A post-invoice settlement uses the existing party-payment engine so the customer ledger and cheque lifecycle remain consistent. The payment is linked back to the repair by repairId.

## Idempotency and authorization

All repair writes are callable functions. They validate store membership and use command/idempotency records. Repair delivery and advance markers persist immutable request fingerprints, so retries cannot change dates, amounts, or posting accounts under the same key. Firestore client rules allow reads for store members but deny direct repair writes; the command outbox only accepts the named repair operations.

## Cheque bounce linkage

A post-invoice repair cheque is linked to its repair through the settlement payment. If the cheque bounces, the same guarded cheque-settlement transaction restores the customer receivable and reduces the repair's paid projection by the bounced amount. A retry of the same bounce remains idempotent and cannot reduce the repair twice.

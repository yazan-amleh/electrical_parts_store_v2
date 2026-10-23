'use strict';

const crypto = require('node:crypto');

function fingerprintPurchaseOrderReceipt(command) {
  return crypto.createHash('sha256').update(JSON.stringify({
    storeId: command.storeId,
    orderId: command.orderId,
    receiptId: command.receiptId,
    idempotencyKey: command.idempotencyKey,
    postedAt: command.postedAt.toISOString(),
    paymentMethod: command.paymentMethod,
    currency: command.currency,
    taxMinorUnits: command.taxMinorUnits,
    accounts: command.accounts,
  })).digest('hex');
}

// The original V2 receipts did not store the posting account IDs. On those
// records verify the completed order and original purchase/journal metadata,
// then fail closed when the requested account identities cannot be checked.
function matchesLegacyPurchaseOrderReceipt(marker, order, purchase, journal, command) {
  const completed = order.completedAt?.toDate?.();
  const posted = purchase.postedAt?.toDate?.();
  const postedJournal = journal.postedAt?.toDate?.();
  const paymentId = command.paymentMethod === 'credit'
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  return marker.storeId === command.storeId &&
    marker.orderId === command.orderId &&
    marker.receiptId === command.receiptId &&
    marker.purchaseId === command.receiptId &&
    marker.journalEntryId === command.receiptId + '-journal' &&
    marker.idempotencyKey === command.idempotencyKey &&
    order.storeId === command.storeId &&
    order.status === 'completed' &&
    order.receiptId === command.receiptId &&
    order.journalEntryId === marker.journalEntryId &&
    purchase.storeId === command.storeId &&
    purchase.status === 'posted' &&
    purchase.idempotencyKey === command.idempotencyKey &&
    purchase.journalEntryId === marker.journalEntryId &&
    purchase.currency === command.currency &&
    purchase.paymentMethod === command.paymentMethod &&
    purchase.supplierId === order.supplierId &&
    purchase.taxMinorUnits === command.taxMinorUnits &&
    journal.storeId === command.storeId &&
    journal.status === 'posted' &&
    journal.sourceType === 'purchase' &&
    journal.currency === command.currency &&
    journal.totalDebitMinorUnits === purchase.totalMinorUnits &&
    journal.totalCreditMinorUnits === purchase.totalMinorUnits &&
    paymentId != null &&
    completed instanceof Date &&
    posted instanceof Date &&
    postedJournal instanceof Date &&
    completed.getTime() === command.postedAt.getTime() &&
    posted.getTime() === command.postedAt.getTime() &&
    postedJournal.getTime() === command.postedAt.getTime();
}

module.exports = {
  fingerprintPurchaseOrderReceipt,
  matchesLegacyPurchaseOrderReceipt,
};

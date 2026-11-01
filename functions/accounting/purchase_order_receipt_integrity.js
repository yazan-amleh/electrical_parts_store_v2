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
    lines: command.lines,
    accounts: command.accounts,
  })).digest('hex');
}

function legacyFingerprintPurchaseOrderReceipt(command) {
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

// The original V2 receipts did not store the posting account IDs. Verify the
// historical purchase and journal, including account identities in the lines.
function matchesLegacyPurchaseOrderReceipt(marker, order, purchase, journal, command) {
  if (command.lines != null) return false;
  const completed = order.completedAt?.toDate?.();
  const posted = purchase.postedAt?.toDate?.();
  const postedJournal = journal.postedAt?.toDate?.();
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
    completed instanceof Date &&
    posted instanceof Date &&
    postedJournal instanceof Date &&
    completed.getTime() === command.postedAt.getTime() &&
    posted.getTime() === command.postedAt.getTime() &&
    postedJournal.getTime() === command.postedAt.getTime();
}

function matchesLegacyPurchaseOrderJournalLines(lines, purchase, command) {
  const id = command.receiptId;
  const paymentId = command.paymentMethod === 'credit'
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  const tax = command.taxMinorUnits;
  const expected = [
    [id + '-inventory', command.accounts.inventoryAccountId,
      purchase.subtotalMinorUnits, 0, 1],
    ...(tax > 0 ? [[id + '-input-tax', command.accounts.inputTaxAccountId,
      tax, 0, 2]] : []),
    [id + '-settlement', paymentId, 0, purchase.totalMinorUnits,
      tax > 0 ? 3 : 2],
  ];
  return lines.length === expected.length &&
    expected.every(([lineId, accountId, debit, credit, lineNumber], i) => {
      const doc = lines[i];
      if (!doc.exists || !accountId) return false;
      const line = doc.data();
      const date = line.postedAt?.toDate?.();
      return doc.id === lineId &&
        line.storeId === command.storeId &&
        line.entryId === id + '-journal' &&
        line.accountId === accountId &&
        (line.currency == null || line.currency === command.currency) &&
        line.lineNumber === lineNumber &&
        line.debitMinorUnits === debit &&
        line.creditMinorUnits === credit &&
        date instanceof Date &&
        date.getTime() === command.postedAt.getTime();
    });
}

module.exports = {
  fingerprintPurchaseOrderReceipt,
  legacyFingerprintPurchaseOrderReceipt,
  matchesLegacyPurchaseOrderReceipt,
  matchesLegacyPurchaseOrderJournalLines,
};

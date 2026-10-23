'use strict';

const crypto = require('node:crypto');

function fingerprintSale(command) {
  const s = command.sale;
  return crypto.createHash('sha256').update(JSON.stringify({
    storeId: command.storeId,
    id: s.id,
    key: s.idempotencyKey,
    postedAt: s.postedAt.toISOString(),
    paymentMethod: s.paymentMethod,
    customerId: s.customerId,
    description: s.description,
    currency: s.currency,
    taxMinorUnits: s.taxMinorUnits,
    accounts: command.accounts,
    lines: s.lines,
  })).digest('hex');
}

function matchesLegacySaleInvoice(row, command, journalId) {
  const s = command.sale;
  const date = row.postedAt?.toDate?.();
  return row.storeId === command.storeId &&
    row.idempotencyKey === s.idempotencyKey &&
    row.journalEntryId === journalId &&
    row.paymentMethod === s.paymentMethod &&
    (row.customerId ?? null) === (s.customerId ?? null) &&
    (row.description ?? null) === (s.description ?? null) &&
    row.currency === s.currency &&
    row.taxMinorUnits === s.taxMinorUnits &&
    row.status === 'posted' &&
    date instanceof Date && date.getTime() === s.postedAt.getTime();
}

function matchesLegacySaleLines(snapshot, command) {
  const requested = command.sale.lines;
  return snapshot.size === requested.length && requested.every((line) => {
    const doc = snapshot.docs.find((d) => d.id === line.id);
    if (!doc) return false;
    const data = doc.data();
    return data.storeId === command.storeId &&
      data.productId === line.productId &&
      data.description === line.description &&
      data.quantityMilliUnits === line.quantityMilliUnits &&
      data.unitFactorToBaseMilliUnits === line.unitFactorToBaseMilliUnits &&
      data.unitPriceMinorUnits === line.unitPriceMinorUnits &&
      data.unitCostMinorUnits === line.unitCostMinorUnits &&
      data.discountMinorUnits === line.discountMinorUnits &&
      data.isService === line.isService &&
      (data.unitId ?? null) === (line.unitId ?? null) &&
      (data.unitName ?? null) === (line.unitName ?? null) &&
      Number.isSafeInteger(data.totalMinorUnits) &&
      Number.isSafeInteger(data.costTotalMinorUnits);
  });
}

function matchesLegacySaleJournal(header, snapshot, command, journalId, saleRow) {
  const s = command.sale;
  const date = header.postedAt?.toDate?.();
  const pay = s.paymentMethod === 'credit'
    ? command.accounts.customerReceivableAccountId
    : command.accounts.settlementAccountId;
  if (header.storeId !== command.storeId ||
      header.status !== 'posted' ||
      header.sourceType !== 'sale' ||
      header.idempotencyKey !== s.idempotencyKey + ':journal' ||
      header.currency !== s.currency ||
      header.totalDebitMinorUnits !== saleRow.totalMinorUnits + saleRow.costTotalMinorUnits ||
      header.totalCreditMinorUnits !== saleRow.totalMinorUnits + saleRow.costTotalMinorUnits ||
      !(date instanceof Date) || date.getTime() !== s.postedAt.getTime()) {
    return false;
  }
  const expected = [
    [s.id + '-settlement', pay, 1, saleRow.totalMinorUnits, 0],
    [s.id + '-sales', command.accounts.salesAccountId, 2, 0, saleRow.subtotalMinorUnits],
  ];
  if (s.taxMinorUnits > 0) {
    expected.push([s.id + '-tax', command.accounts.taxAccountId,
      expected.length + 1, 0, s.taxMinorUnits]);
  }
  if (saleRow.costTotalMinorUnits > 0) {
    expected.push([s.id + '-cost', command.accounts.costOfSalesAccountId,
      expected.length + 1, saleRow.costTotalMinorUnits, 0]);
    // The original V2 generated both COGS lines with the same lineNumber.
    expected.push([s.id + '-inventory', command.accounts.inventoryAccountId,
      expected.length, 0, saleRow.costTotalMinorUnits]);
  }
  return snapshot.size === expected.length && expected.every(([id, accountId, lineNumber, debit, credit]) => {
    const doc = snapshot.docs.find((d) => d.id === id);
    if (!doc) return false;
    const row = doc.data();
    const posted = row.postedAt?.toDate?.();
    return row.storeId === command.storeId &&
      row.entryId === journalId &&
      row.accountId === accountId &&
      (row.currency == null || row.currency === s.currency) &&
      row.lineNumber === lineNumber &&
      row.debitMinorUnits === debit &&
      row.creditMinorUnits === credit &&
      posted instanceof Date && posted.getTime() === s.postedAt.getTime();
  });
}

module.exports = {
  fingerprintSale,
  matchesLegacySaleInvoice,
  matchesLegacySaleLines,
  matchesLegacySaleJournal,
};

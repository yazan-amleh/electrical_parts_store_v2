'use strict';

const crypto = require('node:crypto');

// Requests are normalized by the callable parser before fingerprints are
// computed. Include posting account identities, quantities, discounts and units.
function fingerprintPurchase(command) {
  const purchase = command.purchase;
  const canonical = {
    storeId: command.storeId,
    id: purchase.id,
    idempotencyKey: purchase.idempotencyKey,
    postedAt: purchase.postedAt.toISOString(),
    paymentMethod: purchase.paymentMethod,
    supplierId: purchase.supplierId,
    description: purchase.description,
    currency: purchase.currency,
    taxMinorUnits: purchase.taxMinorUnits,
    accounts: command.accounts,
    lines: purchase.lines,
  };
  return crypto.createHash('sha256')
    .update(JSON.stringify(canonical)).digest('hex');
}

function matchesLegacyPurchaseHeader(row, command, journalId) {
  const p = command.purchase;
  const time = row.postedAt?.toDate?.();
  return row.storeId === command.storeId &&
    row.idempotencyKey === p.idempotencyKey &&
    row.journalEntryId === journalId &&
    row.paymentMethod === p.paymentMethod &&
    (row.supplierId ?? null) === (p.supplierId ?? null) &&
    (row.description ?? null) === (p.description ?? null) &&
    row.currency === p.currency &&
    row.taxMinorUnits === p.taxMinorUnits &&
    row.status === 'posted' &&
    time instanceof Date && time.getTime() === p.postedAt.getTime();
}

function matchesLegacyPurchaseLines(snapshot, command) {
  const requested = command.purchase.lines;
  if (snapshot.size !== requested.length) return false;
  return requested.every((line) => {
    const doc = snapshot.docs.find((d) => d.id === line.id);
    if (!doc) return false;
    const data = doc.data();
    return data.storeId === command.storeId &&
      data.productId === line.productId &&
      data.description === line.description &&
      data.quantityMilliUnits === line.quantityMilliUnits &&
      data.unitFactorToBaseMilliUnits === line.unitFactorToBaseMilliUnits &&
      data.unitCostMinorUnits === line.unitCostMinorUnits &&
      data.discountMinorUnits === line.discountMinorUnits &&
      (data.unitId ?? null) === (line.unitId ?? null) &&
      (data.unitName ?? null) === (line.unitName ?? null) &&
      Number.isSafeInteger(data.totalMinorUnits) &&
      data.totalMinorUnits >= 0;
  });
}

function matchesLegacyPurchaseJournal(header, lines, command, journalId, purchase) {
  const p = command.purchase;
  const posted = header.postedAt?.toDate?.();
  if (header.storeId !== command.storeId ||
      header.idempotencyKey !== p.idempotencyKey + ':journal' ||
      header.sourceType !== 'purchase' ||
      header.status !== 'posted' ||
      header.currency !== p.currency ||
      header.totalDebitMinorUnits !== purchase.totalMinorUnits ||
      header.totalCreditMinorUnits !== purchase.totalMinorUnits ||
      !(posted instanceof Date) || posted.getTime() !== p.postedAt.getTime()) {
    return false;
  }
  const tax = p.taxMinorUnits;
  const paymentAccountId = p.paymentMethod === 'credit'
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  const expected = [
    [p.id + '-inventory', command.accounts.inventoryAccountId, purchase.subtotalMinorUnits, 0, 1],
    ...(tax > 0 ? [[p.id + '-input-tax', command.accounts.inputTaxAccountId, tax, 0, 2]] : []),
    [p.id + '-settlement', paymentAccountId, 0, purchase.totalMinorUnits, tax > 0 ? 3 : 2],
  ];
  if (lines.size !== expected.length) return false;
  return expected.every(([id, accountId, debit, credit, lineNumber]) => {
    const doc = lines.docs.find((d) => d.id === id);
    if (!doc) return false;
    const row = doc.data();
    const time = row.postedAt?.toDate?.();
    return row.storeId === command.storeId &&
      row.entryId === journalId &&
      row.accountId === accountId &&
      (row.currency == null || row.currency === p.currency) &&
      row.lineNumber === lineNumber &&
      row.debitMinorUnits === debit &&
      row.creditMinorUnits === credit &&
      time instanceof Date && time.getTime() === p.postedAt.getTime();
  });
}

module.exports = {
  fingerprintPurchase,
  matchesLegacyPurchaseHeader,
  matchesLegacyPurchaseLines,
  matchesLegacyPurchaseJournal,
};

'use strict';

const crypto = require('node:crypto');

function fingerprintPartyPayment(command) {
  const p = command.payment;
  const canonical = {
    id: p.id,
    idempotencyKey: p.idempotencyKey,
    postedAt: p.postedAt.toISOString(),
    partyType: p.partyType,
    partyId: p.partyId,
    paymentMethod: p.paymentMethod,
    amountMinorUnits: p.amountMinorUnits,
    currency: p.currency,
    description: p.description,
    chequeNumber: p.chequeNumber,
    bankName: p.bankName,
    dueDate: p.dueDate?.toISOString() ?? null,
    settlementAccountId: command.accounts.settlementAccountId,
    partyAccountId: command.accounts.partyAccountId,
  };
  return crypto.createHash('sha256')
    .update(JSON.stringify(canonical)).digest('hex');
}

function sameLegacyPartyPayment(row, command, journalEntryId) {
  const p = command.payment;
  const posted = row.postedAt?.toDate?.();
  const due = row.dueDate?.toDate?.() ?? null;
  return row.storeId === command.storeId &&
    row.idempotencyKey === p.idempotencyKey &&
    row.journalEntryId === journalEntryId &&
    (p.paymentMethod === 'cheque'
      ? ['pending', 'cleared', 'bounced'].includes(row.status)
      : row.status === 'posted') &&
    row.partyType === p.partyType &&
    row.partyId === p.partyId &&
    row.paymentMethod === p.paymentMethod &&
    row.amountMinorUnits === p.amountMinorUnits &&
    row.currency === p.currency &&
    (row.description ?? null) === (p.description ?? null) &&
    (row.chequeNumber ?? null) === (p.chequeNumber ?? null) &&
    (row.bankName ?? null) === (p.bankName ?? null) &&
    (due?.getTime() ?? null) === (p.dueDate?.getTime() ?? null) &&
    posted instanceof Date &&
    posted.getTime() === p.postedAt.getTime();
}

function sameLegacyPartyPaymentLines(snapshot, command, journalEntryId) {
  const p = command.payment;
  const customer = p.partyType === 'customer';
  const expected = [
    {
      id: p.id + '-settlement',
      accountId: command.accounts.settlementAccountId,
      lineNumber: 1,
      debit: customer ? p.amountMinorUnits : 0,
      credit: customer ? 0 : p.amountMinorUnits,
    },
    {
      id: p.id + '-party',
      accountId: command.accounts.partyAccountId,
      lineNumber: 2,
      debit: customer ? 0 : p.amountMinorUnits,
      credit: customer ? p.amountMinorUnits : 0,
    },
  ];
  return snapshot.size === expected.length && expected.every((line) => {
    const doc = snapshot.docs.find((item) => item.id === line.id);
    if (!doc) return false;
    const data = doc.data();
    const posted = data.postedAt?.toDate?.();
    return data.entryId === journalEntryId &&
      data.storeId === command.storeId &&
      data.accountId === line.accountId &&
      (data.currency == null || data.currency === p.currency) &&
      data.lineNumber === line.lineNumber &&
      data.debitMinorUnits === line.debit &&
      data.creditMinorUnits === line.credit &&
      posted instanceof Date &&
      posted.getTime() === p.postedAt.getTime();
  });
}

module.exports = {
  fingerprintPartyPayment,
  sameLegacyPartyPayment,
  sameLegacyPartyPaymentLines,
};

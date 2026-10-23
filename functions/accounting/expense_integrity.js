'use strict';

const crypto = require('node:crypto');

function expenseFingerprint(command) {
  const expense = command.expense;
  const account = command.accounts;
  const canonical = {
    id: expense.id,
    idempotencyKey: expense.idempotencyKey,
    postedAt: expense.postedAt.toISOString(),
    paymentMethod: expense.paymentMethod,
    expenseAccountId: expense.expenseAccountId,
    supplierId: expense.supplierId,
    description: expense.description,
    currency: expense.currency,
    amountMinorUnits: expense.amountMinorUnits,
    taxMinorUnits: expense.taxMinorUnits,
    settlementAccountId: account.settlementAccountId,
    supplierPayableAccountId: account.supplierPayableAccountId,
    inputTaxAccountId: account.inputTaxAccountId,
  };
  return crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
}

function sameLegacyExpense(row, command, journalEntryId, totalMinorUnits) {
  const e = command.expense;
  const postedAt = row.postedAt?.toDate?.();
  return row.status === 'posted' &&
    row.storeId === command.storeId &&
    row.idempotencyKey === e.idempotencyKey &&
    row.journalEntryId === journalEntryId &&
    row.paymentMethod === e.paymentMethod &&
    row.expenseAccountId === e.expenseAccountId &&
    (row.supplierId ?? null) === (e.supplierId ?? null) &&
    (row.description ?? null) === (e.description ?? null) &&
    row.currency === e.currency &&
    row.amountMinorUnits === e.amountMinorUnits &&
    row.taxMinorUnits === e.taxMinorUnits &&
    row.totalMinorUnits === totalMinorUnits &&
    postedAt instanceof Date && postedAt.getTime() === e.postedAt.getTime();
}

function sameLegacyExpenseLines(snapshot, command, journalEntryId, totalMinorUnits) {
  const e = command.expense;
  const paymentAccountId = e.paymentMethod === 'credit'
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  const expected = [
    { id: e.id + '-expense', accountId: e.expenseAccountId, debit: e.amountMinorUnits, credit: 0, lineNumber: 1 },
    ...(e.taxMinorUnits > 0 ? [
      { id: e.id + '-input-tax', accountId: command.accounts.inputTaxAccountId, debit: e.taxMinorUnits, credit: 0, lineNumber: 2 },
    ] : []),
    { id: e.id + '-payment', accountId: paymentAccountId, debit: 0, credit: totalMinorUnits, lineNumber: e.taxMinorUnits > 0 ? 3 : 2 },
  ];
  if (snapshot.size !== expected.length) return false;
  return expected.every((line) => {
    const doc = snapshot.docs.find((d) => d.id === line.id);
    if (!doc) return false;
    const data = doc.data();
    const date = data.postedAt?.toDate?.();
    return data.entryId === journalEntryId &&
      data.storeId === command.storeId &&
      data.accountId === line.accountId &&
      data.currency === e.currency &&
      data.lineNumber === line.lineNumber &&
      data.debitMinorUnits === line.debit &&
      data.creditMinorUnits === line.credit &&
      date instanceof Date && date.getTime() === e.postedAt.getTime();
  });
}

module.exports = {
  expenseFingerprint,
  sameLegacyExpense,
  sameLegacyExpenseLines,
};

'use strict';

const crypto = require('node:crypto');

function fingerprintChequeSettlement(command) {
  const canonical = {
    storeId: command.storeId,
    chequeId: command.chequeId,
    action: command.action,
    idempotencyKey: command.idempotencyKey,
    postedAt: command.postedAt.toISOString(),
    accounts: command.accounts,
  };
  return crypto.createHash('sha256')
    .update(JSON.stringify(canonical)).digest('hex');
}

function sameLegacyChequeSettlement(header, cheque, command, journalEntryId) {
  const date = header.postedAt?.toDate?.();
  const amount = cheque.amountMinorUnits;
  return header.storeId === command.storeId &&
    header.idempotencyKey === command.idempotencyKey + ':journal' &&
    header.sourceType === (command.action === 'clear'
      ? 'chequeClearance' : 'chequeBounce') &&
    header.status === 'posted' &&
    header.currency === cheque.currency &&
    header.totalDebitMinorUnits === amount &&
    header.totalCreditMinorUnits === amount &&
    cheque.settlementJournalEntryId === journalEntryId &&
    cheque.status === (command.action === 'clear' ? 'cleared' : 'bounced') &&
    date instanceof Date && date.getTime() === command.postedAt.getTime();
}

function sameLegacyChequeLines(lines, cheque, command, journalEntryId) {
  if (lines.size !== 2) return false;
  const customer = cheque.partyType === 'customer';
  const held = customer
    ? command.accounts.checksAccountId
    : command.accounts.issuedChecksAccountId;
  const opposite = command.action === 'clear'
    ? command.accounts.bankAccountId
    : customer
      ? command.accounts.customerReceivableAccountId
      : command.accounts.supplierPayableAccountId;
  const debitAccountId = customer ? opposite : held;
  const creditAccountId = customer ? held : opposite;
  return [
    [journalEntryId + '-debit', debitAccountId, 1, cheque.amountMinorUnits, 0],
    [journalEntryId + '-credit', creditAccountId, 2, 0, cheque.amountMinorUnits],
  ].every(([id, accountId, lineNumber, debit, credit]) => {
    const snapshot = lines.docs.find((doc) => doc.id === id);
    if (!snapshot) return false;
    const row = snapshot.data();
    const posted = row.postedAt?.toDate?.();
    return row.entryId === journalEntryId &&
      row.storeId === command.storeId &&
      row.accountId === accountId &&
      row.currency === cheque.currency &&
      row.lineNumber === lineNumber &&
      row.debitMinorUnits === debit &&
      row.creditMinorUnits === credit &&
      posted instanceof Date && posted.getTime() === command.postedAt.getTime();
  });
}

module.exports = {
  fingerprintChequeSettlement,
  sameLegacyChequeSettlement,
  sameLegacyChequeLines,
};

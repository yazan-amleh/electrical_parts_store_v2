'use strict';

const crypto = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');

function checkedMinorAdd(a, b, description) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    throw new HttpsError('invalid-argument',
      description + ' exceeds the safe minor-unit integer range.');
  }
  return a + b;
}

function readBalanceForPosting(snapshot, { storeId, accountId, currency }) {
  if (!snapshot.exists) return { debit: 0, credit: 0 };
  const row = snapshot.data() || {};
  if (row.storeId !== storeId || row.accountId !== accountId ||
      row.currency !== currency ||
      !Number.isSafeInteger(row.debitMinorUnits) ||
      !Number.isSafeInteger(row.creditMinorUnits) ||
      row.debitMinorUnits < 0 || row.creditMinorUnits < 0 ||
      !Number.isSafeInteger(row.balanceMinorUnits) ||
      row.balanceMinorUnits !== row.debitMinorUnits - row.creditMinorUnits) {
    throw new HttpsError('failed-precondition',
      'Account balance projection is corrupt or belongs to another store. ' +
      'Reconcile the journal before posting; never silently reset to zero.');
  }
  return { debit: row.debitMinorUnits, credit: row.creditMinorUnits };
}

function readPartyBalanceForPosting(snapshot, { storeId, partyId, partyType, currency }) {
  if (!snapshot.exists) return { debit: 0, credit: 0 };
  const row = snapshot.data() || {};
  if (row.storeId !== storeId || row.partyId !== partyId ||
      row.partyType !== partyType || row.currency !== currency ||
      !Number.isSafeInteger(row.debitMinorUnits) ||
      !Number.isSafeInteger(row.creditMinorUnits) ||
      row.debitMinorUnits < 0 || row.creditMinorUnits < 0 ||
      !Number.isSafeInteger(row.balanceMinorUnits) ||
      row.balanceMinorUnits !== row.debitMinorUnits - row.creditMinorUnits) {
    throw new HttpsError('failed-precondition',
      'Party balance projection is invalid. Reconcile the party ledger before posting.');
  }
  return { debit: row.debitMinorUnits, credit: row.creditMinorUnits };
}

// The order of normalized journal line items is part of its business identity.
function fingerprintJournal(entry) {
  const canonical = {
    id: entry.id,
    idempotencyKey: entry.idempotencyKey,
    postedAt: entry.postedAt.toISOString(),
    sourceType: entry.sourceType,
    description: entry.description,
    currency: entry.currency,
    totalDebitMinorUnits: entry.totalDebitMinorUnits,
    totalCreditMinorUnits: entry.totalCreditMinorUnits,
    lines: entry.lines.map((l) => ({
      id: l.id,
      accountId: l.accountId,
      description: l.description,
      lineNumber: l.lineNumber,
      debitMinorUnits: l.debitMinorUnits,
      creditMinorUnits: l.creditMinorUnits,
    })),
  };
  return crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
}

function isSameLegacyJournalHeader(row, entry) {
  const oldDate = row.postedAt?.toDate?.();
  return row.idempotencyKey === entry.idempotencyKey &&
    row.sourceType === entry.sourceType &&
    (row.description ?? null) === (entry.description ?? null) &&
    row.status === 'posted' &&
    row.currency === entry.currency &&
    row.totalDebitMinorUnits === entry.totalDebitMinorUnits &&
    row.totalCreditMinorUnits === entry.totalCreditMinorUnits &&
    oldDate instanceof Date &&
    oldDate.getTime() === entry.postedAt.getTime();
}

function isSameLegacyJournalLine(row, line, entry) {
  const oldDate = row.postedAt?.toDate?.();
  return row.entryId === entry.id &&
    row.accountId === line.accountId &&
    (row.description ?? null) === (line.description ?? null) &&
    row.lineNumber === line.lineNumber &&
    row.currency === entry.currency &&
    row.debitMinorUnits === line.debitMinorUnits &&
    row.creditMinorUnits === line.creditMinorUnits &&
    oldDate instanceof Date &&
    oldDate.getTime() === entry.postedAt.getTime();
}

module.exports = {
  checkedMinorAdd,
  readBalanceForPosting,
  readPartyBalanceForPosting,
  fingerprintJournal,
  isSameLegacyJournalHeader,
  isSameLegacyJournalLine,
};

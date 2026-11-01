'use strict';

const crypto = require('node:crypto');

function fingerprintAccountTransfer(transfer) {
  const canonical = {
    id: transfer.id,
    idempotencyKey: transfer.idempotencyKey,
    postedAt: transfer.postedAt.toISOString(),
    fromAccountId: transfer.fromAccountId,
    toAccountId: transfer.toAccountId,
    amountMinorUnits: transfer.amountMinorUnits,
    currency: transfer.currency,
    description: transfer.description,
  };
  return crypto.createHash('sha256')
    .update(JSON.stringify(canonical))
    .digest('hex');
}

function sameLegacyTransfer(row, transfer, journalEntryId) {
  const posted = row.postedAt?.toDate?.();
  return row.status === 'posted' &&
    row.idempotencyKey === transfer.idempotencyKey &&
    row.journalEntryId === journalEntryId &&
    row.fromAccountId === transfer.fromAccountId &&
    row.toAccountId === transfer.toAccountId &&
    row.amountMinorUnits === transfer.amountMinorUnits &&
    row.currency === transfer.currency &&
    (row.description ?? null) === (transfer.description ?? null) &&
    posted instanceof Date &&
    posted.getTime() === transfer.postedAt.getTime();
}

module.exports = {
  fingerprintAccountTransfer,
  sameLegacyTransfer,
};

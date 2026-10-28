'use strict';

const crypto = require('node:crypto');

function fingerprintSaleReturn(command) {
  const value = {
    storeId: command.storeId,
    id: command.saleReturn.id,
    idempotencyKey: command.saleReturn.idempotencyKey,
    originalSaleId: command.saleReturn.originalSaleId,
    postedAt: command.saleReturn.postedAt.toISOString(),
    reason: command.saleReturn.reason,
    lines: command.saleReturn.lines,
    accounts: command.accounts,
  };
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

module.exports = { fingerprintSaleReturn };

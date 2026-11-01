'use strict';

const crypto = require('node:crypto');

function fingerprintPurchaseReturn(command) {
  const value = {
    storeId: command.storeId,
    id: command.purchaseReturn.id,
    idempotencyKey: command.purchaseReturn.idempotencyKey,
    originalPurchaseId: command.purchaseReturn.originalPurchaseId,
    postedAt: command.purchaseReturn.postedAt.toISOString(),
    reason: command.purchaseReturn.reason,
    lines: command.purchaseReturn.lines,
    accounts: command.accounts,
  };
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

module.exports = { fingerprintPurchaseReturn };

'use strict';

const crypto = require('node:crypto');

function fingerprintOfferOrderConfirmation(command) {
  const value = {
    storeId: command.storeId,
    orderId: command.orderId,
    idempotencyKey: command.idempotencyKey,
    postedAt: command.postedAt.toISOString(),
    paymentMethod: command.paymentMethod,
    accounts: command.accounts,
  };
  return crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

module.exports = {fingerprintOfferOrderConfirmation};

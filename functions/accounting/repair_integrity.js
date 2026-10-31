'use strict';

const crypto = require('node:crypto');

function digest(value) {
  return crypto.createHash('sha256')
    .update(JSON.stringify(value))
    .digest('hex');
}

function fingerprintRepairDelivery(command) {
  return digest({
    storeId: command.storeId,
    repairId: command.repairId,
    idempotencyKey: command.idempotencyKey,
    postedAt: command.postedAt.toISOString(),
    accounts: command.accounts,
  });
}

function fingerprintRepairPayment(command, kind) {
  return digest({
    storeId: command.storeId,
    repairId: command.repairId,
    kind,
    payment: {
      id: command.payment.id,
      idempotencyKey: command.payment.idempotencyKey,
      postedAt: command.payment.postedAt.toISOString(),
      paymentMethod: command.payment.paymentMethod,
      amountMinorUnits: command.payment.amountMinorUnits,
      currency: command.payment.currency,
      description: command.payment.description,
      chequeNumber: command.payment.chequeNumber,
      bankName: command.payment.bankName,
      dueDate: command.payment.dueDate?.toISOString?.() ?? null,
    },
    accounts: command.accounts,
  });
}

function sameLegacyRepairAdvance(payment, marker, command) {
  if (!payment || !marker) return false;
  const postedAt = payment.postedAt?.toDate?.();
  const dueDate = payment.dueDate?.toDate?.() ?? null;
  return marker.storeId === command.storeId &&
    marker.repairId === command.repairId &&
    marker.paymentId === command.payment.id &&
    marker.journalEntryId === command.payment.id + '-journal' &&
    payment.storeId === command.storeId &&
    payment.repairId === command.repairId &&
    payment.paymentKind === 'advance' &&
    payment.idempotencyKey === command.payment.idempotencyKey &&
    payment.paymentMethod === command.payment.paymentMethod &&
    payment.amountMinorUnits === command.payment.amountMinorUnits &&
    payment.currency === command.payment.currency &&
    (payment.description ?? null) === (command.payment.description ?? null) &&
    (payment.chequeNumber ?? null) === (command.payment.chequeNumber ?? null) &&
    (payment.bankName ?? null) === (command.payment.bankName ?? null) &&
    ((dueDate == null && command.payment.dueDate == null) ||
      (dueDate instanceof Date &&
        command.payment.dueDate instanceof Date &&
        dueDate.getTime() === command.payment.dueDate.getTime())) &&
    postedAt instanceof Date &&
    postedAt.getTime() === command.payment.postedAt.getTime();
}

module.exports = {
  fingerprintRepairDelivery,
  fingerprintRepairPayment,
  sameLegacyRepairAdvance,
};

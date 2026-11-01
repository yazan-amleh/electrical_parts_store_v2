'use strict';

const crypto = require('node:crypto');

function fingerprintInventoryMovement(command) {
  const movement = command.movement;
  return crypto.createHash('sha256').update(JSON.stringify({
    storeId: command.storeId,
    id: movement.id,
    key: movement.idempotencyKey,
    productId: movement.productId,
    type: movement.type,
    quantityDeltaMilliUnits: movement.quantityDeltaMilliUnits,
    unitCostMinorUnits: movement.unitCostMinorUnits,
    totalCostMinorUnits: movement.totalCostMinorUnits,
    currency: movement.currency,
    sourceType: movement.sourceType,
    sourceId: movement.sourceId,
    description: movement.description,
    occurredAt: movement.occurredAt.toISOString(),
  })).digest('hex');
}

function matchesLegacyInventoryMovement(row, command) {
  const movement = command.movement;
  const occurredAt = row.occurredAt?.toDate?.();
  return row.storeId === command.storeId &&
    row.productId === movement.productId &&
    row.type === movement.type &&
    row.quantityDeltaMilliUnits === movement.quantityDeltaMilliUnits &&
    row.unitCostMinorUnits === movement.unitCostMinorUnits &&
    row.totalCostMinorUnits === movement.totalCostMinorUnits &&
    row.currency === movement.currency &&
    row.idempotencyKey === movement.idempotencyKey &&
    (row.sourceType ?? '') === movement.sourceType &&
    (row.sourceId ?? null) === (movement.sourceId ?? null) &&
    (row.description ?? '') === movement.description &&
    occurredAt instanceof Date &&
    occurredAt.getTime() === movement.occurredAt.getTime();
}

module.exports = {
  fingerprintInventoryMovement,
  matchesLegacyInventoryMovement,
};

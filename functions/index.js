const { setGlobalOptions } = require('firebase-functions/v2');
const {
  HttpsError,
  onCall,
} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

admin.initializeApp();
setGlobalOptions({
  maxInstances: 10,
  region: 'europe-west1',
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;
const QUANTITY_SCALE = 1000;
const MAX_LINES = 100;
const POSTING_ROLES = new Set(['owner', 'admin', 'accountant', 'sales']);
const OFFER_ROLES = new Set(['owner', 'admin', 'accountant', 'sales']);
const OFFER_PRICE_TYPES = new Set(['retail', 'wholesale', 'custom']);
const PARTY_PAYMENT_METHODS = new Set(['cash', 'bank', 'card']);
const EXPENSE_PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);
const PAYMENT_POSTING_ROLES = new Set(['owner', 'admin', 'accountant']);
const PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);
const PURCHASE_PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);
const PURCHASE_ORDER_ROLES = new Set([
  'owner',
  'admin',
  'accountant',
  'warehouse',
]);
const INVENTORY_MOVEMENT_TYPES = new Set([
  'openingBalance',
  'adjustment',
  'saleReturn',
  'purchaseReturn',
]);
const INVENTORY_POSTING_ROLES = new Set(['owner', 'admin', 'warehouse']);

exports.postInventoryMovement = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseInventoryMovementCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postInventoryMovementInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postInventoryMovement failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The inventory movement could not be posted.',
    );
  }
});

exports.postJournalEntry = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseJournalEntryCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postJournalEntryInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postJournalEntry failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The journal entry could not be posted.',
    );
  }
});

exports.postSale = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postSaleInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postSale failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The sale could not be posted.',
    );
  }
});

exports.postPurchase = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parsePurchaseCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postPurchaseInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postPurchase failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The purchase could not be posted.',
    );
  }
});



exports.createOffer = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferCreateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return createOfferInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('createOffer failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer could not be created.');
  }
});

exports.updateOffer = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferUpdateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return updateOfferInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('updateOffer failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer could not be updated.');
  }
});

exports.setOfferActive = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferActiveCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return setOfferActiveInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('setOfferActive failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer status could not be changed.');
  }
});

exports.archiveOffer = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferArchiveCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return archiveOfferInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('archiveOffer failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer could not be archived.');
  }
});

exports.createOfferOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferOrderCreateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return createOfferOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('createOfferOrder failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer order could not be created.');
  }
});

exports.cancelOfferOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferOrderCancelCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return cancelOfferOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('cancelOfferOrder failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer order could not be cancelled.');
  }
});

exports.confirmOfferOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseOfferOrderConfirmCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return confirmOfferOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('confirmOfferOrder failed', {message: error.message, stack: error.stack});
    throw new HttpsError('internal', 'The offer order could not be confirmed.');
  }
});

exports.createPurchaseOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parsePurchaseOrderCreateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return createPurchaseOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('createPurchaseOrder failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The purchase order could not be created.',
    );
  }
});

exports.cancelPurchaseOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parsePurchaseOrderCancelCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return cancelPurchaseOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('cancelPurchaseOrder failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The purchase order could not be cancelled.',
    );
  }
});

exports.receivePurchaseOrder = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parsePurchaseOrderReceiveCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return receivePurchaseOrderInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('receivePurchaseOrder failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The purchase order could not be received.',
    );
  }
});

exports.postAccountTransfer = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseAccountTransferCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postAccountTransferInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postAccountTransfer failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The account transfer could not be posted.',
    );
  }
});

exports.postExpense = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseExpenseCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postExpenseInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postExpense failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The expense could not be posted.',
    );
  }
});

exports.postPartyPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parsePartyPaymentCommand(request.data);

  try {
    return await db.runTransaction(async (transaction) => {
      return postPartyPaymentInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postPartyPayment failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The party payment could not be posted.',
    );
  }
});

function parseInventoryMovementCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const rawMovement = asObject(command.movement, 'movement');
  const type = stringValue(rawMovement.type, 'movement.type');
  if (!INVENTORY_MOVEMENT_TYPES.has(type)) {
    invalid('This inventory movement type must use a business command.');
  }

  const quantityDeltaMilliUnits = rawMovement.quantityDeltaMilliUnits;
  if (!Number.isSafeInteger(quantityDeltaMilliUnits) ||
      quantityDeltaMilliUnits === 0) {
    invalid('movement.quantityDeltaMilliUnits must be a non-zero integer.');
  }

  return {
    storeId,
    movement: {
      id: safeId(rawMovement.id, 'movement.id'),
      idempotencyKey: safeId(
        rawMovement.idempotencyKey,
        'movement.idempotencyKey',
      ),
      productId: safeId(rawMovement.productId, 'movement.productId'),
      type,
      quantityDeltaMilliUnits,
      unitCostMinorUnits: nonNegativeInt(
        rawMovement.unitCostMinorUnits,
        'movement.unitCostMinorUnits',
      ),
      totalCostMinorUnits: nonNegativeInt(
        rawMovement.totalCostMinorUnits,
        'movement.totalCostMinorUnits',
      ),
      currency: stringValue(rawMovement.currency, 'movement.currency'),
      sourceType: rawMovement.sourceType == null
        ? ''
        : stringValue(rawMovement.sourceType, 'movement.sourceType'),
      sourceId: optionalSafeId(rawMovement.sourceId, 'movement.sourceId'),
      description: optionalText(
        rawMovement.description,
        'movement.description',
      ),
      occurredAt: parseDate(
        rawMovement.occurredAt,
        'movement.occurredAt',
      ),
    },
  };
}

async function postInventoryMovementInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const productRef = storeRef
    .collection('products')
    .doc(command.movement.productId);
  const movementRef = storeRef
    .collection('inventory_movements')
    .doc(command.movement.id);
  const idempotencyRef = storeRef
    .collection('inventory_idempotency')
    .doc(command.movement.idempotencyKey);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post inventory movements',
    INVENTORY_POSTING_ROLES,
  );

  const idempotencySnapshot = await transaction.get(idempotencyRef);
  if (idempotencySnapshot.exists) {
    const existingMovementId = idempotencySnapshot.data().movementId;
    if (existingMovementId === command.movement.id) {
      return {
        status: 'already_posted',
        movementId: command.movement.id,
      };
    }
    conflict('The inventory idempotency key is already assigned.');
  }

  const existingMovementSnapshot = await transaction.get(movementRef);
  if (existingMovementSnapshot.exists) {
    conflict('The inventory movement id already exists.');
  }

  const productSnapshot = await transaction.get(productRef);
  if (!productSnapshot.exists) {
    invalid('Product was not found.');
  }

  const product = productSnapshot.data();
  if (product.storeId !== command.storeId) {
    deny('Product belongs to another store.');
  }
  if (product.isService === true) {
    invalid('Services cannot receive stock movements.');
  }

  const currency = product.currency || 'ILS';
  if (currency !== command.movement.currency) {
    invalid('Movement currency does not match the product.');
  }

  const currentQuantity = storedInt(
    product.quantityOnHandMilliUnits,
    0,
  );
  const currentInventoryValue = Number.isSafeInteger(
    product.inventoryValueMinorUnits,
  )
    ? product.inventoryValueMinorUnits
    : multiplyAndRound(
      storedInt(product.purchasePriceMinorUnits, 0),
      currentQuantity,
    );
  const nextQuantity =
    currentQuantity + command.movement.quantityDeltaMilliUnits;
  if (nextQuantity < 0) {
    throw new HttpsError(
      'failed-precondition',
      'The movement would create negative stock.',
    );
  }

  const nextInventoryValue = command.movement.quantityDeltaMilliUnits < 0
    ? currentInventoryValue - command.movement.totalCostMinorUnits
    : currentInventoryValue + command.movement.totalCostMinorUnits;
  if (nextInventoryValue < 0) {
    throw new HttpsError(
      'failed-precondition',
      'The movement would create negative inventory value.',
    );
  }

  transaction.update(productRef, {
    quantityOnHandMilliUnits: nextQuantity,
    inventoryValueMinorUnits: nextInventoryValue,
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(movementRef, {
    storeId: command.storeId,
    productId: command.movement.productId,
    type: command.movement.type,
    quantityDeltaMilliUnits: command.movement.quantityDeltaMilliUnits,
    unitCostMinorUnits: command.movement.unitCostMinorUnits,
    totalCostMinorUnits: command.movement.totalCostMinorUnits,
    currency: command.movement.currency,
    idempotencyKey: command.movement.idempotencyKey,
    sourceType: command.movement.sourceType,
    sourceId: command.movement.sourceId,
    description: command.movement.description,
    occurredAt: Timestamp.fromDate(command.movement.occurredAt),
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    movementId: command.movement.id,
    idempotencyKey: command.movement.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: 'posted',
    movementId: command.movement.id,
  };
}

function parseJournalEntryCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const rawEntry = asObject(command.entry, 'entry');
  const rawLines = rawEntry.lines;

  if (!Array.isArray(rawLines) ||
      rawLines.length < 2 ||
      rawLines.length > MAX_LINES) {
    invalid('A journal entry must contain between 2 and ' + MAX_LINES +
      ' lines.');
  }

  const currency = stringValue(rawEntry.currency, 'entry.currency');
  const lines = [];
  const lineIds = new Set();
  let totalDebitMinorUnits = 0;
  let totalCreditMinorUnits = 0;

  for (let index = 0; index < rawLines.length; index++) {
    const rawLine = asObject(rawLines[index], 'entry.lines[' + index + ']');
    const lineId = safeId(
      rawLine.id,
      'entry.lines[' + index + '].id',
    );
    if (lineIds.has(lineId)) {
      invalid('Journal line ids must be unique.');
    }
    lineIds.add(lineId);

    const debitMinorUnits = nonNegativeInt(
      rawLine.debitMinorUnits,
      'entry.lines[' + index + '].debitMinorUnits',
    );
    const creditMinorUnits = nonNegativeInt(
      rawLine.creditMinorUnits,
      'entry.lines[' + index + '].creditMinorUnits',
    );
    if ((debitMinorUnits === 0) === (creditMinorUnits === 0)) {
      invalid('Each journal line must contain exactly one side.');
    }

    totalDebitMinorUnits += debitMinorUnits;
    totalCreditMinorUnits += creditMinorUnits;
    lines.push({
      id: lineId,
      accountId: safeId(
        rawLine.accountId,
        'entry.lines[' + index + '].accountId',
      ),
      description: rawLine.description == null
        ? null
        : stringValue(
          rawLine.description,
          'entry.lines[' + index + '].description',
        ),
      debitMinorUnits,
      creditMinorUnits,
      lineNumber: index + 1,
    });
  }

  if (totalDebitMinorUnits <= 0 ||
      totalDebitMinorUnits !== totalCreditMinorUnits) {
    invalid('The journal entry must be balanced and greater than zero.');
  }

  return {
    storeId,
    entry: {
      id: safeId(rawEntry.id, 'entry.id'),
      idempotencyKey: safeId(
        rawEntry.idempotencyKey,
        'entry.idempotencyKey',
      ),
      postedAt: parseDate(rawEntry.postedAt, 'entry.postedAt'),
      sourceType: stringValue(rawEntry.sourceType, 'entry.sourceType'),
      description: rawEntry.description == null
        ? null
        : stringValue(rawEntry.description, 'entry.description'),
      currency,
      totalDebitMinorUnits,
      totalCreditMinorUnits,
      lines,
    },
  };
}

async function postJournalEntryInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(command.entry.id);
  const idempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(command.entry.idempotencyKey);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post journal entries',
    PAYMENT_POSTING_ROLES,
  );

  const idempotencySnapshot = await transaction.get(idempotencyRef);
  if (idempotencySnapshot.exists) {
    const existingEntryId = idempotencySnapshot.data().entryId;
    if (existingEntryId === command.entry.id) {
      return {
        status: 'already_posted',
        entryId: command.entry.id,
      };
    }
    conflict('The journal idempotency key is already assigned.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The journal entry id already exists.');
  }

  const accountIds = [
    ...new Set(command.entry.lines.map((line) => line.accountId)),
  ];
  const accountSnapshots = new Map();
  const balanceSnapshots = new Map();
  for (const accountId of accountIds) {
    const accountRef = storeRef.collection('accounts').doc(accountId);
    accountSnapshots.set(accountId, await transaction.get(accountRef));
  }
  for (const accountId of accountIds) {
    const balanceRef = storeRef.collection('account_balances').doc(accountId);
    balanceSnapshots.set(accountId, await transaction.get(balanceRef));
  }

  const deltas = new Map();
  for (const line of command.entry.lines) {
    const accountSnapshot = accountSnapshots.get(line.accountId);
    if (!accountSnapshot.exists) {
      invalid('Account was not found: ' + line.accountId);
    }

    const account = accountSnapshot.data();
    if (account.storeId !== command.storeId) {
      deny('Account belongs to another store.');
    }
    if (account.isActive === false || account.isHeader === true) {
      invalid('Account is not postable: ' + line.accountId);
    }
    if (account.currency !== command.entry.currency) {
      invalid('Account currency does not match the journal.');
    }

    const previous = deltas.get(line.accountId) || {
      debit: 0,
      credit: 0,
    };
    deltas.set(line.accountId, {
      debit: previous.debit + line.debitMinorUnits,
      credit: previous.credit + line.creditMinorUnits,
    });
  }

  transaction.set(journalRef, {
    storeId: command.storeId,
    idempotencyKey: command.entry.idempotencyKey,
    sourceType: command.entry.sourceType,
    description: command.entry.description,
    status: 'posted',
    currency: command.entry.currency,
    totalDebitMinorUnits: command.entry.totalDebitMinorUnits,
    totalCreditMinorUnits: command.entry.totalCreditMinorUnits,
    postedAt: Timestamp.fromDate(command.entry.postedAt),
  });

  for (const line of command.entry.lines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        storeId: command.storeId,
        entryId: command.entry.id,
        accountId: line.accountId,
        description: line.description,
        lineNumber: line.lineNumber,
        currency: command.entry.currency,
        debitMinorUnits: line.debitMinorUnits,
        creditMinorUnits: line.creditMinorUnits,
        postedAt: Timestamp.fromDate(command.entry.postedAt),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const previousDebit = storedInt(balance.debitMinorUnits, 0);
    const previousCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = deltas.get(accountId);

    transaction.set(
      storeRef.collection('account_balances').doc(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.entry.currency,
        debitMinorUnits: previousDebit + delta.debit,
        creditMinorUnits: previousCredit + delta.credit,
        balanceMinorUnits:
          previousDebit + delta.debit - previousCredit - delta.credit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    entryId: command.entry.id,
    idempotencyKey: command.entry.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: 'posted',
    entryId: command.entry.id,
  };
}

function parseAccountTransferCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const transfer = asObject(command.transfer, 'transfer');
  const fromAccountId = safeId(
    transfer.fromAccountId,
    'fromAccountId',
  );
  const toAccountId = safeId(
    transfer.toAccountId,
    'toAccountId',
  );
  if (fromAccountId === toAccountId) {
    invalid('Source and destination accounts must be different.');
  }

  return {
    storeId,
    transfer: {
      id: safeId(transfer.id, 'transfer id'),
      idempotencyKey: safeId(
        transfer.idempotencyKey,
        'transfer idempotency key',
      ),
      postedAt: parseDate(transfer.postedAt, 'transfer.postedAt'),
      fromAccountId,
      toAccountId,
      amountMinorUnits: positiveInt(
        transfer.amountMinorUnits,
        'transfer.amountMinorUnits',
      ),
      currency: stringValue(transfer.currency, 'transfer.currency'),
      description: transfer.description == null
        ? null
        : stringValue(transfer.description, 'transfer.description'),
    },
  };
}

async function postAccountTransferInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const transferRef = storeRef
    .collection('account_transfers')
    .doc(command.transfer.id);
  const transferIdempotencyRef = storeRef
    .collection('account_transfer_idempotency')
    .doc(command.transfer.idempotencyKey);
  const journalEntryId = command.transfer.id + '-journal';
  const journalIdempotencyKey = command.transfer.idempotencyKey +
    ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post account transfers',
    PAYMENT_POSTING_ROLES,
  );

  const transferIdempotencySnapshot = await transaction.get(
    transferIdempotencyRef,
  );
  if (transferIdempotencySnapshot.exists) {
    const existingTransferId =
      transferIdempotencySnapshot.data().transferId;
    if (existingTransferId === command.transfer.id) {
      return {
        status: 'already_posted',
        transferId: command.transfer.id,
        journalEntryId,
      };
    }
    conflict('The transfer idempotency key is already assigned.');
  }

  const existingTransferSnapshot = await transaction.get(transferRef);
  if (existingTransferSnapshot.exists) {
    conflict('The account transfer id already exists.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The transfer journal id already exists.');
  }

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The transfer journal idempotency key already exists.');
  }

  const accountIds = [
    command.transfer.fromAccountId,
    command.transfer.toAccountId,
  ];
  const accountRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('accounts').doc(accountId),
    ]),
  );
  const accountSnapshots = new Map();
  for (const [accountId, accountRef] of accountRefs) {
    accountSnapshots.set(
      accountId,
      await transaction.get(accountRef),
    );
  }

  const balanceRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('account_balances').doc(accountId),
    ]),
  );
  const balanceSnapshots = new Map();
  for (const [accountId, balanceRef] of balanceRefs) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(balanceRef),
    );
  }

  assertTransferAccount(
    accountSnapshots.get(command.transfer.fromAccountId),
    command.transfer.fromAccountId,
    command.storeId,
    command.transfer.currency,
  );
  assertTransferAccount(
    accountSnapshots.get(command.transfer.toAccountId),
    command.transfer.toAccountId,
    command.storeId,
    command.transfer.currency,
  );

  const amount = command.transfer.amountMinorUnits;
  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    command.transfer.toAccountId,
    amount,
    0,
  );
  addDelta(
    accountDeltas,
    command.transfer.fromAccountId,
    0,
    amount,
  );

  const journalLines = [
    {
      id: command.transfer.id + '-destination',
      storeId: command.storeId,
      accountId: command.transfer.toAccountId,
      description: 'Internal account transfer',
      lineNumber: 1,
      debitMinorUnits: amount,
      creditMinorUnits: 0,
    },
    {
      id: command.transfer.id + '-source',
      storeId: command.storeId,
      accountId: command.transfer.fromAccountId,
      description: 'Internal account transfer',
      lineNumber: 2,
      debitMinorUnits: 0,
      creditMinorUnits: amount,
    },
  ];

  transaction.set(
    transferRef,
    {
      storeId: command.storeId,
      idempotencyKey: command.transfer.idempotencyKey,
      postedAt: Timestamp.fromDate(command.transfer.postedAt),
      fromAccountId: command.transfer.fromAccountId,
      toAccountId: command.transfer.toAccountId,
      amountMinorUnits: amount,
      currency: command.transfer.currency,
      description: command.transfer.description,
      journalEntryId,
      status: 'posted',
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  transaction.set(
    journalRef,
    {
      storeId: command.storeId,
      idempotencyKey: journalIdempotencyKey,
      sourceType: 'accountTransfer',
      description: command.transfer.description,
      status: 'posted',
      currency: command.transfer.currency,
      totalDebitMinorUnits: amount,
      totalCreditMinorUnits: amount,
      postedAt: Timestamp.fromDate(command.transfer.postedAt),
    },
  );
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.transfer.postedAt),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };

    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.transfer.currency,
        debitMinorUnits: currentDebit + delta.debit,
        creditMinorUnits: currentCredit + delta.credit,
        balanceMinorUnits:
          currentDebit + delta.debit - currentCredit - delta.credit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    transferIdempotencyRef,
    {
      storeId: command.storeId,
      transferId: command.transfer.id,
      idempotencyKey: command.transfer.idempotencyKey,
      journalEntryId,
      createdAt: FieldValue.serverTimestamp(),
    },
  );
  transaction.set(
    journalIdempotencyRef,
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      idempotencyKey: journalIdempotencyKey,
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  return {
    status: 'posted',
    transferId: command.transfer.id,
    journalEntryId,
  };
}

function parseExpenseCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const expense = asObject(command.expense, 'expense');
  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );

  const paymentMethod = stringValue(
    expense.paymentMethod,
    'expense.paymentMethod',
  );
  if (!EXPENSE_PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported expense payment method.');
  }

  const supplierId = optionalSafeId(expense.supplierId, 'supplierId');
  if (paymentMethod === 'credit' && !supplierId) {
    invalid('A credit expense requires a supplier.');
  }

  const accounts = {
    settlementAccountId: optionalSafeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    supplierPayableAccountId: optionalSafeId(
      postingAccounts.supplierPayableAccountId,
      'supplierPayableAccountId',
    ),
    inputTaxAccountId: optionalSafeId(
      postingAccounts.inputTaxAccountId,
      'inputTaxAccountId',
    ),
  };
  const expenseAccountId = safeId(
    expense.expenseAccountId,
    'expenseAccountId',
  );
  const paymentAccountId = paymentMethod === 'credit'
    ? accounts.supplierPayableAccountId
    : accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid(
      paymentMethod === 'credit'
        ? 'A supplier payable account is required for credit expenses.'
        : 'A settlement account is required for paid expenses.',
    );
  }

  const amountMinorUnits = positiveInt(
    expense.amountMinorUnits,
    'expense.amountMinorUnits',
  );
  const taxMinorUnits = nonNegativeInt(
    expense.taxMinorUnits,
    'expense.taxMinorUnits',
  );
  if (taxMinorUnits > 0 && !accounts.inputTaxAccountId) {
    invalid('An input tax account is required when tax is present.');
  }

  const providedAccountIds = [
    expenseAccountId,
    accounts.settlementAccountId,
    accounts.supplierPayableAccountId,
    accounts.inputTaxAccountId,
  ].filter(Boolean);
  if (new Set(providedAccountIds).size !== providedAccountIds.length) {
    invalid('Expense posting accounts must be distinct.');
  }

  return {
    storeId,
    expense: {
      id: safeId(expense.id, 'expense id'),
      idempotencyKey: safeId(
        expense.idempotencyKey,
        'expense idempotency key',
      ),
      postedAt: parseDate(expense.postedAt, 'expense.postedAt'),
      paymentMethod,
      expenseAccountId,
      supplierId,
      description: expense.description == null
        ? null
        : stringValue(expense.description, 'expense.description'),
      currency: stringValue(expense.currency, 'expense.currency'),
      amountMinorUnits,
      taxMinorUnits,
    },
    accounts,
  };
}

async function postExpenseInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const expenseRef = storeRef
    .collection('expenses')
    .doc(command.expense.id);
  const expenseIdempotencyRef = storeRef
    .collection('expense_idempotency')
    .doc(command.expense.idempotencyKey);
  const journalEntryId = command.expense.id + '-journal';
  const journalIdempotencyKey = command.expense.idempotencyKey +
    ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);
  const isCreditExpense = command.expense.paymentMethod === 'credit';
  const supplierLedgerId = isCreditExpense
    ? command.expense.id + '-supplier'
    : null;
  const supplierLedgerRef = isCreditExpense
    ? storeRef.collection('party_ledger_entries').doc(supplierLedgerId)
    : null;
  const supplierBalanceId = isCreditExpense
    ? 'supplier-' + command.expense.supplierId
    : null;
  const supplierBalanceRef = isCreditExpense
    ? storeRef.collection('party_balances').doc(supplierBalanceId)
    : null;

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post expenses',
    PAYMENT_POSTING_ROLES,
  );

  const expenseIdempotencySnapshot = await transaction.get(
    expenseIdempotencyRef,
  );
  if (expenseIdempotencySnapshot.exists) {
    const existingExpenseId =
      expenseIdempotencySnapshot.data().expenseId;
    if (existingExpenseId === command.expense.id) {
      return {
        status: 'already_posted',
        expenseId: command.expense.id,
        journalEntryId,
      };
    }
    conflict('The expense idempotency key is already assigned.');
  }

  const existingExpenseSnapshot = await transaction.get(expenseRef);
  if (existingExpenseSnapshot.exists) {
    conflict('The expense id already exists.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The expense journal id already exists.');
  }

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The expense journal idempotency key already exists.');
  }

  let supplierLedgerSnapshot = null;
  let supplierBalanceSnapshot = null;
  if (isCreditExpense) {
    supplierLedgerSnapshot = await transaction.get(supplierLedgerRef);
    if (supplierLedgerSnapshot.exists) {
      conflict('A supplier ledger entry for this expense already exists.');
    }
    supplierBalanceSnapshot = await transaction.get(supplierBalanceRef);
  }

  const paymentAccountId = isCreditExpense
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid('The expense payment account is required.');
  }

  const accountIds = [
    command.expense.expenseAccountId,
    paymentAccountId,
  ];
  if (command.expense.taxMinorUnits > 0) {
    accountIds.push(command.accounts.inputTaxAccountId);
  }

  const accountRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('accounts').doc(accountId),
    ]),
  );
  const accountSnapshots = new Map();
  for (const [accountId, accountRef] of accountRefs) {
    accountSnapshots.set(
      accountId,
      await transaction.get(accountRef),
    );
  }

  const balanceRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('account_balances').doc(accountId),
    ]),
  );
  const balanceSnapshots = new Map();
  for (const [accountId, balanceRef] of balanceRefs) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(balanceRef),
    );
  }

  assertAccount(
    accountSnapshots.get(command.expense.expenseAccountId),
    command.expense.expenseAccountId,
    command.storeId,
    command.expense.currency,
    'expense',
  );
  if (isCreditExpense) {
    assertAccount(
      accountSnapshots.get(command.accounts.supplierPayableAccountId),
      command.accounts.supplierPayableAccountId,
      command.storeId,
      command.expense.currency,
      'liability',
      'supplierPayable',
    );
  } else {
    assertAccount(
      accountSnapshots.get(command.accounts.settlementAccountId),
      command.accounts.settlementAccountId,
      command.storeId,
      command.expense.currency,
      'asset',
      paymentAccountControlType(command.expense.paymentMethod),
    );
  }
  if (command.expense.taxMinorUnits > 0) {
    assertAccount(
      accountSnapshots.get(command.accounts.inputTaxAccountId),
      command.accounts.inputTaxAccountId,
      command.storeId,
      command.expense.currency,
      'asset',
      'inputTax',
    );
  }

  const totalMinorUnits =
    command.expense.amountMinorUnits + command.expense.taxMinorUnits;
  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    command.expense.expenseAccountId,
    command.expense.amountMinorUnits,
    0,
  );
  if (command.expense.taxMinorUnits > 0) {
    addDelta(
      accountDeltas,
      command.accounts.inputTaxAccountId,
      command.expense.taxMinorUnits,
      0,
    );
  }
  addDelta(accountDeltas, paymentAccountId, 0, totalMinorUnits);

  const journalLines = [
    {
      id: command.expense.id + '-expense',
      storeId: command.storeId,
      accountId: command.expense.expenseAccountId,
      description: 'Operating expense',
      lineNumber: 1,
      debitMinorUnits: command.expense.amountMinorUnits,
      creditMinorUnits: 0,
    },
  ];
  if (command.expense.taxMinorUnits > 0) {
    journalLines.push({
      id: command.expense.id + '-input-tax',
      storeId: command.storeId,
      accountId: command.accounts.inputTaxAccountId,
      description: 'Input tax',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: command.expense.taxMinorUnits,
      creditMinorUnits: 0,
    });
  }
  journalLines.push({
    id: command.expense.id + '-payment',
    storeId: command.storeId,
    accountId: paymentAccountId,
    description: command.expense.paymentMethod,
    lineNumber: journalLines.length + 1,
    debitMinorUnits: 0,
    creditMinorUnits: totalMinorUnits,
  });

  const expenseData = {
    storeId: command.storeId,
    idempotencyKey: command.expense.idempotencyKey,
    postedAt: Timestamp.fromDate(command.expense.postedAt),
    paymentMethod: command.expense.paymentMethod,
    expenseAccountId: command.expense.expenseAccountId,
    supplierId: command.expense.supplierId,
    description: command.expense.description,
    currency: command.expense.currency,
    amountMinorUnits: command.expense.amountMinorUnits,
    taxMinorUnits: command.expense.taxMinorUnits,
    totalMinorUnits,
    journalEntryId,
    status: 'posted',
    createdAt: FieldValue.serverTimestamp(),
  };
  transaction.set(expenseRef, expenseData);

  transaction.set(
    journalRef,
    {
      storeId: command.storeId,
      idempotencyKey: journalIdempotencyKey,
      sourceType: 'expense',
      description: command.expense.description,
      status: 'posted',
      currency: command.expense.currency,
      totalDebitMinorUnits: totalMinorUnits,
      totalCreditMinorUnits: totalMinorUnits,
      postedAt: Timestamp.fromDate(command.expense.postedAt),
    },
  );
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.expense.postedAt),
      },
    );
  }

  if (isCreditExpense) {
    const balance = supplierBalanceSnapshot.exists
      ? supplierBalanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const nextDebit = currentDebit;
    const nextCredit = currentCredit + totalMinorUnits;

    transaction.set(
      supplierLedgerRef,
      {
        storeId: command.storeId,
        partyType: 'supplier',
        partyId: command.expense.supplierId,
        sourceType: 'expense',
        sourceId: command.expense.id,
        currency: command.expense.currency,
        debitMinorUnits: 0,
        creditMinorUnits: totalMinorUnits,
        description: command.expense.description,
        postedAt: Timestamp.fromDate(command.expense.postedAt),
      },
    );
    transaction.set(
      supplierBalanceRef,
      {
        storeId: command.storeId,
        partyType: 'supplier',
        partyId: command.expense.supplierId,
        currency: command.expense.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };
    const nextDebit = currentDebit + delta.debit;
    const nextCredit = currentCredit + delta.credit;

    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.expense.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    expenseIdempotencyRef,
    {
      storeId: command.storeId,
      expenseId: command.expense.id,
      idempotencyKey: command.expense.idempotencyKey,
      journalEntryId,
      createdAt: FieldValue.serverTimestamp(),
    },
  );
  transaction.set(
    journalIdempotencyRef,
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      idempotencyKey: journalIdempotencyKey,
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  return {
    status: 'posted',
    expenseId: command.expense.id,
    journalEntryId,
  };
}

function parsePartyPaymentCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const payment = asObject(command.payment, 'payment');
  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );

  const partyType = stringValue(
    payment.partyType,
    'payment.partyType',
  );
  if (partyType !== 'customer' && partyType !== 'supplier') {
    invalid('Unsupported party type.');
  }

  const paymentMethod = stringValue(
    payment.paymentMethod,
    'payment.paymentMethod',
  );
  if (!PARTY_PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported party payment method.');
  }

  const accounts = {
    settlementAccountId: safeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    partyAccountId: safeId(
      postingAccounts.partyAccountId,
      'partyAccountId',
    ),
  };
  if (accounts.settlementAccountId === accounts.partyAccountId) {
    invalid('Party payment accounts must be distinct.');
  }

  return {
    storeId,
    payment: {
      id: safeId(payment.id, 'payment id'),
      idempotencyKey: safeId(
        payment.idempotencyKey,
        'payment idempotency key',
      ),
      postedAt: parseDate(payment.postedAt, 'payment.postedAt'),
      partyType,
      partyId: safeId(payment.partyId, 'partyId'),
      paymentMethod,
      amountMinorUnits: positiveInt(
        payment.amountMinorUnits,
        'payment.amountMinorUnits',
      ),
      currency: stringValue(payment.currency, 'payment.currency'),
      description: payment.description == null
        ? null
        : stringValue(payment.description, 'payment.description'),
    },
    accounts,
  };
}

async function postPartyPaymentInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const paymentRef = storeRef
    .collection('party_payments')
    .doc(command.payment.id);
  const paymentIdempotencyRef = storeRef
    .collection('party_payment_idempotency')
    .doc(command.payment.idempotencyKey);
  const journalEntryId = command.payment.id + '-journal';
  const journalIdempotencyKey = command.payment.idempotencyKey +
    ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);
  const partyLedgerId = command.payment.id + '-' +
    command.payment.partyType;
  const partyLedgerRef = storeRef
    .collection('party_ledger_entries')
    .doc(partyLedgerId);
  const partyBalanceId = command.payment.partyType + '-' +
    command.payment.partyId;
  const partyBalanceRef = storeRef
    .collection('party_balances')
    .doc(partyBalanceId);
  const partyRef = storeRef.collection('parties').doc(command.payment.partyId);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post party payments',
    PAYMENT_POSTING_ROLES,
  );

  const paymentIdempotencySnapshot = await transaction.get(
    paymentIdempotencyRef,
  );
  if (paymentIdempotencySnapshot.exists) {
    const existingPaymentId =
      paymentIdempotencySnapshot.data().paymentId;
    if (existingPaymentId === command.payment.id) {
      return {
        status: 'already_posted',
        paymentId: command.payment.id,
        journalEntryId,
      };
    }
    conflict('The payment idempotency key is already assigned.');
  }

  const existingPaymentSnapshot = await transaction.get(paymentRef);
  if (existingPaymentSnapshot.exists) {
    conflict('The party payment id already exists.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The payment journal id already exists.');
  }

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The payment journal idempotency key already exists.');
  }

  const existingPartyLedgerSnapshot = await transaction.get(
    partyLedgerRef,
  );
  if (existingPartyLedgerSnapshot.exists) {
    conflict('A party ledger entry for this payment already exists.');
  }

  const partySnapshot = await transaction.get(partyRef);
  assertParty(
    partySnapshot,
    command.storeId,
    command.payment.partyId,
    command.payment.partyType,
  );

  const accountIds = [
    command.accounts.settlementAccountId,
    command.accounts.partyAccountId,
  ];
  const accountRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('accounts').doc(accountId),
    ]),
  );
  const accountSnapshots = new Map();
  for (const [accountId, accountRef] of accountRefs) {
    accountSnapshots.set(
      accountId,
      await transaction.get(accountRef),
    );
  }

  const balanceRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('account_balances').doc(accountId),
    ]),
  );
  const balanceSnapshots = new Map();
  for (const [accountId, balanceRef] of balanceRefs) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(balanceRef),
    );
  }

  const partyBalanceSnapshot = await transaction.get(partyBalanceRef);

  assertAccount(
    accountSnapshots.get(command.accounts.settlementAccountId),
    command.accounts.settlementAccountId,
    command.storeId,
    command.payment.currency,
    'asset',
    paymentAccountControlType(command.payment.paymentMethod),
  );
  const isCustomerPayment = command.payment.partyType === 'customer';
  assertAccount(
    accountSnapshots.get(command.accounts.partyAccountId),
    command.accounts.partyAccountId,
    command.storeId,
    command.payment.currency,
    isCustomerPayment ? 'asset' : 'liability',
    isCustomerPayment ? 'customerReceivable' : 'supplierPayable',
  );

  const amount = command.payment.amountMinorUnits;
  const accountDeltas = new Map();
  if (isCustomerPayment) {
    addDelta(
      accountDeltas,
      command.accounts.settlementAccountId,
      amount,
      0,
    );
    addDelta(
      accountDeltas,
      command.accounts.partyAccountId,
      0,
      amount,
    );
  } else {
    addDelta(
      accountDeltas,
      command.accounts.partyAccountId,
      amount,
      0,
    );
    addDelta(
      accountDeltas,
      command.accounts.settlementAccountId,
      0,
      amount,
    );
  }

  const journalLines = [
    {
      id: command.payment.id + '-settlement',
      storeId: command.storeId,
      accountId: command.accounts.settlementAccountId,
      description: command.payment.paymentMethod,
      lineNumber: 1,
      debitMinorUnits: isCustomerPayment ? amount : 0,
      creditMinorUnits: isCustomerPayment ? 0 : amount,
    },
    {
      id: command.payment.id + '-party',
      storeId: command.storeId,
      accountId: command.accounts.partyAccountId,
      description: command.payment.partyType === 'customer'
        ? 'Customer receivable settlement'
        : 'Supplier payable settlement',
      lineNumber: 2,
      debitMinorUnits: isCustomerPayment ? 0 : amount,
      creditMinorUnits: isCustomerPayment ? amount : 0,
    },
  ];

  const paymentData = {
    storeId: command.storeId,
    idempotencyKey: command.payment.idempotencyKey,
    postedAt: Timestamp.fromDate(command.payment.postedAt),
    partyType: command.payment.partyType,
    partyId: command.payment.partyId,
    paymentMethod: command.payment.paymentMethod,
    amountMinorUnits: amount,
    currency: command.payment.currency,
    description: command.payment.description,
    journalEntryId,
    status: 'posted',
    createdAt: FieldValue.serverTimestamp(),
  };
  transaction.set(paymentRef, paymentData);

  transaction.set(
    partyLedgerRef,
    {
      storeId: command.storeId,
      partyType: command.payment.partyType,
      partyId: command.payment.partyId,
      sourceType: command.payment.partyType === 'customer'
        ? 'customerReceipt'
        : 'supplierPayment',
      sourceId: command.payment.id,
      currency: command.payment.currency,
      debitMinorUnits: isCustomerPayment ? 0 : amount,
      creditMinorUnits: isCustomerPayment ? amount : 0,
      description: command.payment.description,
      postedAt: Timestamp.fromDate(command.payment.postedAt),
    },
  );

  const partyBalance = partyBalanceSnapshot.exists
    ? partyBalanceSnapshot.data()
    : {};
  const currentPartyDebit = storedInt(
    partyBalance.debitMinorUnits,
    0,
  );
  const currentPartyCredit = storedInt(
    partyBalance.creditMinorUnits,
    0,
  );
  const nextPartyDebit = currentPartyDebit +
    (isCustomerPayment ? 0 : amount);
  const nextPartyCredit = currentPartyCredit +
    (isCustomerPayment ? amount : 0);
  transaction.set(
    partyBalanceRef,
    {
      storeId: command.storeId,
      partyType: command.payment.partyType,
      partyId: command.payment.partyId,
      currency: command.payment.currency,
      debitMinorUnits: nextPartyDebit,
      creditMinorUnits: nextPartyCredit,
      balanceMinorUnits: nextPartyDebit - nextPartyCredit,
      updatedAt: FieldValue.serverTimestamp(),
    },
  );

  transaction.set(
    journalRef,
    {
      storeId: command.storeId,
      idempotencyKey: journalIdempotencyKey,
      sourceType: command.payment.partyType === 'customer'
        ? 'customerReceipt'
        : 'supplierPayment',
      description: command.payment.description,
      status: 'posted',
      currency: command.payment.currency,
      totalDebitMinorUnits: amount,
      totalCreditMinorUnits: amount,
      postedAt: Timestamp.fromDate(command.payment.postedAt),
    },
  );
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.payment.postedAt),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };
    const nextDebit = currentDebit + delta.debit;
    const nextCredit = currentCredit + delta.credit;

    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.payment.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    paymentIdempotencyRef,
    {
      storeId: command.storeId,
      paymentId: command.payment.id,
      idempotencyKey: command.payment.idempotencyKey,
      journalEntryId,
      createdAt: FieldValue.serverTimestamp(),
    },
  );
  transaction.set(
    journalIdempotencyRef,
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      idempotencyKey: journalIdempotencyKey,
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  return {
    status: 'posted',
    paymentId: command.payment.id,
    journalEntryId,
  };
}

function parsePurchaseCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const purchase = asObject(command.purchase, 'purchase');
  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );
  const lines = Array.isArray(purchase.lines) ? purchase.lines : [];

  if (lines.length === 0 || lines.length > MAX_LINES) {
    invalid('Purchase must contain between 1 and 100 lines.');
  }

  const paymentMethod = stringValue(
    purchase.paymentMethod,
    'purchase.paymentMethod',
  );
  if (!PURCHASE_PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported purchase payment method.');
  }

  const supplierId = optionalSafeId(purchase.supplierId, 'supplierId');
  if (paymentMethod === 'credit' && !supplierId) {
    invalid('A credit purchase requires a supplier.');
  }

  const currency = stringValue(purchase.currency, 'purchase.currency');
  const taxMinorUnits = nonNegativeInt(
    purchase.taxMinorUnits,
    'purchase.taxMinorUnits',
  );
  const postedAt = parseDate(purchase.postedAt, 'purchase.postedAt');
  const parsedLines = lines.map((rawLine, index) => {
    const line = asObject(rawLine, 'purchase.lines[' + index + ']');
    return {
      id: safeId(line.id, 'purchase line id'),
      productId: safeId(line.productId, 'product id'),
      description: stringValue(
        line.description,
        'purchase line description',
      ),
      quantityMilliUnits: positiveInt(
        line.quantityMilliUnits,
        'quantityMilliUnits',
      ),
      unitFactorToBaseMilliUnits: positiveInt(
        line.unitFactorToBaseMilliUnits,
        'unitFactorToBaseMilliUnits',
      ),
      unitCostMinorUnits: nonNegativeInt(
        line.unitCostMinorUnits,
        'unitCostMinorUnits',
      ),
      discountMinorUnits: nonNegativeInt(
        line.discountMinorUnits,
        'discountMinorUnits',
      ),
      unitId: optionalSafeId(line.unitId, 'unitId'),
      unitName: line.unitName == null
        ? null
        : stringValue(line.unitName, 'unitName'),
    };
  });

  const lineIds = new Set(parsedLines.map((line) => line.id));
  if (lineIds.size !== parsedLines.length) {
    invalid('Purchase line ids must be unique.');
  }

  const accounts = {
    settlementAccountId: optionalSafeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    inventoryAccountId: safeId(
      postingAccounts.inventoryAccountId,
      'inventoryAccountId',
    ),
    supplierPayableAccountId: optionalSafeId(
      postingAccounts.supplierPayableAccountId,
      'supplierPayableAccountId',
    ),
    inputTaxAccountId: optionalSafeId(
      postingAccounts.inputTaxAccountId,
      'inputTaxAccountId',
    ),
  };

  const paymentAccountId = paymentMethod === 'credit'
    ? accounts.supplierPayableAccountId
    : accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid(
      paymentMethod === 'credit'
        ? 'A supplier payable account is required for credit purchases.'
        : 'A settlement account is required for paid purchases.',
    );
  }
  if (taxMinorUnits > 0 && !accounts.inputTaxAccountId) {
    invalid('An input tax account is required when tax is present.');
  }

  const providedAccountIds = [
    accounts.settlementAccountId,
    accounts.inventoryAccountId,
    accounts.supplierPayableAccountId,
    accounts.inputTaxAccountId,
  ].filter(Boolean);
  if (new Set(providedAccountIds).size !== providedAccountIds.length) {
    invalid('Purchase posting accounts must be distinct.');
  }

  return {
    storeId,
    purchase: {
      id: safeId(purchase.id, 'purchase id'),
      idempotencyKey: safeId(
        purchase.idempotencyKey,
        'purchase idempotency key',
      ),
      postedAt,
      paymentMethod,
      supplierId,
      description: purchase.description == null
        ? null
        : stringValue(purchase.description, 'purchase.description'),
      currency,
      taxMinorUnits,
      lines: parsedLines,
    },
    accounts,
  };
}

async function postPurchaseInTransaction(
  transaction,
  userId,
  command,
  allowedRoles = POSTING_ROLES,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const purchaseRef = storeRef
    .collection('purchases')
    .doc(command.purchase.id);
  const purchaseIdempotencyRef = storeRef
    .collection('purchase_idempotency')
    .doc(command.purchase.idempotencyKey);
  const journalEntryId = command.purchase.id + '-journal';
  const journalIdempotencyKey = command.purchase.idempotencyKey +
    ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);

  const isCreditPurchase =
    command.purchase.paymentMethod === 'credit';
  const supplierLedgerId = isCreditPurchase
    ? command.purchase.id + '-supplier'
    : null;
  const supplierLedgerRef = isCreditPurchase
    ? storeRef.collection('party_ledger_entries').doc(supplierLedgerId)
    : null;
  const supplierBalanceId = isCreditPurchase
    ? 'supplier-' + command.purchase.supplierId
    : null;
  const supplierBalanceRef = isCreditPurchase
    ? storeRef.collection('party_balances').doc(supplierBalanceId)
    : null;
  const supplierRef = isCreditPurchase
    ? storeRef.collection('parties').doc(command.purchase.supplierId)
    : null;

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post purchases',
    allowedRoles,
  );

  const purchaseIdempotencySnapshot = await transaction.get(
    purchaseIdempotencyRef,
  );
  if (purchaseIdempotencySnapshot.exists) {
    const existingPurchaseId = purchaseIdempotencySnapshot.data().purchaseId;
    if (existingPurchaseId === command.purchase.id) {
      return {
        status: 'already_posted',
        purchaseId: command.purchase.id,
        journalEntryId,
      };
    }
    conflict('The purchase idempotency key is already assigned.');
  }

  const existingPurchaseSnapshot = await transaction.get(purchaseRef);
  if (existingPurchaseSnapshot.exists) {
    conflict('The purchase id already exists.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The purchase journal id already exists.');
  }

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The journal idempotency key already exists.');
  }

  let supplierSnapshot = null;
  let supplierLedgerSnapshot = null;
  let supplierBalanceSnapshot = null;
  if (isCreditPurchase) {
    supplierSnapshot = await transaction.get(supplierRef);
    assertParty(
      supplierSnapshot,
      command.storeId,
      command.purchase.supplierId,
      'supplier',
    );
    supplierLedgerSnapshot = await transaction.get(supplierLedgerRef);
    if (supplierLedgerSnapshot.exists) {
      conflict('A supplier ledger entry for this purchase already exists.');
    }
    supplierBalanceSnapshot = await transaction.get(supplierBalanceRef);
  }

  const productIds = [...new Set(
    command.purchase.lines.map((line) => line.productId),
  )];
  const productRefs = new Map(
    productIds.map((productId) => [
      productId,
      storeRef.collection('products').doc(productId),
    ]),
  );
  const productSnapshots = new Map();
  for (const [productId, productRef] of productRefs) {
    productSnapshots.set(
      productId,
      await transaction.get(productRef),
    );
  }

  const paymentAccountId = command.purchase.paymentMethod === 'credit'
    ? command.accounts.supplierPayableAccountId
    : command.accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid('The purchase payment account is required.');
  }

  const accountIds = [
    command.accounts.inventoryAccountId,
    paymentAccountId,
  ];
  if (command.purchase.taxMinorUnits > 0) {
    accountIds.push(command.accounts.inputTaxAccountId);
  }
  const accountRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('accounts').doc(accountId),
    ]),
  );
  const accountSnapshots = new Map();
  for (const [accountId, accountRef] of accountRefs) {
    accountSnapshots.set(
      accountId,
      await transaction.get(accountRef),
    );
  }

  const balanceRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('account_balances').doc(accountId),
    ]),
  );
  const balanceSnapshots = new Map();
  for (const [accountId, balanceRef] of balanceRefs) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(balanceRef),
    );
  }

  const movementRefs = command.purchase.lines.map((line) => ({
    line,
    movementId: command.purchase.id + '-inventory-' + line.id,
    movementKey: command.purchase.idempotencyKey +
      ':inventory:' + line.id,
    ref: storeRef.collection('inventory_movements').doc(
      command.purchase.id + '-inventory-' + line.id,
    ),
    idempotencyRef: storeRef.collection('inventory_idempotency').doc(
      command.purchase.idempotencyKey + ':inventory:' + line.id,
    ),
  }));
  const movementSnapshots = [];
  for (const movement of movementRefs) {
    movementSnapshots.push({
      movement,
      snapshot: await transaction.get(movement.ref),
      idempotencySnapshot: await transaction.get(
        movement.idempotencyRef,
      ),
    });
  }
  for (const item of movementSnapshots) {
    if (item.snapshot.exists || item.idempotencySnapshot.exists) {
      conflict('An inventory movement for this purchase already exists.');
    }
  }

  assertAccount(
    accountSnapshots.get(command.accounts.inventoryAccountId),
    command.accounts.inventoryAccountId,
    command.storeId,
    command.purchase.currency,
    'asset',
    'inventory',
  );
  if (command.purchase.paymentMethod === 'credit') {
    assertAccount(
      accountSnapshots.get(command.accounts.supplierPayableAccountId),
      command.accounts.supplierPayableAccountId,
      command.storeId,
      command.purchase.currency,
      'liability',
      'supplierPayable',
    );
  } else {
    assertAccount(
      accountSnapshots.get(command.accounts.settlementAccountId),
      command.accounts.settlementAccountId,
      command.storeId,
      command.purchase.currency,
      'asset',
      paymentAccountControlType(command.purchase.paymentMethod),
    );
  }
  if (command.purchase.taxMinorUnits > 0) {
    assertAccount(
      accountSnapshots.get(command.accounts.inputTaxAccountId),
      command.accounts.inputTaxAccountId,
      command.storeId,
      command.purchase.currency,
      'asset',
      'inputTax',
    );
  }

  const receivedByProduct = new Map();
  const storedLines = [];
  let subtotalMinorUnits = 0;

  for (const line of command.purchase.lines) {
    const productSnapshot = productSnapshots.get(line.productId);
    if (!productSnapshot || !productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId) {
      deny('Product belongs to another store.');
    }
    if (product.isActive === false) {
      invalid('Inactive products cannot receive stock.');
    }
    if (product.isService === true) {
      invalid('Services cannot receive inventory purchases.');
    }

    const productCurrency = product.currency || 'ILS';
    if (productCurrency !== command.purchase.currency) {
      invalid('Product currency does not match the purchase currency.');
    }

    const expectedFactor = expectedUnitFactor(product, line.unitId);
    if (expectedFactor !== line.unitFactorToBaseMilliUnits) {
      invalid('Product unit changed. Refresh the purchase and try again.');
    }

    const baseQuantityMilliUnits = multiplyAndRound(
      line.quantityMilliUnits,
      line.unitFactorToBaseMilliUnits,
    );
    if (baseQuantityMilliUnits <= 0) {
      invalid('Purchase line base quantity must be positive.');
    }

    const grossMinorUnits = multiplyAndRound(
      line.unitCostMinorUnits,
      baseQuantityMilliUnits,
    );
    if (line.discountMinorUnits > grossMinorUnits) {
      invalid('Purchase line discount exceeds its gross total.');
    }
    const totalMinorUnits = grossMinorUnits - line.discountMinorUnits;
    subtotalMinorUnits += totalMinorUnits;

    const previous = receivedByProduct.get(line.productId) || {
      quantity: 0,
      cost: 0,
    };
    receivedByProduct.set(line.productId, {
      quantity: previous.quantity + baseQuantityMilliUnits,
      cost: previous.cost + totalMinorUnits,
    });

    storedLines.push({
      storeId: command.storeId,
      id: line.id,
      productId: line.productId,
      description: line.description,
      quantityMilliUnits: line.quantityMilliUnits,
      unitFactorToBaseMilliUnits: line.unitFactorToBaseMilliUnits,
      baseQuantityMilliUnits,
      unitCostMinorUnits: line.unitCostMinorUnits,
      discountMinorUnits: line.discountMinorUnits,
      grossTotalMinorUnits: grossMinorUnits,
      totalMinorUnits,
      unitId: line.unitId,
      unitName: line.unitName,
    });
  }

  if (subtotalMinorUnits <= 0) {
    invalid('A purchase total must be greater than zero.');
  }

  const grandTotalMinorUnits =
    subtotalMinorUnits + command.purchase.taxMinorUnits;
  if (grandTotalMinorUnits <= 0) {
    invalid('A purchase total must be greater than zero.');
  }

  const nextProducts = new Map();
  for (const [productId, receipt] of receivedByProduct) {
    const product = productSnapshots.get(productId).data();
    const currentQuantity = storedInt(
      product.quantityOnHandMilliUnits,
      0,
    );
    const currentUnitCost = storedInt(
      product.purchasePriceMinorUnits,
      0,
    );
    const currentTotalCost = currentQuantity > 0
      ? multiplyAndRound(currentUnitCost, currentQuantity)
      : 0;
    const nextQuantity = currentQuantity + receipt.quantity;
    const nextTotalCost = currentTotalCost + receipt.cost;
    const nextUnitCost = divideAndRound(
      nextTotalCost,
      nextQuantity,
    );
    nextProducts.set(productId, {
      quantity: nextQuantity,
      unitCost: nextUnitCost,
      inventoryValue: nextTotalCost,
    });
  }

  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    command.accounts.inventoryAccountId,
    subtotalMinorUnits,
    0,
  );
  if (command.purchase.taxMinorUnits > 0) {
    addDelta(
      accountDeltas,
      command.accounts.inputTaxAccountId,
      command.purchase.taxMinorUnits,
      0,
    );
  }
  addDelta(
    accountDeltas,
    paymentAccountId,
    0,
    grandTotalMinorUnits,
  );

  const totalDebitMinorUnits = subtotalMinorUnits +
    command.purchase.taxMinorUnits;
  const totalCreditMinorUnits = grandTotalMinorUnits;
  if (totalDebitMinorUnits !== totalCreditMinorUnits) {
    throw new HttpsError(
      'internal',
      'The generated purchase journal is not balanced.',
    );
  }

  const journalLines = [
    {
      id: command.purchase.id + '-inventory',
      storeId: command.storeId,
      accountId: command.accounts.inventoryAccountId,
      description: 'Inventory receipt',
      lineNumber: 1,
      debitMinorUnits: subtotalMinorUnits,
      creditMinorUnits: 0,
    },
  ];
  if (command.purchase.taxMinorUnits > 0) {
    journalLines.push({
      id: command.purchase.id + '-input-tax',
      storeId: command.storeId,
      accountId: command.accounts.inputTaxAccountId,
      description: 'Input tax',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: command.purchase.taxMinorUnits,
      creditMinorUnits: 0,
    });
  }
  journalLines.push({
    id: command.purchase.id + '-settlement',
    storeId: command.storeId,
    accountId: paymentAccountId,
    description: command.purchase.paymentMethod,
    lineNumber: journalLines.length + 1,
    debitMinorUnits: 0,
    creditMinorUnits: grandTotalMinorUnits,
  });

  const purchaseData = {
    storeId: command.storeId,
    idempotencyKey: command.purchase.idempotencyKey,
    postedAt: Timestamp.fromDate(command.purchase.postedAt),
    paymentMethod: command.purchase.paymentMethod,
    supplierId: command.purchase.supplierId,
    description: command.purchase.description,
    currency: command.purchase.currency,
    subtotalMinorUnits,
    taxMinorUnits: command.purchase.taxMinorUnits,
    totalMinorUnits: grandTotalMinorUnits,
    journalEntryId,
    status: 'posted',
    createdAt: FieldValue.serverTimestamp(),
  };
  transaction.set(purchaseRef, purchaseData);

  for (const line of storedLines) {
    transaction.set(
      purchaseRef.collection('lines').doc(line.id),
      line,
    );
  }

  for (const [productId, nextProduct] of nextProducts) {
    transaction.update(
      productRefs.get(productId),
      {
        quantityOnHandMilliUnits: nextProduct.quantity,
        purchasePriceMinorUnits: nextProduct.unitCost,
        inventoryValueMinorUnits: nextProduct.inventoryValue,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const item of movementRefs) {
    const line = storedLines.find(
      (storedLine) => storedLine.id === item.line.id,
    );
    const movementData = {
      storeId: command.storeId,
      productId: line.productId,
      type: 'purchaseReceipt',
      quantityDeltaMilliUnits: line.baseQuantityMilliUnits,
      unitCostMinorUnits: line.unitCostMinorUnits,
      totalCostMinorUnits: line.totalMinorUnits,
      currency: command.purchase.currency,
      idempotencyKey: item.movementKey,
      sourceType: 'purchase',
      sourceId: command.purchase.id,
      occurredAt: Timestamp.fromDate(command.purchase.postedAt),
    };
    transaction.set(item.ref, movementData);
    transaction.set(
      item.idempotencyRef,
      {
        storeId: command.storeId,
        movementId: item.movementId,
        idempotencyKey: item.movementKey,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    journalRef,
    {
      storeId: command.storeId,
      idempotencyKey: journalIdempotencyKey,
      sourceType: 'purchase',
      description: command.purchase.description,
      status: 'posted',
      currency: command.purchase.currency,
      totalDebitMinorUnits,
      totalCreditMinorUnits,
      postedAt: Timestamp.fromDate(command.purchase.postedAt),
    },
  );
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.purchase.postedAt),
      },
    );
  }

  if (isCreditPurchase) {
    const balance = supplierBalanceSnapshot.exists
      ? supplierBalanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const nextDebit = currentDebit;
    const nextCredit = currentCredit + grandTotalMinorUnits;

    transaction.set(
      supplierLedgerRef,
      {
        storeId: command.storeId,
        partyType: 'supplier',
        partyId: command.purchase.supplierId,
        sourceType: 'purchase',
        sourceId: command.purchase.id,
        currency: command.purchase.currency,
        debitMinorUnits: 0,
        creditMinorUnits: grandTotalMinorUnits,
        description: command.purchase.description,
        postedAt: Timestamp.fromDate(command.purchase.postedAt),
      },
    );
    transaction.set(
      supplierBalanceRef,
      {
        storeId: command.storeId,
        partyType: 'supplier',
        partyId: command.purchase.supplierId,
        currency: command.purchase.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };
    const nextDebit = currentDebit + delta.debit;
    const nextCredit = currentCredit + delta.credit;

    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.purchase.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    purchaseIdempotencyRef,
    {
      storeId: command.storeId,
      purchaseId: command.purchase.id,
      idempotencyKey: command.purchase.idempotencyKey,
      journalEntryId,
      createdAt: FieldValue.serverTimestamp(),
    },
  );
  transaction.set(
    journalIdempotencyRef,
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      idempotencyKey: journalIdempotencyKey,
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  return {
    status: 'posted',
    purchaseId: command.purchase.id,
    journalEntryId,
  };
}


function parsePurchaseOrderCreateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const rawOrder = asObject(command.order, 'order');
  const rawLines = Array.isArray(rawOrder.lines) ? rawOrder.lines : [];
  if (rawLines.length === 0 || rawLines.length > MAX_LINES) {
    invalid('A purchase order must contain between 1 and 100 lines.');
  }

  const currency = stringValue(rawOrder.currency, 'order.currency');
  const lines = rawLines.map((rawLine, index) => {
    const line = asObject(rawLine, 'order.lines[' + index + ']');
    return {
      id: safeId(line.id, 'order line id'),
      productId: safeId(line.productId, 'order product id'),
      productName: stringValue(line.productName, 'order product name'),
      quantityMilliUnits: positiveInt(
        line.quantityMilliUnits,
        'order quantityMilliUnits',
      ),
      unitFactorToBaseMilliUnits: positiveInt(
        line.unitFactorToBaseMilliUnits,
        'order unitFactorToBaseMilliUnits',
      ),
      unitCostMinorUnits: nonNegativeInt(
        line.unitCostMinorUnits,
        'order unitCostMinorUnits',
      ),
      currency: line.currency == null
        ? currency
        : stringValue(line.currency, 'order line currency'),
      unitId: optionalSafeId(line.unitId, 'order unitId'),
      unitName: line.unitName == null
        ? null
        : stringValue(line.unitName, 'order unitName'),
    };
  });

  const lineIds = new Set(lines.map((line) => line.id));
  if (lineIds.size !== lines.length) {
    invalid('Purchase order line ids must be unique.');
  }

  return {
    storeId,
    order: {
      id: safeId(rawOrder.id, 'order id'),
      orderNumber: safeId(rawOrder.orderNumber, 'order number'),
      supplierId: safeId(rawOrder.supplierId, 'supplier id'),
      supplierName: stringValue(rawOrder.supplierName, 'supplier name'),
      currency,
      orderedAt: parseDate(rawOrder.orderedAt, 'order.orderedAt'),
      notes: optionalText(rawOrder.notes, 'order.notes'),
      lines,
    },
  };
}

function parsePurchaseOrderCancelCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  return {
    storeId: safeId(command.storeId, 'storeId'),
    orderId: safeId(command.orderId, 'orderId'),
  };
}

function parsePurchaseOrderReceiveCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const paymentMethod = stringValue(
    command.paymentMethod,
    'paymentMethod',
  );
  if (!PURCHASE_PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported purchase payment method.');
  }

  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );
  const accounts = {
    settlementAccountId: optionalSafeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    inventoryAccountId: safeId(
      postingAccounts.inventoryAccountId,
      'inventoryAccountId',
    ),
    supplierPayableAccountId: optionalSafeId(
      postingAccounts.supplierPayableAccountId,
      'supplierPayableAccountId',
    ),
    inputTaxAccountId: optionalSafeId(
      postingAccounts.inputTaxAccountId,
      'inputTaxAccountId',
    ),
  };
  const paymentAccountId = paymentMethod === 'credit'
    ? accounts.supplierPayableAccountId
    : accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid('The purchase payment account is required.');
  }

  const taxMinorUnits = nonNegativeInt(
    command.taxMinorUnits,
    'taxMinorUnits',
  );
  if (taxMinorUnits > 0 && !accounts.inputTaxAccountId) {
    invalid('An input tax account is required when tax is present.');
  }

  return {
    storeId,
    orderId: safeId(command.orderId, 'orderId'),
    receiptId: safeId(command.receiptId, 'receiptId'),
    idempotencyKey: safeId(command.idempotencyKey, 'idempotencyKey'),
    postedAt: parseDate(command.postedAt, 'postedAt'),
    paymentMethod,
    currency: stringValue(command.currency, 'currency'),
    taxMinorUnits,
    accounts,
  };
}

async function createPurchaseOrderInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const orderRef = storeRef
    .collection('purchase_orders')
    .doc(command.order.id);
  const supplierRef = storeRef
    .collection('parties')
    .doc(command.order.supplierId);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'create purchase orders',
    PURCHASE_ORDER_ROLES,
  );

  const existingOrderSnapshot = await transaction.get(orderRef);
  if (existingOrderSnapshot.exists) {
    conflict('The purchase order id already exists.');
  }

  const supplierSnapshot = await transaction.get(supplierRef);
  if (!supplierSnapshot.exists) {
    invalid('Supplier was not found.');
  }
  const supplier = supplierSnapshot.data();
  if (supplier.storeId !== command.storeId) {
    deny('Supplier belongs to another store.');
  }
  if (supplier.partyType !== 'supplier') {
    invalid('The selected party is not a supplier.');
  }
  if (supplier.isActive === false) {
    invalid('Inactive suppliers cannot receive purchase orders.');
  }

  const productIds = [...new Set(
    command.order.lines.map((line) => line.productId),
  )];
  const productRefs = new Map(
    productIds.map((productId) => [
      productId,
      storeRef.collection('products').doc(productId),
    ]),
  );
  const productSnapshots = new Map();
  for (const [productId, productRef] of productRefs) {
    productSnapshots.set(productId, await transaction.get(productRef));
  }

  let totalMinorUnits = 0;
  const storedLines = [];
  for (const line of command.order.lines) {
    const productSnapshot = productSnapshots.get(line.productId);
    if (!productSnapshot || !productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId) {
      deny('Product belongs to another store.');
    }
    if (product.isActive === false) {
      invalid('Inactive products cannot be ordered.');
    }
    if (product.isService === true) {
      invalid('Services cannot be ordered as stock.');
    }
    const productCurrency = product.currency || 'ILS';
    if (productCurrency !== command.order.currency ||
        line.currency !== command.order.currency) {
      invalid('Product currency does not match the purchase order.');
    }
    const expectedFactor = expectedUnitFactor(product, line.unitId);
    if (expectedFactor !== line.unitFactorToBaseMilliUnits) {
      invalid('Product unit changed. Refresh the purchase order and try again.');
    }

    const baseQuantityMilliUnits = multiplyAndRound(
      line.quantityMilliUnits,
      line.unitFactorToBaseMilliUnits,
    );
    const lineTotalMinorUnits = multiplyAndRound(
      line.unitCostMinorUnits,
      baseQuantityMilliUnits,
    );
    totalMinorUnits += lineTotalMinorUnits;
    storedLines.push({
      id: line.id,
      productId: line.productId,
      productName: line.productName,
      quantityMilliUnits: line.quantityMilliUnits,
      unitFactorToBaseMilliUnits: line.unitFactorToBaseMilliUnits,
      unitCostMinorUnits: line.unitCostMinorUnits,
      currency: line.currency,
      unitId: line.unitId,
      unitName: line.unitName,
      receivedQuantityMilliUnits: 0,
      totalMinorUnits: lineTotalMinorUnits,
    });
  }
  if (totalMinorUnits <= 0) {
    invalid('A purchase order total must be greater than zero.');
  }

  transaction.set(orderRef, {
    storeId: command.storeId,
    orderNumber: command.order.orderNumber,
    supplierId: command.order.supplierId,
    supplierName: supplier.name || command.order.supplierName,
    currency: command.order.currency,
    orderedAt: Timestamp.fromDate(command.order.orderedAt),
    status: 'pending',
    notes: command.order.notes,
    totalMinorUnits,
    lines: storedLines,
    createdBy: userId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return {
    status: 'created',
    orderId: command.order.id,
  };
}

async function cancelPurchaseOrderInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const orderRef = storeRef
    .collection('purchase_orders')
    .doc(command.orderId);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'cancel purchase orders',
    PURCHASE_ORDER_ROLES,
  );
  const orderSnapshot = await transaction.get(orderRef);
  if (!orderSnapshot.exists) {
    invalid('Purchase order was not found.');
  }
  const order = orderSnapshot.data();
  if (order.storeId !== command.storeId) {
    deny('Purchase order belongs to another store.');
  }
  if (order.status === 'cancelled') {
    return {
      status: 'already_cancelled',
      orderId: command.orderId,
    };
  }
  if (order.status !== 'pending') {
    conflict('Only pending purchase orders can be cancelled.');
  }

  transaction.update(orderRef, {
    status: 'cancelled',
    cancelledAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    status: 'cancelled',
    orderId: command.orderId,
  };
}

async function receivePurchaseOrderInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const orderRef = storeRef
    .collection('purchase_orders')
    .doc(command.orderId);
  const receiptIdempotencyRef = storeRef
    .collection('purchase_order_receipt_idempotency')
    .doc(command.idempotencyKey);

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'receive purchase orders',
    PURCHASE_ORDER_ROLES,
  );

  const idempotencySnapshot = await transaction.get(receiptIdempotencyRef);
  if (idempotencySnapshot.exists) {
    const previous = idempotencySnapshot.data();
    if (previous.orderId === command.orderId) {
      return {
        status: 'already_received',
        orderId: command.orderId,
        purchaseId: previous.purchaseId,
        journalEntryId: previous.journalEntryId,
      };
    }
    conflict('The purchase order receipt key is already assigned.');
  }

  const orderSnapshot = await transaction.get(orderRef);
  if (!orderSnapshot.exists) {
    invalid('Purchase order was not found.');
  }
  const order = orderSnapshot.data();
  if (order.storeId !== command.storeId) {
    deny('Purchase order belongs to another store.');
  }
  if (order.status === 'completed' && order.receiptId === command.receiptId) {
    return {
      status: 'already_received',
      orderId: command.orderId,
      purchaseId: command.receiptId,
      journalEntryId: order.journalEntryId || '',
    };
  }
  if (order.status !== 'pending') {
    conflict('Only pending purchase orders can be received.');
  }
  if (command.currency !== order.currency) {
    invalid('Receipt currency does not match the purchase order.');
  }

  const rawLines = Array.isArray(order.lines) ? order.lines : [];
  if (rawLines.length === 0 || rawLines.length > MAX_LINES) {
    invalid('The purchase order has no receivable lines.');
  }
  const purchaseLines = rawLines.map((rawLine, index) => {
    const line = asObject(rawLine, 'stored order line ' + index);
    const receivedQuantity = storedInt(
      line.receivedQuantityMilliUnits,
      0,
    );
    if (receivedQuantity !== 0) {
      invalid('Partial purchase order receipts are not supported yet.');
    }
    return {
      id: safeId(line.id, 'stored order line id'),
      productId: safeId(line.productId, 'stored order product id'),
      description: stringValue(line.productName, 'stored product name'),
      quantityMilliUnits: positiveInt(
        line.quantityMilliUnits,
        'stored order quantityMilliUnits',
      ),
      unitFactorToBaseMilliUnits: positiveInt(
        line.unitFactorToBaseMilliUnits,
        'stored order unitFactorToBaseMilliUnits',
      ),
      unitCostMinorUnits: nonNegativeInt(
        line.unitCostMinorUnits,
        'stored order unitCostMinorUnits',
      ),
      discountMinorUnits: 0,
      unitId: optionalSafeId(line.unitId, 'stored order unitId'),
      unitName: line.unitName == null
        ? null
        : stringValue(line.unitName, 'stored order unitName'),
    };
  });

  const purchaseCommand = {
    storeId: command.storeId,
    purchase: {
      id: command.receiptId,
      idempotencyKey: command.idempotencyKey,
      postedAt: command.postedAt,
      paymentMethod: command.paymentMethod,
      supplierId: safeId(order.supplierId, 'order supplier id'),
      description: 'Receipt for purchase order ' + order.orderNumber,
      currency: command.currency,
      taxMinorUnits: command.taxMinorUnits,
      lines: purchaseLines,
    },
    accounts: command.accounts,
  };
  const result = await postPurchaseInTransaction(
    transaction,
    userId,
    purchaseCommand,
    PURCHASE_ORDER_ROLES,
  );

  const completedLines = rawLines.map((rawLine) => ({
    ...rawLine,
    receivedQuantityMilliUnits: rawLine.quantityMilliUnits,
  }));
  transaction.update(orderRef, {
    status: 'completed',
    receiptId: command.receiptId,
    journalEntryId: result.journalEntryId,
    completedAt: Timestamp.fromDate(command.postedAt),
    lines: completedLines,
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(receiptIdempotencyRef, {
    storeId: command.storeId,
    orderId: command.orderId,
    receiptId: command.receiptId,
    idempotencyKey: command.idempotencyKey,
    purchaseId: result.purchaseId,
    journalEntryId: result.journalEntryId,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: result.status === 'already_posted' ? 'already_received' : 'received',
    orderId: command.orderId,
    purchaseId: result.purchaseId,
    journalEntryId: result.journalEntryId,
  };
}

function parseCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const sale = asObject(command.sale, 'sale');
  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );
  const lines = Array.isArray(sale.lines) ? sale.lines : [];

  if (lines.length === 0 || lines.length > MAX_LINES) {
    invalid('Sale must contain between 1 and 100 lines.');
  }

  const paymentMethod = stringValue(
    sale.paymentMethod,
    'sale.paymentMethod',
  );
  if (!PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported sale payment method.');
  }

  const customerId = optionalSafeId(sale.customerId, 'customerId');
  if (paymentMethod === 'credit' && !customerId) {
    invalid('A credit sale requires a customer.');
  }

  const currency = stringValue(sale.currency, 'sale.currency');
  const taxMinorUnits = nonNegativeInt(
    sale.taxMinorUnits,
    'sale.taxMinorUnits',
  );
  const postedAt = parseDate(sale.postedAt, 'sale.postedAt');
  const parsedLines = lines.map((rawLine, index) => {
    const line = asObject(rawLine, 'sale.lines[' + index + ']');
    const id = safeId(line.id, 'sale line id');
    const productId = safeId(line.productId, 'product id');
    const unitId = optionalSafeId(line.unitId, 'unitId');
    const unitName = line.unitName == null
      ? null
      : stringValue(line.unitName, 'unitName');

    return {
      id,
      productId,
      description: stringValue(
        line.description,
        'sale line description',
      ),
      quantityMilliUnits: positiveInt(
        line.quantityMilliUnits,
        'quantityMilliUnits',
      ),
      unitFactorToBaseMilliUnits: positiveInt(
        line.unitFactorToBaseMilliUnits,
        'unitFactorToBaseMilliUnits',
      ),
      unitPriceMinorUnits: nonNegativeInt(
        line.unitPriceMinorUnits,
        'unitPriceMinorUnits',
      ),
      unitCostMinorUnits: nonNegativeInt(
        line.unitCostMinorUnits,
        'unitCostMinorUnits',
      ),
      discountMinorUnits: nonNegativeInt(
        line.discountMinorUnits,
        'discountMinorUnits',
      ),
      unitId,
      unitName,
      isService: line.isService === true,
    };
  });

  const lineIds = new Set(parsedLines.map((line) => line.id));
  if (lineIds.size !== parsedLines.length) {
    invalid('Sale line ids must be unique.');
  }

  const accounts = {
    settlementAccountId: optionalSafeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    customerReceivableAccountId: optionalSafeId(
      postingAccounts.customerReceivableAccountId,
      'customerReceivableAccountId',
    ),
    salesAccountId: safeId(
      postingAccounts.salesAccountId,
      'salesAccountId',
    ),
    inventoryAccountId: safeId(
      postingAccounts.inventoryAccountId,
      'inventoryAccountId',
    ),
    costOfSalesAccountId: safeId(
      postingAccounts.costOfSalesAccountId,
      'costOfSalesAccountId',
    ),
    taxAccountId: optionalSafeId(
      postingAccounts.taxAccountId,
      'taxAccountId',
    ),
  };

  const paymentAccountId = paymentMethod === 'credit'
    ? accounts.customerReceivableAccountId
    : accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid(
      paymentMethod === 'credit'
        ? 'A customer receivable account is required for credit sales.'
        : 'A settlement account is required for paid sales.',
    );
  }

  const providedAccountIds = [
    accounts.settlementAccountId,
    accounts.customerReceivableAccountId,
    accounts.salesAccountId,
    accounts.inventoryAccountId,
    accounts.costOfSalesAccountId,
    accounts.taxAccountId,
  ].filter(Boolean);
  if (new Set(providedAccountIds).size !== providedAccountIds.length) {
    invalid('Sale posting accounts must be distinct.');
  }

  return {
    storeId,
    sale: {
      id: safeId(sale.id, 'sale id'),
      idempotencyKey: safeId(
        sale.idempotencyKey,
        'sale idempotency key',
      ),
      postedAt,
      paymentMethod,
      customerId,
      description: sale.description == null
        ? null
        : stringValue(sale.description, 'sale.description'),
      currency,
      taxMinorUnits,
      lines: parsedLines,
    },
    accounts,
  };
}

async function postSaleInTransaction(
  transaction,
  userId,
  command,
  allowedRoles = POSTING_ROLES,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const saleRef = storeRef.collection('sales').doc(command.sale.id);
  const saleIdempotencyRef = storeRef
    .collection('sale_idempotency')
    .doc(command.sale.idempotencyKey);
  const journalEntryId = command.sale.id + '-journal';
  const journalIdempotencyKey = command.sale.idempotencyKey + ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);

  const isCreditSale = command.sale.paymentMethod === 'credit';
  const customerLedgerId = isCreditSale
    ? command.sale.id + '-customer'
    : null;
  const customerLedgerRef = isCreditSale
    ? storeRef.collection('party_ledger_entries').doc(customerLedgerId)
    : null;
  const customerBalanceId = isCreditSale
    ? 'customer-' + command.sale.customerId
    : null;
  const customerBalanceRef = isCreditSale
    ? storeRef.collection('party_balances').doc(customerBalanceId)
    : null;
  const customerRef = isCreditSale
    ? storeRef.collection('parties').doc(command.sale.customerId)
    : null;

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post sales',
    allowedRoles,
  );

  const saleIdempotencySnapshot = await transaction.get(
    saleIdempotencyRef,
  );
  if (saleIdempotencySnapshot.exists) {
    const existingSaleId = saleIdempotencySnapshot.data().saleId;
    if (existingSaleId === command.sale.id) {
      return {
        status: 'already_posted',
        saleId: command.sale.id,
        journalEntryId,
      };
    }
    conflict('The sale idempotency key is already assigned.');
  }

  const existingSaleSnapshot = await transaction.get(saleRef);
  if (existingSaleSnapshot.exists) {
    conflict('The sale id already exists.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The sale journal id already exists.');
  }

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The journal idempotency key already exists.');
  }

  let customerSnapshot = null;
  let customerLedgerSnapshot = null;
  let customerBalanceSnapshot = null;
  if (isCreditSale) {
    customerSnapshot = await transaction.get(customerRef);
    assertParty(
      customerSnapshot,
      command.storeId,
      command.sale.customerId,
      'customer',
    );
    customerLedgerSnapshot = await transaction.get(customerLedgerRef);
    if (customerLedgerSnapshot.exists) {
      conflict('A customer ledger entry for this sale already exists.');
    }
    customerBalanceSnapshot = await transaction.get(customerBalanceRef);
  }

  const productIds = [...new Set(
    command.sale.lines.map((line) => line.productId),
  )];
  const productRefs = new Map(
    productIds.map((productId) => [
      productId,
      storeRef.collection('products').doc(productId),
    ]),
  );
  const productSnapshots = new Map();
  for (const [productId, productRef] of productRefs) {
    productSnapshots.set(
      productId,
      await transaction.get(productRef),
    );
  }

  const paymentAccountId = command.sale.paymentMethod === 'credit'
    ? command.accounts.customerReceivableAccountId
    : command.accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid('The sale payment account is required.');
  }

  const accountIds = [
    paymentAccountId,
    command.accounts.salesAccountId,
    command.accounts.inventoryAccountId,
    command.accounts.costOfSalesAccountId,
  ];
  if (command.accounts.taxAccountId) {
    accountIds.push(command.accounts.taxAccountId);
  }
  const accountRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('accounts').doc(accountId),
    ]),
  );
  const accountSnapshots = new Map();
  for (const [accountId, accountRef] of accountRefs) {
    accountSnapshots.set(
      accountId,
      await transaction.get(accountRef),
    );
  }

  const balanceRefs = new Map(
    accountIds.map((accountId) => [
      accountId,
      storeRef.collection('account_balances').doc(accountId),
    ]),
  );
  const balanceSnapshots = new Map();
  for (const [accountId, balanceRef] of balanceRefs) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(balanceRef),
    );
  }

  const movementRefs = command.sale.lines
    .filter((line) => !line.isService)
    .map((line) => ({
      line,
      movementId: command.sale.id + '-inventory-' + line.id,
      movementKey: command.sale.idempotencyKey +
        ':inventory:' + line.id,
      ref: storeRef.collection('inventory_movements').doc(
        command.sale.id + '-inventory-' + line.id,
      ),
      idempotencyRef: storeRef.collection('inventory_idempotency').doc(
        command.sale.idempotencyKey + ':inventory:' + line.id,
      ),
    }));
  const movementSnapshots = [];
  for (const movement of movementRefs) {
    movementSnapshots.push({
      movement,
      snapshot: await transaction.get(movement.ref),
      idempotencySnapshot: await transaction.get(
        movement.idempotencyRef,
      ),
    });
  }

  for (const item of movementSnapshots) {
    if (item.snapshot.exists || item.idempotencySnapshot.exists) {
      conflict('An inventory movement for this sale already exists.');
    }
  }

  if (command.sale.paymentMethod === 'credit') {
    assertAccount(
      accountSnapshots.get(command.accounts.customerReceivableAccountId),
      command.accounts.customerReceivableAccountId,
      command.storeId,
      command.sale.currency,
      'asset',
      'customerReceivable',
    );
  } else {
    assertAccount(
      accountSnapshots.get(command.accounts.settlementAccountId),
      command.accounts.settlementAccountId,
      command.storeId,
      command.sale.currency,
      'asset',
      paymentAccountControlType(command.sale.paymentMethod),
    );
  }
  assertAccount(
    accountSnapshots.get(command.accounts.salesAccountId),
    command.accounts.salesAccountId,
    command.storeId,
    command.sale.currency,
    'revenue',
  );
  assertAccount(
    accountSnapshots.get(command.accounts.inventoryAccountId),
    command.accounts.inventoryAccountId,
    command.storeId,
    command.sale.currency,
    'asset',
    'inventory',
  );
  assertAccount(
    accountSnapshots.get(command.accounts.costOfSalesAccountId),
    command.accounts.costOfSalesAccountId,
    command.storeId,
    command.sale.currency,
    'expense',
  );
  if (command.sale.taxMinorUnits > 0) {
    if (!command.accounts.taxAccountId) {
      invalid('A tax account is required when tax is present.');
    }
    assertAccount(
      accountSnapshots.get(command.accounts.taxAccountId),
      command.accounts.taxAccountId,
      command.storeId,
      command.sale.currency,
      'liability',
      'tax',
    );
  }

  const issuedByProduct = new Map();
  const storedLines = [];
  let subtotalMinorUnits = 0;
  let costTotalMinorUnits = 0;

  for (const line of command.sale.lines) {
    const productSnapshot = productSnapshots.get(line.productId);
    if (!productSnapshot || !productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId) {
      deny('Product belongs to another store.');
    }
    if (product.isActive === false) {
      invalid('Inactive products cannot be sold.');
    }
    if (product.isService !== line.isService) {
      invalid('Sale line service type does not match the product.');
    }

    const productCurrency = product.currency || 'ILS';
    if (productCurrency !== command.sale.currency) {
      invalid('Product currency does not match the sale currency.');
    }

    const purchasePriceMinorUnits = storedInt(
      product.purchasePriceMinorUnits,
      0,
    );
    if (line.isService) {
      if (line.unitCostMinorUnits !== 0) {
        invalid('A service line must have zero inventory cost.');
      }
    } else if (line.unitCostMinorUnits !== purchasePriceMinorUnits) {
      invalid('Product cost changed. Refresh the sale and try again.');
    }

    const expectedFactor = expectedUnitFactor(
      product,
      line.unitId,
    );
    if (expectedFactor !== line.unitFactorToBaseMilliUnits) {
      invalid('Product unit changed. Refresh the sale and try again.');
    }

    const grossMinorUnits = multiplyAndRound(
      line.unitPriceMinorUnits,
      line.quantityMilliUnits,
    );
    if (line.discountMinorUnits > grossMinorUnits) {
      invalid('Sale line discount exceeds its gross total.');
    }
    const totalMinorUnits = grossMinorUnits - line.discountMinorUnits;
    const baseQuantityMilliUnits = multiplyAndRound(
      line.quantityMilliUnits,
      line.unitFactorToBaseMilliUnits,
    );
    const costMinorUnits = line.isService
      ? 0
      : multiplyAndRound(
        line.unitCostMinorUnits,
        baseQuantityMilliUnits,
      );

    subtotalMinorUnits += totalMinorUnits;
    costTotalMinorUnits += costMinorUnits;

    if (!line.isService) {
      const previousIssued = issuedByProduct.get(line.productId) || {
        quantity: 0,
        cost: 0,
      };
      issuedByProduct.set(line.productId, {
        quantity: previousIssued.quantity + baseQuantityMilliUnits,
        cost: previousIssued.cost + costMinorUnits,
      });
    }

    storedLines.push({
      storeId: command.storeId,
      id: line.id,
      productId: line.productId,
      description: line.description,
      quantityMilliUnits: line.quantityMilliUnits,
      unitFactorToBaseMilliUnits: line.unitFactorToBaseMilliUnits,
      baseQuantityMilliUnits,
      unitPriceMinorUnits: line.unitPriceMinorUnits,
      unitCostMinorUnits: line.unitCostMinorUnits,
      discountMinorUnits: line.discountMinorUnits,
      grossTotalMinorUnits: grossMinorUnits,
      totalMinorUnits,
      costTotalMinorUnits: costMinorUnits,
      unitId: line.unitId,
      unitName: line.unitName,
      isService: line.isService,
    });
  }

  if (subtotalMinorUnits <= 0) {
    invalid('A sale total must be greater than zero.');
  }

  const grandTotalMinorUnits =
    subtotalMinorUnits + command.sale.taxMinorUnits;
  if (grandTotalMinorUnits <= 0) {
    invalid('A sale total must be greater than zero.');
  }

  const nextProducts = new Map();
  for (const [productId, issued] of issuedByProduct) {
    const productSnapshot = productSnapshots.get(productId);
    const product = productSnapshot.data();
    const currentQuantity = storedInt(
      product.quantityOnHandMilliUnits,
      0,
    );
    const currentUnitCost = storedInt(
      product.purchasePriceMinorUnits,
      0,
    );
    const currentInventoryValue = storedInt(
      product.inventoryValueMinorUnits,
      multiplyAndRound(currentUnitCost, currentQuantity),
    );
    const nextQuantity = currentQuantity - issued.quantity;
    if (nextQuantity < 0) {
      throw new HttpsError(
        'failed-precondition',
        'The sale would create negative stock for ' + productId + '.',
      );
    }
    const nextInventoryValue = currentInventoryValue - issued.cost;
    if (nextInventoryValue < 0) {
      throw new HttpsError(
        'failed-precondition',
        'The sale would create negative inventory value for ' +
          productId + '.',
      );
    }
    nextProducts.set(productId, {
      quantity: nextQuantity,
      inventoryValue: nextInventoryValue,
    });
  }

  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    paymentAccountId,
    grandTotalMinorUnits,
    0,
  );
  addDelta(
    accountDeltas,
    command.accounts.salesAccountId,
    0,
    subtotalMinorUnits,
  );
  if (command.sale.taxMinorUnits > 0) {
    addDelta(
      accountDeltas,
      command.accounts.taxAccountId,
      0,
      command.sale.taxMinorUnits,
    );
  }
  if (costTotalMinorUnits > 0) {
    addDelta(
      accountDeltas,
      command.accounts.costOfSalesAccountId,
      costTotalMinorUnits,
      0,
    );
    addDelta(
      accountDeltas,
      command.accounts.inventoryAccountId,
      0,
      costTotalMinorUnits,
    );
  }

  const totalDebitMinorUnits = grandTotalMinorUnits +
    costTotalMinorUnits;
  const totalCreditMinorUnits = subtotalMinorUnits +
    command.sale.taxMinorUnits +
    costTotalMinorUnits;
  if (totalDebitMinorUnits !== totalCreditMinorUnits) {
    throw new HttpsError(
      'internal',
      'The generated sale journal is not balanced.',
    );
  }

  const zero = 0;
  const journalLines = [
    {
      id: command.sale.id + '-settlement',
      storeId: command.storeId,
      accountId: paymentAccountId,
      description: command.sale.paymentMethod,
      lineNumber: 1,
      debitMinorUnits: grandTotalMinorUnits,
      creditMinorUnits: zero,
    },
    {
      id: command.sale.id + '-sales',
      storeId: command.storeId,
      accountId: command.accounts.salesAccountId,
      description: 'Sales revenue',
      lineNumber: 2,
      debitMinorUnits: zero,
      creditMinorUnits: subtotalMinorUnits,
    },
  ];
  if (command.sale.taxMinorUnits > 0) {
    journalLines.push({
      id: command.sale.id + '-tax',
      storeId: command.storeId,
      accountId: command.accounts.taxAccountId,
      description: 'Sales tax',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: zero,
      creditMinorUnits: command.sale.taxMinorUnits,
    });
  }
  if (costTotalMinorUnits > 0) {
    journalLines.push(
      {
        id: command.sale.id + '-cost',
        storeId: command.storeId,
        accountId: command.accounts.costOfSalesAccountId,
        description: 'Cost of sales',
        lineNumber: journalLines.length + 1,
        debitMinorUnits: costTotalMinorUnits,
        creditMinorUnits: zero,
      },
      {
        id: command.sale.id + '-inventory',
        storeId: command.storeId,
        accountId: command.accounts.inventoryAccountId,
        description: 'Inventory issue',
        lineNumber: journalLines.length + 1,
        debitMinorUnits: zero,
        creditMinorUnits: costTotalMinorUnits,
      },
    );
  }

  const saleData = {
    storeId: command.storeId,
    idempotencyKey: command.sale.idempotencyKey,
    postedAt: Timestamp.fromDate(command.sale.postedAt),
    paymentMethod: command.sale.paymentMethod,
    customerId: command.sale.customerId,
    description: command.sale.description,
    currency: command.sale.currency,
    subtotalMinorUnits,
    taxMinorUnits: command.sale.taxMinorUnits,
    totalMinorUnits: grandTotalMinorUnits,
    costTotalMinorUnits,
    journalEntryId,
    status: 'posted',
    createdAt: FieldValue.serverTimestamp(),
  };
  transaction.set(saleRef, saleData);

  for (const line of storedLines) {
    transaction.set(
      saleRef.collection('lines').doc(line.id),
      line,
    );
  }

  for (const [productId, nextProduct] of nextProducts) {
    transaction.update(
      productRefs.get(productId),
      {
        quantityOnHandMilliUnits: nextProduct.quantity,
        inventoryValueMinorUnits: nextProduct.inventoryValue,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const item of movementRefs) {
    const line = storedLines.find(
      (storedLine) => storedLine.id === item.line.id,
    );
    const movementData = {
      storeId: command.storeId,
      productId: line.productId,
      type: 'saleIssue',
      quantityDeltaMilliUnits: -line.baseQuantityMilliUnits,
      unitCostMinorUnits: line.unitCostMinorUnits,
      totalCostMinorUnits: line.costTotalMinorUnits,
      currency: command.sale.currency,
      idempotencyKey: item.movementKey,
      sourceType: 'sale',
      sourceId: command.sale.id,
      occurredAt: Timestamp.fromDate(command.sale.postedAt),
    };
    transaction.set(item.ref, movementData);
    transaction.set(
      item.idempotencyRef,
      {
        storeId: command.storeId,
        movementId: item.movementId,
        idempotencyKey: item.movementKey,
        createdAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    journalRef,
    {
      storeId: command.storeId,
      idempotencyKey: journalIdempotencyKey,
      sourceType: 'sale',
      description: command.sale.description,
      status: 'posted',
      currency: command.sale.currency,
      totalDebitMinorUnits,
      totalCreditMinorUnits,
      postedAt: Timestamp.fromDate(command.sale.postedAt),
    },
  );
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.sale.postedAt),
      },
    );
  }

  if (isCreditSale) {
    const balance = customerBalanceSnapshot.exists
      ? customerBalanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const nextDebit = currentDebit + grandTotalMinorUnits;
    const nextCredit = currentCredit;

    transaction.set(
      customerLedgerRef,
      {
        storeId: command.storeId,
        partyType: 'customer',
        partyId: command.sale.customerId,
        sourceType: 'sale',
        sourceId: command.sale.id,
        currency: command.sale.currency,
        debitMinorUnits: grandTotalMinorUnits,
        creditMinorUnits: 0,
        description: command.sale.description,
        postedAt: Timestamp.fromDate(command.sale.postedAt),
      },
    );
    transaction.set(
      customerBalanceRef,
      {
        storeId: command.storeId,
        partyType: 'customer',
        partyId: command.sale.customerId,
        currency: command.sale.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const balance = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const currentDebit = storedInt(balance.debitMinorUnits, 0);
    const currentCredit = storedInt(balance.creditMinorUnits, 0);
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };
    const nextDebit = currentDebit + delta.debit;
    const nextCredit = currentCredit + delta.credit;

    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.sale.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextDebit - nextCredit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(
    saleIdempotencyRef,
    {
      storeId: command.storeId,
      saleId: command.sale.id,
      idempotencyKey: command.sale.idempotencyKey,
      journalEntryId,
      createdAt: FieldValue.serverTimestamp(),
    },
  );
  transaction.set(
    journalIdempotencyRef,
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      idempotencyKey: journalIdempotencyKey,
      createdAt: FieldValue.serverTimestamp(),
    },
  );

  return {
    status: 'posted',
    saleId: command.sale.id,
    journalEntryId,
  };
}

function assertMembership(
  snapshot,
  storeId,
  action = 'post transactions',
  roles = POSTING_ROLES,
) {
  if (!snapshot.exists) {
    deny('The user is not a member of this store.');
  }
  const member = snapshot.data();
  if (member.storeId && member.storeId !== storeId) {
    deny('The membership belongs to another store.');
  }
  if (member.isActive !== true || !roles.has(member.role)) {
    deny('The user cannot ' + action + ' in this store.');
  }
}

function assertParty(
  snapshot,
  storeId,
  partyId,
  expectedType,
) {
  if (!snapshot || !snapshot.exists) {
    invalid(
      expectedType === 'customer'
        ? 'Customer was not found.'
        : 'Supplier was not found.',
    );
  }
  const party = snapshot.data();
  if (party.storeId !== storeId) {
    deny('Party belongs to another store.');
  }
  if (party.partyType !== expectedType) {
    invalid(
      expectedType === 'customer'
        ? 'The selected party is not a customer.'
        : 'The selected party is not a supplier.',
    );
  }
  if (party.isActive === false) {
    invalid(
      expectedType === 'customer'
        ? 'Inactive customers cannot be used.'
        : 'Inactive suppliers cannot be used.',
    );
  }
}

function assertAccount(
  snapshot,
  accountId,
  storeId,
  currency,
  expectedType,
  expectedControlType,
) {
  if (!snapshot || !snapshot.exists) {
    invalid('Account was not found: ' + accountId);
  }
  const account = snapshot.data();
  if (account.storeId !== storeId) {
    deny('Account belongs to another store.');
  }
  if (account.isActive === false || account.isHeader === true) {
    invalid('Account is not postable: ' + accountId);
  }
  if (account.currency !== currency) {
    invalid('Account currency does not match the transaction.');
  }
  if (account.type !== expectedType) {
    invalid('Account type is invalid: ' + accountId);
  }
  if (expectedControlType &&
      account.controlType !== expectedControlType) {
    invalid('Account control type is invalid: ' + accountId);
  }
}

function assertTransferAccount(
  snapshot,
  accountId,
  storeId,
  currency,
) {
  assertAccount(
    snapshot,
    accountId,
    storeId,
    currency,
    'asset',
  );
  const controlType = snapshot.data().controlType || 'none';
  if (![
    'cashBox',
    'bank',
    'cardReceivable',
    'none',
  ].includes(controlType)) {
    invalid('Account cannot be used in an internal transfer: ' + accountId);
  }
}

function paymentAccountControlType(paymentMethod) {
  switch (paymentMethod) {
    case 'cash':
      return 'cashBox';
    case 'bank':
      return 'bank';
    case 'card':
      return 'cardReceivable';
    case 'credit':
      return 'customerReceivable';
    default:
      invalid('Unsupported payment method.');
  }
}

function expectedUnitFactor(product, unitId) {
  if (!unitId) {
    return QUANTITY_SCALE;
  }
  const units = Array.isArray(product.units) ? product.units : [];
  const unit = units.find(
    (candidate) => candidate &&
      (candidate.id === unitId || candidate.unitId === unitId),
  );
  if (!unit) {
    invalid('Product unit was not found.');
  }
  return storedInt(unit.factorToBaseMilliUnits, 0);
}

function addDelta(deltas, accountId, debit, credit) {
  const previous = deltas.get(accountId) || {
    debit: 0,
    credit: 0,
  };
  deltas.set(accountId, {
    debit: previous.debit + debit,
    credit: previous.credit + credit,
  });
}

function multiplyAndRound(first, second) {
  const product = first * second;
  if (!Number.isSafeInteger(product)) {
    invalid('Sale amount is too large.');
  }
  return Math.floor((product + QUANTITY_SCALE / 2) / QUANTITY_SCALE);
}

function divideAndRound(numerator, denominator) {
  if (!Number.isSafeInteger(numerator) ||
      !Number.isSafeInteger(denominator) ||
      denominator <= 0) {
    invalid('Amount is too large.');
  }
  const scaled = numerator * QUANTITY_SCALE;
  if (!Number.isSafeInteger(scaled)) {
    invalid('Amount is too large.');
  }
  return Math.floor((scaled + denominator / 2) / denominator);
}

function storedInt(value, fallback) {
  return Number.isSafeInteger(value) ? value : fallback;
}

function asObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    invalid(label + ' must be an object.');
  }
  return value;
}

function stringValue(value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    invalid(label + ' is required.');
  }
  return value.trim();
}

function safeId(value, label) {
  const result = stringValue(value, label);
  if (result.includes('/')) {
    invalid(label + ' cannot contain a slash.');
  }
  return result;
}

function optionalSafeId(value, label) {
  if (value == null || value === '') {
    return null;
  }
  return safeId(value, label);
}

function optionalText(value, label) {
  if (value == null) {
    return '';
  }
  if (typeof value !== 'string') {
    invalid(label + ' must be a string.');
  }
  return value.trim();
}

function positiveInt(value, label) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    invalid(label + ' must be a positive integer.');
  }
  return value;
}

function nonNegativeInt(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    invalid(label + ' must be a non-negative integer.');
  }
  return value;
}

function parseDate(value, label) {
  if (typeof value !== 'string') {
    invalid(label + ' must be an ISO date string.');
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    invalid(label + ' is not a valid date.');
  }
  return date;
}

function invalid(message) {
  throw new HttpsError('invalid-argument', message);
}

function deny(message) {
  throw new HttpsError('permission-denied', message);
}

function conflict(message) {
  throw new HttpsError('already-exists', message);
}


function parseOfferCreateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const rawOffer = asObject(command.offer, 'offer');
  const offer = parseOfferPayload(rawOffer);
  const idempotencyKey = safeId(
    command.idempotencyKey || offer.id,
    'idempotencyKey',
  );
  return {storeId, offer, idempotencyKey};
}

function parseOfferUpdateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const offerId = safeId(command.offerId, 'offerId');
  const offer = parseOfferPayload(asObject(command.offer, 'offer'));
  if (offer.id !== offerId) {
    invalid('Offer id does not match the update target.');
  }
  return {storeId, offerId, offer};
}

function parseOfferPayload(rawOffer) {
  const rawLines = Array.isArray(rawOffer.lines) ? rawOffer.lines : [];
  if (rawLines.length === 0 || rawLines.length > MAX_LINES) {
    invalid('An offer must contain between 1 and 100 lines.');
  }

  const currency = stringValue(rawOffer.currency, 'offer.currency');
  const lines = rawLines.map((rawLine, index) => {
    const line = asObject(rawLine, 'offer.lines[' + index + ']');
    const priceType = stringValue(
      line.priceType || 'custom',
      'offer line priceType',
    );
    if (!OFFER_PRICE_TYPES.has(priceType)) {
      invalid('Unsupported offer price type.');
    }
    const unitId = optionalSafeId(line.unitId, 'offer unitId');
    return {
      id: safeId(line.id, 'offer line id'),
      productId: safeId(line.productId, 'offer product id'),
      productName: stringValue(line.productName, 'offer product name'),
      originalUnitPriceMinorUnits: nonNegativeInt(
        line.originalUnitPriceMinorUnits,
        'offer original price',
      ),
      finalUnitPriceMinorUnits: nonNegativeInt(
        line.finalUnitPriceMinorUnits,
        'offer final price',
      ),
      quantityMilliUnits: positiveInt(
        line.quantityMilliUnits,
        'offer quantityMilliUnits',
      ),
      unitFactorToBaseMilliUnits: positiveInt(
        line.unitFactorToBaseMilliUnits,
        'offer unit factor',
      ),
      priceType,
      unitId,
      unitName: line.unitName == null
        ? null
        : stringValue(line.unitName, 'offer unitName'),
      isService: line.isService === true,
    };
  });

  const lineIds = new Set(lines.map((line) => line.id));
  if (lineIds.size !== lines.length) {
    invalid('Offer line ids must be unique.');
  }

  for (const line of lines) {
    if (line.finalUnitPriceMinorUnits > line.originalUnitPriceMinorUnits) {
      invalid('Offer final price cannot exceed the original price.');
    }
  }

  const startDate = rawOffer.startDate == null
    ? null
    : parseDate(rawOffer.startDate, 'offer.startDate');
  const endDate = rawOffer.endDate == null
    ? null
    : parseDate(rawOffer.endDate, 'offer.endDate');
  if (startDate && endDate && startDate > endDate) {
    invalid('Offer start date must be before its end date.');
  }

  return {
    id: safeId(rawOffer.id, 'offer id'),
    offerNumber: stringValue(rawOffer.offerNumber, 'offer number'),
    name: stringValue(rawOffer.name, 'offer name'),
    description: optionalText(rawOffer.description, 'offer.description'),
    currency,
    createdAt: parseDate(rawOffer.createdAt, 'offer.createdAt'),
    isActive: rawOffer.isActive !== false,
    startDate,
    endDate,
    imageUrl: rawOffer.imageUrl == null
      ? null
      : stringValue(rawOffer.imageUrl, 'offer.imageUrl'),
    globalDiscountMinorUnits: nonNegativeInt(
      rawOffer.globalDiscountMinorUnits || 0,
      'offer global discount',
    ),
    lines,
  };
}

function parseOfferActiveCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  return {
    storeId: safeId(command.storeId, 'storeId'),
    offerId: safeId(command.offerId, 'offerId'),
    isActive: command.isActive === true,
  };
}

function parseOfferArchiveCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  return {
    storeId: safeId(command.storeId, 'storeId'),
    offerId: safeId(command.offerId, 'offerId'),
  };
}

function parseOfferOrderCreateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const rawOrder = asObject(command.order, 'order');
  return {
    storeId,
    order: {
      id: safeId(rawOrder.id, 'offer order id'),
      orderNumber: stringValue(rawOrder.orderNumber, 'offer order number'),
      offerId: safeId(rawOrder.offerId, 'offer id'),
      customerId: safeId(rawOrder.customerId, 'customer id'),
      idempotencyKey: safeId(
        rawOrder.idempotencyKey || rawOrder.id,
        'offer order idempotencyKey',
      ),
      createdAt: parseDate(rawOrder.createdAt, 'offer order.createdAt'),
    },
  };
}

function parseOfferOrderCancelCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  return {
    storeId: safeId(command.storeId, 'storeId'),
    orderId: safeId(command.orderId, 'orderId'),
  };
}

function parseOfferOrderConfirmCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const postingAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );
  const paymentMethod = stringValue(command.paymentMethod, 'paymentMethod');
  if (!PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported offer order payment method.');
  }
  const accounts = {
    settlementAccountId: optionalSafeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
    ),
    customerReceivableAccountId: optionalSafeId(
      postingAccounts.customerReceivableAccountId,
      'customerReceivableAccountId',
    ),
    salesAccountId: safeId(
      postingAccounts.salesAccountId,
      'salesAccountId',
    ),
    inventoryAccountId: safeId(
      postingAccounts.inventoryAccountId,
      'inventoryAccountId',
    ),
    costOfSalesAccountId: safeId(
      postingAccounts.costOfSalesAccountId,
      'costOfSalesAccountId',
    ),
    taxAccountId: optionalSafeId(
      postingAccounts.taxAccountId,
      'taxAccountId',
    ),
  };
  const paymentAccountId = paymentMethod === 'credit'
    ? accounts.customerReceivableAccountId
    : accounts.settlementAccountId;
  if (!paymentAccountId) {
    invalid('The offer order payment account is required.');
  }
  return {
    storeId: safeId(command.storeId, 'storeId'),
    orderId: safeId(command.orderId, 'orderId'),
    idempotencyKey: safeId(command.idempotencyKey, 'idempotencyKey'),
    postedAt: parseDate(command.postedAt, 'postedAt'),
    paymentMethod,
    accounts,
  };
}

async function createOfferInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const offerRef = storeRef.collection('offers').doc(command.offer.id);
  const idempotencyRef = storeRef
    .collection('offer_idempotency')
    .doc(command.idempotencyKey);

  const memberSnapshot = await transaction.get(memberRef);
  assertMembership(memberSnapshot, command.storeId, 'manage offers', OFFER_ROLES);
  const idempotencySnapshot = await transaction.get(idempotencyRef);
  if (idempotencySnapshot.exists) {
    const data = idempotencySnapshot.data();
    if (data.offerId === command.offer.id) {
      return {status: 'already_created', offerId: command.offer.id};
    }
    conflict('The offer idempotency key is already assigned.');
  }
  const existingSnapshot = await transaction.get(offerRef);
  if (existingSnapshot.exists) {
    conflict('The offer id already exists.');
  }

  const canonical = await canonicalOfferLines(transaction, storeRef, command);
  const offerData = offerDocument(command, canonical);
  transaction.set(offerRef, offerData);
  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    offerId: command.offer.id,
    idempotencyKey: command.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {status: 'created', offerId: command.offer.id};
}

async function updateOfferInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(memberSnapshot, command.storeId, 'manage offers', OFFER_ROLES);
  const offerRef = storeRef.collection('offers').doc(command.offerId);
  const existingSnapshot = await transaction.get(offerRef);
  if (!existingSnapshot.exists) {
    invalid('Offer was not found.');
  }

  const canonical = await canonicalOfferLines(transaction, storeRef, command);
  const existing = existingSnapshot.data();
  const next = offerDocument(command, canonical);
  next.createdAt = existing.createdAt || next.createdAt;
  transaction.set(offerRef, next);
  return {status: 'updated', offerId: command.offerId};
}

async function setOfferActiveInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(memberSnapshot, command.storeId, 'manage offers', OFFER_ROLES);
  const offerRef = storeRef.collection('offers').doc(command.offerId);
  const offerSnapshot = await transaction.get(offerRef);
  if (!offerSnapshot.exists) {
    invalid('Offer was not found.');
  }
  transaction.update(offerRef, {
    isActive: command.isActive,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'updated', offerId: command.offerId};
}

async function archiveOfferInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(memberSnapshot, command.storeId, 'manage offers', OFFER_ROLES);
  const offerRef = storeRef.collection('offers').doc(command.offerId);
  const offerSnapshot = await transaction.get(offerRef);
  if (!offerSnapshot.exists) {
    invalid('Offer was not found.');
  }
  transaction.update(offerRef, {
    isActive: false,
    archivedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'archived', offerId: command.offerId};
}

async function canonicalOfferLines(transaction, storeRef, command) {
  const productIds = [...new Set(
    command.offer.lines.map((line) => line.productId),
  )];
  const productSnapshots = new Map();
  for (const productId of productIds) {
    productSnapshots.set(
      productId,
      await transaction.get(storeRef.collection('products').doc(productId)),
    );
  }

  const lines = [];
  let originalTotal = 0;
  let lineFinalTotal = 0;
  for (const line of command.offer.lines) {
    const productSnapshot = productSnapshots.get(line.productId);
    if (!productSnapshot || !productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId) {
      deny('Product belongs to another store.');
    }
    if (product.isActive === false) {
      invalid('Inactive products cannot be used in an offer.');
    }
    const productCurrency = product.currency || 'ILS';
    if (productCurrency !== command.offer.currency) {
      invalid('Product currency does not match the offer.');
    }
    if (product.isService !== line.isService) {
      invalid('Offer service type does not match the product.');
    }
    const expectedFactor = expectedUnitFactor(product, line.unitId);
    if (expectedFactor !== line.unitFactorToBaseMilliUnits) {
      invalid('Product unit changed. Refresh the offer and try again.');
    }
    const originalLine = multiplyAndRound(
      line.originalUnitPriceMinorUnits,
      line.quantityMilliUnits,
    );
    const finalLine = multiplyAndRound(
      line.finalUnitPriceMinorUnits,
      line.quantityMilliUnits,
    );
    originalTotal += originalLine;
    lineFinalTotal += finalLine;
    lines.push({
      id: line.id,
      productId: line.productId,
      productName: product.name,
      originalUnitPriceMinorUnits: line.originalUnitPriceMinorUnits,
      finalUnitPriceMinorUnits: line.finalUnitPriceMinorUnits,
      quantityMilliUnits: line.quantityMilliUnits,
      unitFactorToBaseMilliUnits: line.unitFactorToBaseMilliUnits,
      priceType: line.priceType,
      unitId: line.unitId,
      unitName: line.unitName || product.baseUnitName || null,
      isService: line.isService,
    });
  }
  if (command.offer.globalDiscountMinorUnits > lineFinalTotal) {
    invalid('Offer discount cannot exceed the offer total.');
  }
  return {lines, originalTotal, lineFinalTotal};
}

function offerDocument(command, canonical) {
  const totalDiscount = canonical.originalTotal -
    canonical.lineFinalTotal +
    command.offer.globalDiscountMinorUnits;
  const totalFinal = canonical.lineFinalTotal -
    command.offer.globalDiscountMinorUnits;
  return {
    storeId: command.storeId,
    offerNumber: command.offer.offerNumber,
    name: command.offer.name,
    description: command.offer.description,
    currency: command.offer.currency,
    createdAt: Timestamp.fromDate(command.offer.createdAt),
    isActive: command.offer.isActive,
    startDate: command.offer.startDate
      ? Timestamp.fromDate(command.offer.startDate)
      : null,
    endDate: command.offer.endDate
      ? Timestamp.fromDate(command.offer.endDate)
      : null,
    imageUrl: command.offer.imageUrl,
    globalDiscountMinorUnits: command.offer.globalDiscountMinorUnits,
    totalOriginalMinorUnits: canonical.originalTotal,
    totalDiscountMinorUnits: totalDiscount,
    totalFinalMinorUnits: totalFinal,
    lines: canonical.lines,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function createOfferOrderInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'manage offer orders',
    OFFER_ROLES,
  );

  const orderRef = storeRef.collection('offer_orders').doc(command.order.id);
  const idempotencyRef = storeRef
    .collection('offer_order_idempotency')
    .doc(command.order.idempotencyKey);
  const [idempotencySnapshot, orderSnapshot, offerSnapshot, customerSnapshot] =
    await Promise.all([
      transaction.get(idempotencyRef),
      transaction.get(orderRef),
      transaction.get(storeRef.collection('offers').doc(command.order.offerId)),
      transaction.get(storeRef.collection('parties').doc(command.order.customerId)),
    ]);

  if (idempotencySnapshot.exists) {
    const data = idempotencySnapshot.data();
    if (data.orderId === command.order.id) {
      return {status: 'already_created', orderId: command.order.id};
    }
    conflict('The offer order idempotency key is already assigned.');
  }
  if (orderSnapshot.exists) {
    conflict('The offer order id already exists.');
  }
  if (!offerSnapshot.exists) {
    invalid('Offer was not found.');
  }
  const offer = offerSnapshot.data();
  if (offer.storeId !== command.storeId) {
    deny('Offer belongs to another store.');
  }
  if (!isOfferCurrentlyActive(offer)) {
    invalid('Only an active offer can create a new order.');
  }
  if (!customerSnapshot.exists) {
    invalid('Customer was not found.');
  }
  const customer = customerSnapshot.data();
  if (customer.storeId !== command.storeId ||
      customer.partyType !== 'customer') {
    invalid('The selected party is not a customer in this store.');
  }
  if (customer.isActive === false) {
    invalid('Inactive customers cannot receive offer orders.');
  }

  const offerLines = Array.isArray(offer.lines) ? offer.lines : [];
  if (offerLines.length === 0) {
    invalid('The offer has no products.');
  }
  for (const line of offerLines) {
    const productSnapshot = await transaction.get(
      storeRef.collection('products').doc(line.productId),
    );
    if (!productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId || product.isActive === false) {
      invalid('An offer product is no longer available.');
    }
    if (product.isService !== (line.isService === true)) {
      invalid('An offer product type changed.');
    }
    const factor = expectedUnitFactor(product, line.unitId || null);
    const required = multiplyAndRound(
      storedInt(line.quantityMilliUnits, 0),
      factor,
    );
    if (!product.isService &&
        storedInt(product.quantityOnHandMilliUnits, 0) < required) {
      throw new HttpsError(
        'failed-precondition',
        'Insufficient stock for offer product ' + line.productId + '.',
      );
    }
  }

  const orderData = {
    storeId: command.storeId,
    orderNumber: command.order.orderNumber,
    offerId: command.order.offerId,
    offerNumber: offer.offerNumber,
    customerId: command.order.customerId,
    customerName: customer.name,
    currency: offer.currency,
    createdAt: Timestamp.fromDate(command.order.createdAt),
    status: 'pending',
    paymentMethod: null,
    globalDiscountMinorUnits: storedInt(offer.globalDiscountMinorUnits, 0),
    totalMinorUnits: storedInt(offer.totalFinalMinorUnits, 0),
    saleId: null,
    journalEntryId: null,
    confirmedAt: null,
    lines: offerLines,
    createdBy: userId,
    updatedAt: FieldValue.serverTimestamp(),
  };
  transaction.set(orderRef, orderData);
  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    orderId: command.order.id,
    idempotencyKey: command.order.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {status: 'created', orderId: command.order.id};
}

async function cancelOfferOrderInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'manage offer orders',
    OFFER_ROLES,
  );
  const orderRef = storeRef.collection('offer_orders').doc(command.orderId);
  const orderSnapshot = await transaction.get(orderRef);
  if (!orderSnapshot.exists) {
    invalid('Offer order was not found.');
  }
  const order = orderSnapshot.data();
  if (order.status === 'cancelled') {
    return {status: 'already_cancelled', orderId: command.orderId};
  }
  if (order.status === 'confirmed') {
    invalid('A confirmed offer order must be reversed through a sales return.');
  }
  transaction.update(orderRef, {
    status: 'cancelled',
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {status: 'cancelled', orderId: command.orderId};
}

async function confirmOfferOrderInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'confirm offer orders',
    OFFER_ROLES,
  );
  const orderRef = storeRef.collection('offer_orders').doc(command.orderId);
  const confirmationRef = storeRef
    .collection('offer_order_confirmation_idempotency')
    .doc(command.idempotencyKey);
  const [orderSnapshot, confirmationSnapshot] = await Promise.all([
    transaction.get(orderRef),
    transaction.get(confirmationRef),
  ]);
  if (!orderSnapshot.exists) {
    invalid('Offer order was not found.');
  }
  const order = orderSnapshot.data();
  if (confirmationSnapshot.exists) {
    const data = confirmationSnapshot.data();
    return {
      status: 'already_confirmed',
      orderId: command.orderId,
      saleId: data.saleId,
      journalEntryId: data.journalEntryId,
    };
  }
  if (order.status === 'confirmed') {
    return {
      status: 'already_confirmed',
      orderId: command.orderId,
      saleId: order.saleId,
      journalEntryId: order.journalEntryId,
    };
  }
  if (order.status === 'cancelled') {
    invalid('A cancelled offer order cannot be confirmed.');
  }

  const rawLines = Array.isArray(order.lines) ? order.lines : [];
  const saleLines = [];
  const productSnapshots = new Map();
  for (const line of rawLines) {
    const productRef = storeRef.collection('products').doc(line.productId);
    const productSnapshot = await transaction.get(productRef);
    if (!productSnapshot.exists) {
      invalid('Product was not found: ' + line.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId || product.isActive === false) {
      invalid('An offer product is no longer available.');
    }
    if (product.isService !== (line.isService === true)) {
      invalid('An offer product type changed.');
    }
    const factor = expectedUnitFactor(product, line.unitId || null);
    if (factor !== storedInt(line.unitFactorToBaseMilliUnits, 0)) {
      invalid('Product unit changed. Refresh the offer order and try again.');
    }
    productSnapshots.set(line.productId, productSnapshot);
    saleLines.push({
      id: command.orderId + '-' + line.id,
      productId: line.productId,
      description: line.productName,
      quantityMilliUnits: positiveInt(
        storedInt(line.quantityMilliUnits, 0),
        'offer order quantity',
      ),
      unitFactorToBaseMilliUnits: factor,
      unitPriceMinorUnits: nonNegativeInt(
        storedInt(line.finalUnitPriceMinorUnits, 0),
        'offer order price',
      ),
      unitCostMinorUnits: line.isService === true
        ? 0
        : storedInt(product.purchasePriceMinorUnits, 0),
      discountMinorUnits: 0,
      unitId: line.unitId || null,
      unitName: line.unitName || product.baseUnitName || null,
      isService: line.isService === true,
    });
  }

  let remainingDiscount = storedInt(order.globalDiscountMinorUnits, 0);
  for (const line of saleLines) {
    const gross = multiplyAndRound(
      line.unitPriceMinorUnits,
      line.quantityMilliUnits,
    );
    const discount = Math.min(remainingDiscount, gross);
    line.discountMinorUnits = discount;
    remainingDiscount -= discount;
  }
  if (remainingDiscount > 0) {
    invalid('Offer discount exceeds the order total.');
  }

  const saleId = 'sale-offer-order-' + command.orderId;
  const saleCommand = {
    storeId: command.storeId,
    sale: {
      id: saleId,
      idempotencyKey: command.idempotencyKey,
      postedAt: command.postedAt,
      paymentMethod: command.paymentMethod,
      customerId: order.customerId,
      description: 'Offer ' + order.offerNumber +
        ' order ' + order.orderNumber,
      currency: order.currency,
      taxMinorUnits: 0,
      lines: saleLines,
    },
    accounts: command.accounts,
  };
  const result = await postSaleInTransaction(
    transaction,
    userId,
    saleCommand,
    OFFER_ROLES,
  );

  transaction.update(orderRef, {
    status: 'confirmed',
    paymentMethod: command.paymentMethod,
    saleId: result.saleId,
    journalEntryId: result.journalEntryId,
    confirmedAt: Timestamp.fromDate(command.postedAt),
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(confirmationRef, {
    storeId: command.storeId,
    orderId: command.orderId,
    saleId: result.saleId,
    journalEntryId: result.journalEntryId,
    idempotencyKey: command.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {
    status: result.status === 'already_posted'
      ? 'already_confirmed'
      : 'confirmed',
    orderId: command.orderId,
    saleId: result.saleId,
    journalEntryId: result.journalEntryId,
  };
}

function isOfferCurrentlyActive(offer) {
  if (offer.isActive === false) {
    return false;
  }
  const now = Date.now();
  if (offer.startDate && offer.startDate.toMillis() > now) {
    return false;
  }
  if (offer.endDate && offer.endDate.toMillis() < now) {
    return false;
  }
  return true;
}

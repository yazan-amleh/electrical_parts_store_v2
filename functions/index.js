const { setGlobalOptions } = require('firebase-functions/v2');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
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
const { createStoreHandler, selectStoreHandler } = require('./store_onboarding');
const {
  checkedMinorAdd,
  readBalanceForPosting,
  readPartyBalanceForPosting,
  fingerprintJournal,
  isSameLegacyJournalHeader,
  isSameLegacyJournalLine,
} = require('./accounting/journal_integrity');
const {
  fingerprintAccountTransfer,
  sameLegacyTransfer,
} = require('./accounting/transfer_integrity');
const {
  expenseFingerprint,
  sameLegacyExpense,
  sameLegacyExpenseLines,
} = require('./accounting/expense_integrity');
const {
  fingerprintPartyPayment,
  sameLegacyPartyPayment,
  sameLegacyPartyPaymentLines,
} = require('./accounting/party_payment_integrity');
const {
  fingerprintChequeSettlement,
  sameLegacyChequeSettlement,
  sameLegacyChequeLines,
} = require('./accounting/cheque_settlement_integrity');
const {
  fingerprintPurchase,
  matchesLegacyPurchaseHeader,
  matchesLegacyPurchaseLines,
  matchesLegacyPurchaseJournal,
} = require('./accounting/purchase_integrity');
const {
  fingerprintSale,
  matchesLegacySaleInvoice,
  matchesLegacySaleLines,
  matchesLegacySaleJournal,
} = require('./accounting/sale_integrity');
const {
  fingerprintPurchaseOrderReceipt,
  matchesLegacyPurchaseOrderReceipt,
  matchesLegacyPurchaseOrderJournalLines,
} = require('./accounting/purchase_order_receipt_integrity');
const {
  MAX_AUDIT_DOCS_PER_COLLECTION,
  MAX_AUDIT_TOTAL_DOCS,
  readAuditPages,
  readJournalAuditLines,
  isJournalLinePath,
  auditInteger,
  auditSum,
} = require('./accounting/audit_integrity');

exports.createStore = onCall((request) =>
  createStoreHandler({ db, FieldValue, HttpsError, request }),
);

exports.selectStore = onCall((request) =>
  selectStoreHandler({ db, FieldValue, HttpsError, request }),
);

const QUANTITY_SCALE = 1000;
const MAX_LINES = 100;
const POSTING_ROLES = new Set(['owner', 'admin', 'accountant', 'sales']);
const OFFER_ROLES = new Set(['owner', 'admin', 'accountant', 'sales']);
const OFFER_PRICE_TYPES = new Set(['retail', 'wholesale', 'custom']);
const PARTY_PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'cheque']);
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

exports.sendChatMessageNotification = onDocumentCreated(
  'stores/{storeId}/chatRooms/{roomId}/messages/{messageId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      return null;
    }

    const message = snapshot.data() || {};
    const { storeId, roomId, messageId } = event.params;
    const senderId = typeof message.senderId === 'string'
      ? message.senderId
      : '';
    const roomSnapshot = await db
      .collection('stores')
      .doc(storeId)
      .collection('chatRooms')
      .doc(roomId)
      .get();
    if (!roomSnapshot.exists) {
      return null;
    }

    const room = roomSnapshot.data() || {};
    const participantIds = Array.isArray(room.participantIds)
      ? room.participantIds.filter((userId) => typeof userId === 'string')
      : [];
    const recipientIds = participantIds.filter((userId) => userId !== senderId);
    if (recipientIds.length === 0) {
      return null;
    }

    const tokens = [];
    for (let offset = 0; offset < recipientIds.length; offset += 30) {
      const userIds = recipientIds.slice(offset, offset + 30);
      const tokenSnapshot = await db
        .collection('stores')
        .doc(storeId)
        .collection('notificationTokens')
        .where('userId', 'in', userIds)
        .get();
      for (const tokenDoc of tokenSnapshot.docs) {
        const tokenData = tokenDoc.data() || {};
        if (typeof tokenData.token === 'string' && tokenData.token.length > 0) {
          tokens.push({
            value: tokenData.token,
            ref: tokenDoc.ref,
          });
        }
      }
    }
    const uniqueTokens = [
      ...new Map(tokens.map((entry) => [entry.value, entry])).values(),
    ];
    if (uniqueTokens.length === 0) {
      return null;
    }

    const content = typeof message.content === 'string'
      ? message.content.trim()
      : '';
    const body = content || 'تم إرسال مرفق جديد';
    const response = await admin.messaging().sendEachForMulticast({
      tokens: uniqueTokens.map((entry) => entry.value),
      notification: {
        title: typeof room.name === 'string' && room.name.trim()
          ? room.name.trim()
          : 'محادثة جديدة',
        body: body.substring(0, 120),
      },
      data: {
        storeId,
        roomId,
        messageId,
        type: typeof message.type === 'string' ? message.type : 'text',
      },
    });

    const invalidTokenRefs = [];
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokenRefs.push(uniqueTokens[index].ref);
      }
    });
    if (invalidTokenRefs.length > 0) {
      const batch = db.batch();
      for (const tokenRef of invalidTokenRefs) {
        batch.delete(tokenRef);
      }
      await batch.commit();
    }

    return {
      sent: response.successCount,
      removedInvalidTokens: invalidTokenRefs.length,
    };
  },
);


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

    totalDebitMinorUnits = checkedMinorAdd(
      totalDebitMinorUnits, debitMinorUnits, 'Journal total debit',
    );
    totalCreditMinorUnits = checkedMinorAdd(
      totalCreditMinorUnits, creditMinorUnits, 'Journal total credit',
    );
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

  const fingerprint = fingerprintJournal(command.entry);
  const idempotencySnapshot = await transaction.get(idempotencyRef);
  if (idempotencySnapshot.exists) {
    const marker = idempotencySnapshot.data();
    if (marker.entryId !== command.entry.id) {
      conflict('The journal idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== fingerprint) {
        conflict('The journal idempotency key was reused with different data.');
      }
    } else {
      // Pre-fingerprint V2 entries must also be verified before acknowledging
      // a retry. Never claim a changed amount was already posted.
      const oldJournal = await transaction.get(journalRef);
      if (!oldJournal.exists ||
          !isSameLegacyJournalHeader(oldJournal.data(), command.entry)) {
        conflict('The historical journal cannot be verified for this retry.');
      }
      const oldLines = await transaction.get(journalRef.collection('lines'));
      if (oldLines.size !== command.entry.lines.length) {
        conflict('The historical journal lines differ from this retry.');
      }
      for (const line of command.entry.lines) {
        const oldLine = oldLines.docs.find((doc) => doc.id === line.id);
        if (!oldLine ||
            !isSameLegacyJournalLine(oldLine.data(), line, command.entry)) {
          conflict('The historical journal lines differ from this retry.');
        }
      }
    }
    return {
      status: 'already_posted',
      entryId: command.entry.id,
    };
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
      debit: checkedMinorAdd(
        previous.debit, line.debitMinorUnits, 'Account debit delta',
      ),
      credit: checkedMinorAdd(
        previous.credit, line.creditMinorUnits, 'Account credit delta',
      ),
    });
  }

  transaction.set(journalRef, {
    storeId: command.storeId,
    idempotencyKey: command.entry.idempotencyKey,
    sourceType: command.entry.sourceType,
    description: command.entry.description,
    status: 'posted',
    currency: command.entry.currency,
    requestFingerprint: fingerprint,
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
    const previous = readBalanceForPosting(balanceSnapshot, {
      storeId: command.storeId,
      accountId,
      currency: command.entry.currency,
    });
    const delta = deltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      previous.debit, delta.debit, 'Running account debit balance',
    );
    const nextCredit = checkedMinorAdd(
      previous.credit, delta.credit, 'Running account credit balance',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Running account net balance',
    );

    transaction.set(
      storeRef.collection('account_balances').doc(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.entry.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    entryId: command.entry.id,
    idempotencyKey: command.entry.idempotencyKey,
    requestFingerprint: fingerprint,
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

  const transferFingerprint = fingerprintAccountTransfer(command.transfer);
  const transferIdempotencySnapshot = await transaction.get(
    transferIdempotencyRef,
  );
  if (transferIdempotencySnapshot.exists) {
    const marker = transferIdempotencySnapshot.data();
    if (marker.transferId !== command.transfer.id) {
      conflict('The transfer idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== transferFingerprint) {
        conflict('The transfer key was replayed with changed financial details.');
      }
    } else {
      // Preserve existing V2 transfer retries, but never trust a matching ID
      // alone when an old marker predates request fingerprints.
      const oldTransfer = await transaction.get(transferRef);
      const oldJournal = await transaction.get(journalRef);
      const oldJournalMarker = await transaction.get(journalIdempotencyRef);
      if (!oldTransfer.exists ||
          !sameLegacyTransfer(
            oldTransfer.data(), command.transfer, journalEntryId,
          ) ||
          !oldJournal.exists ||
          oldJournal.data().status !== 'posted' ||
          oldJournal.data().sourceType !== 'accountTransfer' ||
          oldJournal.data().totalDebitMinorUnits !==
            command.transfer.amountMinorUnits ||
          oldJournal.data().totalCreditMinorUnits !==
            command.transfer.amountMinorUnits ||
          !oldJournalMarker.exists ||
          oldJournalMarker.data().entryId !== journalEntryId) {
        conflict('The historical transfer cannot be verified for this retry.');
      }
    }
    return {
      status: 'already_posted',
      transferId: command.transfer.id,
      journalEntryId,
    };
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
      requestFingerprint: transferFingerprint,
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
    const previous = readBalanceForPosting(
      balanceSnapshots.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.transfer.currency,
      },
    );
    const delta = accountDeltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      previous.debit, delta.debit, 'Transfer account debit',
    );
    const nextCredit = checkedMinorAdd(
      previous.credit, delta.credit, 'Transfer account credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Transfer account net',
    );
    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.transfer.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
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
      requestFingerprint: transferFingerprint,
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
  checkedMinorAdd(amountMinorUnits, taxMinorUnits, 'Expense inclusive tax total');
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
  const supplierRef = isCreditExpense
    ? storeRef.collection('parties').doc(command.expense.supplierId)
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

  const fingerprint = expenseFingerprint(command);
  const expenseIdempotencySnapshot = await transaction.get(
    expenseIdempotencyRef,
  );
  if (expenseIdempotencySnapshot.exists) {
    const marker = expenseIdempotencySnapshot.data();
    if (marker.expenseId !== command.expense.id) {
      conflict('The expense idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== fingerprint) {
        conflict('Expense idempotency key reused with different financial data.');
      }
    } else {
      const oldExpense = await transaction.get(expenseRef);
      const oldJournal = await transaction.get(journalRef);
      const oldMarker = await transaction.get(journalIdempotencyRef);
      const inclusiveTotal = checkedMinorAdd(
        command.expense.amountMinorUnits, command.expense.taxMinorUnits,
        'Expense total',
      );
      if (!oldExpense.exists ||
          !sameLegacyExpense(
            oldExpense.data(), command, journalEntryId, inclusiveTotal,
          ) ||
          !oldJournal.exists ||
          oldJournal.data().storeId !== command.storeId ||
          oldJournal.data().status !== 'posted' ||
          oldJournal.data().sourceType !== 'expense' ||
          oldJournal.data().currency !== command.expense.currency ||
          oldJournal.data().totalDebitMinorUnits !== inclusiveTotal ||
          oldJournal.data().totalCreditMinorUnits !== inclusiveTotal ||
          !oldMarker.exists ||
          oldMarker.data().entryId !== journalEntryId) {
        conflict('Historical expense could not be verified for replay.');
      }
      const oldLines = await transaction.get(journalRef.collection('lines'));
      if (!sameLegacyExpenseLines(
        oldLines, command, journalEntryId, inclusiveTotal,
      )) {
        conflict('Historical expense journal lines differ from this replay.');
      }
    }
    return {
      status: 'already_posted',
      expenseId: command.expense.id,
      journalEntryId,
    };
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
    const supplierSnapshot = await transaction.get(supplierRef);
    assertParty(
      supplierSnapshot, command.storeId, command.expense.supplierId,
      'supplier',
    );
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

  const totalMinorUnits = checkedMinorAdd(
    command.expense.amountMinorUnits, command.expense.taxMinorUnits,
    'Expense total',
  );
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
    requestFingerprint: fingerprint,
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
        currency: command.expense.currency,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.expense.postedAt),
      },
    );
  }

  if (isCreditExpense) {
    const prior = readPartyBalanceForPosting(
      supplierBalanceSnapshot,
      {
        storeId: command.storeId,
        partyId: command.expense.supplierId,
        partyType: 'supplier',
        currency: command.expense.currency,
      },
    );
    const nextDebit = prior.debit;
    const nextCredit = checkedMinorAdd(
      prior.credit, totalMinorUnits, 'Supplier payable balance',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Supplier payable net balance',
    );

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
        balanceMinorUnits: nextNet,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const prior = readBalanceForPosting(
      balanceSnapshots.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.expense.currency,
      },
    );
    const delta = accountDeltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      prior.debit, delta.debit, 'Expense account debit',
    );
    const nextCredit = checkedMinorAdd(
      prior.credit, delta.credit, 'Expense account credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Expense account net',
    );
    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.expense.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
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
      requestFingerprint: fingerprint,
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
  const chequeNumber = payment.chequeNumber == null
    ? null
    : stringValue(payment.chequeNumber, 'payment.chequeNumber');
  const bankName = payment.bankName == null
    ? null
    : stringValue(payment.bankName, 'payment.bankName');
  const dueDate = payment.dueDate == null
    ? null
    : parseDate(payment.dueDate, 'payment.dueDate');
  if (paymentMethod === 'cheque' && !chequeNumber) {
    invalid('A cheque number is required.');
  }
  if (paymentMethod === 'cheque' && !bankName) {
    invalid('A cheque bank name is required.');
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
      chequeNumber,
      bankName,
      dueDate,
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

  const fingerprint = fingerprintPartyPayment(command);
  const paymentIdempotencySnapshot = await transaction.get(
    paymentIdempotencyRef,
  );
  if (paymentIdempotencySnapshot.exists) {
    const marker = paymentIdempotencySnapshot.data();
    if (marker.paymentId !== command.payment.id) {
      conflict('The payment idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== fingerprint) {
        conflict('Payment idempotency key reused with changed financial details.');
      }
    } else {
      const previousPayment = await transaction.get(paymentRef);
      const previousJournal = await transaction.get(journalRef);
      const previousJournalMarker = await transaction.get(journalIdempotencyRef);
      const type = command.payment.partyType === 'customer'
        ? 'customerReceipt' : 'supplierPayment';
      if (!previousPayment.exists ||
          !sameLegacyPartyPayment(
            previousPayment.data(), command, journalEntryId,
          ) ||
          !previousJournal.exists ||
          previousJournal.data().storeId !== command.storeId ||
          previousJournal.data().status !== 'posted' ||
          previousJournal.data().sourceType !== type ||
          previousJournal.data().currency !== command.payment.currency ||
          previousJournal.data().totalDebitMinorUnits !==
            command.payment.amountMinorUnits ||
          previousJournal.data().totalCreditMinorUnits !==
            command.payment.amountMinorUnits ||
          !previousJournalMarker.exists ||
          previousJournalMarker.data().entryId !== journalEntryId) {
        conflict('Historical party payment cannot be verified for replay.');
      }
      const previousLines = await transaction.get(journalRef.collection('lines'));
      if (!sameLegacyPartyPaymentLines(
        previousLines, command, journalEntryId,
      )) {
        conflict('Historical party payment journal lines differ from replay.');
      }
    }
    return {
      status: 'already_posted',
      paymentId: command.payment.id,
      journalEntryId,
    };
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

  const isCustomerPayment = command.payment.partyType === 'customer';
  const settlementAccountType =
    !isCustomerPayment && command.payment.paymentMethod === 'cheque'
      ? 'liability'
      : 'asset';
  assertAccount(
    accountSnapshots.get(command.accounts.settlementAccountId),
    command.accounts.settlementAccountId,
    command.storeId,
    command.payment.currency,
    settlementAccountType,
    paymentAccountControlType(
      command.payment.paymentMethod,
      command.payment.partyType,
    ),
  );
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
    requestFingerprint: fingerprint,
    postedAt: Timestamp.fromDate(command.payment.postedAt),
    partyType: command.payment.partyType,
    partyId: command.payment.partyId,
    paymentMethod: command.payment.paymentMethod,
    amountMinorUnits: amount,
    currency: command.payment.currency,
    description: command.payment.description,
    journalEntryId,
    status: command.payment.paymentMethod === 'cheque'
      ? 'pending'
      : 'posted',
    chequeNumber: command.payment.chequeNumber,
    bankName: command.payment.bankName,
    dueDate: command.payment.dueDate == null
      ? null
      : Timestamp.fromDate(command.payment.dueDate),
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

  const previousParty = readPartyBalanceForPosting(
    partyBalanceSnapshot,
    {
      storeId: command.storeId,
      partyId: command.payment.partyId,
      partyType: command.payment.partyType,
      currency: command.payment.currency,
    },
  );
  const nextPartyDebit = checkedMinorAdd(
    previousParty.debit, isCustomerPayment ? 0 : amount,
    'Party settlement debit',
  );
  const nextPartyCredit = checkedMinorAdd(
    previousParty.credit, isCustomerPayment ? amount : 0,
    'Party settlement credit',
  );
  const nextPartyNet = checkedMinorAdd(
    nextPartyDebit, -nextPartyCredit, 'Party settlement net',
  );
  transaction.set(
    partyBalanceRef,
    {
      storeId: command.storeId,
      partyType: command.payment.partyType,
      partyId: command.payment.partyId,
      currency: command.payment.currency,
      debitMinorUnits: nextPartyDebit,
      creditMinorUnits: nextPartyCredit,
      balanceMinorUnits: nextPartyNet,
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
        currency: command.payment.currency,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.payment.postedAt),
      },
    );
  }

  for (const accountId of accountIds) {
    const previous = readBalanceForPosting(
      balanceSnapshots.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.payment.currency,
      },
    );
    const delta = accountDeltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      previous.debit, delta.debit, 'Payment GL debit',
    );
    const nextCredit = checkedMinorAdd(
      previous.credit, delta.credit, 'Payment GL credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Payment GL net',
    );
    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.payment.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
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
      requestFingerprint: fingerprint,
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

  const fingerprint = fingerprintPurchase(command);
  const purchaseIdempotencySnapshot = await transaction.get(
    purchaseIdempotencyRef,
  );
  if (purchaseIdempotencySnapshot.exists) {
    const marker = purchaseIdempotencySnapshot.data();
    if (marker.purchaseId !== command.purchase.id) {
      conflict('The purchase idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== fingerprint) {
        conflict('The purchase key was reused with changed invoice details.');
      }
    } else {
      const oldInvoice = await transaction.get(purchaseRef);
      const oldJournal = await transaction.get(journalRef);
      const oldMarker = await transaction.get(journalIdempotencyRef);
      if (!oldInvoice.exists ||
          !oldJournal.exists ||
          !oldMarker.exists ||
          oldMarker.data().entryId !== journalEntryId ||
          !matchesLegacyPurchaseHeader(
            oldInvoice.data(), command, journalEntryId,
          )) {
        conflict('Historical purchase cannot be verified for replay.');
      }
      const invoiceLines = await transaction.get(purchaseRef.collection('lines'));
      const journalLines = await transaction.get(journalRef.collection('lines'));
      if (!matchesLegacyPurchaseLines(invoiceLines, command) ||
          !matchesLegacyPurchaseJournal(
            oldJournal.data(), journalLines, command,
            journalEntryId, oldInvoice.data(),
          )) {
        conflict('Historical purchase lines/journal differ from replay.');
      }
    }
    return {
      status: 'already_posted',
      purchaseId: command.purchase.id,
      journalEntryId,
    };
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
    subtotalMinorUnits = checkedMinorAdd(
      subtotalMinorUnits, totalMinorUnits, 'Purchase subtotal',
    );

    const previous = receivedByProduct.get(line.productId) || {
      quantity: 0,
      cost: 0,
    };
    receivedByProduct.set(line.productId, {
      quantity: checkedMinorAdd(
        previous.quantity, baseQuantityMilliUnits, 'Purchased product quantity',
      ),
      cost: checkedMinorAdd(
        previous.cost, totalMinorUnits, 'Purchased product cost',
      ),
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

  const grandTotalMinorUnits = checkedMinorAdd(
    subtotalMinorUnits, command.purchase.taxMinorUnits, 'Purchase grand total',
  );
  if (grandTotalMinorUnits <= 0) {
    invalid('A purchase total must be greater than zero.');
  }

  const nextProducts = new Map();
  for (const [productId, receipt] of receivedByProduct) {
    const product = productSnapshots.get(productId).data();
    const currentQuantity = product.quantityOnHandMilliUnits ?? 0;
    const currentUnitCost = product.purchasePriceMinorUnits ?? 0;
    if (!Number.isSafeInteger(currentQuantity) || currentQuantity < 0 ||
        !Number.isSafeInteger(currentUnitCost) || currentUnitCost < 0) {
      throw new HttpsError(
        'failed-precondition', 'Product quantity or cost is corrupt.',
      );
    }
    // The stored inventory value is authoritative. Multiplying a rounded
    // average unit cost may silently change historical stock value.
    const currentTotalCost = product.inventoryValueMinorUnits ??
      (currentQuantity > 0
        ? multiplyAndRound(currentUnitCost, currentQuantity) : 0);
    if (!Number.isSafeInteger(currentTotalCost) ||
        currentTotalCost < 0 ||
        (currentQuantity === 0 && currentTotalCost !== 0)) {
      throw new HttpsError(
        'failed-precondition', 'Product inventory value is corrupt.',
      );
    }
    const nextQuantity = checkedMinorAdd(
      currentQuantity, receipt.quantity, 'Purchase stock quantity',
    );
    const nextTotalCost = checkedMinorAdd(
      currentTotalCost, receipt.cost, 'Purchase stock value',
    );
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

  const totalDebitMinorUnits = checkedMinorAdd(
    subtotalMinorUnits, command.purchase.taxMinorUnits, 'Purchase GL debit',
  );
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
    requestFingerprint: fingerprint,
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
        currency: command.purchase.currency,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.purchase.postedAt),
      },
    );
  }

  if (isCreditPurchase) {
    const prior = readPartyBalanceForPosting(
      supplierBalanceSnapshot, {
        storeId: command.storeId,
        partyId: command.purchase.supplierId,
        partyType: 'supplier',
        currency: command.purchase.currency,
      },
    );
    const nextDebit = prior.debit;
    const nextCredit = checkedMinorAdd(
      prior.credit, grandTotalMinorUnits, 'Purchase supplier payable',
    );
    const nextPartyNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Purchase supplier net balance',
    );

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
        balanceMinorUnits: nextPartyNet,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const prior = readBalanceForPosting(
      balanceSnapshots.get(accountId), {
        storeId: command.storeId,
        accountId,
        currency: command.purchase.currency,
      },
    );
    const delta = accountDeltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      prior.debit, delta.debit, 'Purchase GL account debit',
    );
    const nextCredit = checkedMinorAdd(
      prior.credit, delta.credit, 'Purchase GL account credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Purchase GL account net',
    );
    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.purchase.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
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
      requestFingerprint: fingerprint,
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
    totalMinorUnits = checkedMinorAdd(
      totalMinorUnits, lineTotalMinorUnits, 'Purchase order total',
    );
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

  const fingerprint = fingerprintPurchaseOrderReceipt(command);
  const idempotencySnapshot = await transaction.get(receiptIdempotencyRef);
  if (idempotencySnapshot.exists) {
    const previous = idempotencySnapshot.data();
    if (previous.storeId !== command.storeId ||
        previous.orderId !== command.orderId ||
        previous.receiptId !== command.receiptId ||
        previous.purchaseId !== command.receiptId ||
        previous.journalEntryId !== command.receiptId + '-journal') {
      conflict('The purchase order receipt key is already assigned.');
    }
    if (previous.requestFingerprint != null) {
      if (previous.requestFingerprint !== fingerprint) {
        conflict('Receipt retry differs from the original financial request.');
      }
    } else {
      const historicalOrderRef = storeRef.collection('purchase_orders')
        .doc(command.orderId);
      const historicalPurchaseRef = storeRef.collection('purchases')
        .doc(command.receiptId);
      const historicalJournalRef = storeRef.collection('journal_entries')
        .doc(command.receiptId + '-journal');
      const historicalOrder = await transaction.get(historicalOrderRef);
      const historicalPurchase = await transaction.get(historicalPurchaseRef);
      const historicalJournal = await transaction.get(historicalJournalRef);
      if (!historicalOrder.exists ||
          !historicalPurchase.exists ||
          !historicalJournal.exists ||
          !matchesLegacyPurchaseOrderReceipt(
            previous, historicalOrder.data(), historicalPurchase.data(),
            historicalJournal.data(), command,
          )) {
        conflict('Historical purchase order receipt cannot be verified.');
      }
      const lineNames = [
        command.receiptId + '-inventory',
        ...(command.taxMinorUnits > 0
          ? [command.receiptId + '-input-tax'] : []),
        command.receiptId + '-settlement',
      ];
      const historicLines = [];
      for (const name of lineNames) {
        historicLines.push(await transaction.get(
          historicalJournalRef.collection('lines').doc(name),
        ));
      }
      if (!matchesLegacyPurchaseOrderJournalLines(
        historicLines, historicalPurchase.data(), command,
      )) {
        conflict('Historical receipt journal accounts do not match replay.');
      }
    }
    return {
      status: 'already_received',
      orderId: command.orderId,
      purchaseId: command.receiptId,
      journalEntryId: command.receiptId + '-journal',
    };
  }

  const orderSnapshot = await transaction.get(orderRef);
  if (!orderSnapshot.exists) {
    invalid('Purchase order was not found.');
  }
  const order = orderSnapshot.data();
  if (order.storeId !== command.storeId) {
    deny('Purchase order belongs to another store.');
  }
  // Without the receipt marker there is no safe way to distinguish an
  // identical retry from a conflicting request: never acknowledge it.
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
    const receivedQuantity = line.receivedQuantityMilliUnits ?? 0;
    if (!Number.isSafeInteger(receivedQuantity) || receivedQuantity < 0) {
      throw new HttpsError(
        'failed-precondition', 'Purchase order received quantity is corrupt.',
      );
    }
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
    requestFingerprint: fingerprint,
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

  const fingerprint = fingerprintSale(command);
  const saleIdempotencySnapshot = await transaction.get(saleIdempotencyRef);
  if (saleIdempotencySnapshot.exists) {
    const marker = saleIdempotencySnapshot.data();
    if (marker.saleId !== command.sale.id) {
      conflict('The sale idempotency key is already assigned.');
    }
    if (marker.requestFingerprint != null) {
      if (marker.requestFingerprint !== fingerprint) {
        conflict('Sale key was reused with changed invoice details.');
      }
    } else {
      const oldInvoice = await transaction.get(saleRef);
      const oldJournal = await transaction.get(journalRef);
      const oldMarker = await transaction.get(journalIdempotencyRef);
      if (!oldInvoice.exists ||
          !oldJournal.exists ||
          !oldMarker.exists ||
          oldMarker.data().entryId !== journalEntryId ||
          !matchesLegacySaleInvoice(
            oldInvoice.data(), command, journalEntryId,
          )) {
        conflict('Historical sale cannot be verified for retry.');
      }
      const invoiceLines = await transaction.get(saleRef.collection('lines'));
      const journalLines = await transaction.get(journalRef.collection('lines'));
      if (!matchesLegacySaleLines(invoiceLines, command) ||
          !matchesLegacySaleJournal(
            oldJournal.data(), journalLines, command,
            journalEntryId, oldInvoice.data(),
          )) {
        conflict('Historical sale lines/journal differ from retry.');
      }
    }
    return {
      status: 'already_posted',
      saleId: command.sale.id,
      journalEntryId,
    };
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

    const purchasePriceMinorUnits = product.purchasePriceMinorUnits ?? 0;
    if (!Number.isSafeInteger(purchasePriceMinorUnits) ||
        purchasePriceMinorUnits < 0) {
      throw new HttpsError(
        'failed-precondition', 'Product purchase cost is corrupt.',
      );
    }
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

    subtotalMinorUnits = checkedMinorAdd(
      subtotalMinorUnits, totalMinorUnits, 'Sale subtotal',
    );
    costTotalMinorUnits = checkedMinorAdd(
      costTotalMinorUnits, costMinorUnits, 'Sale COGS total',
    );

    if (!line.isService) {
      const previousIssued = issuedByProduct.get(line.productId) || {
        quantity: 0,
        cost: 0,
      };
      issuedByProduct.set(line.productId, {
        quantity: checkedMinorAdd(
          previousIssued.quantity, baseQuantityMilliUnits, 'Sale issue quantity',
        ),
        cost: checkedMinorAdd(
          previousIssued.cost, costMinorUnits, 'Sale issue cost',
        ),
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

  const grandTotalMinorUnits = checkedMinorAdd(
    subtotalMinorUnits, command.sale.taxMinorUnits, 'Sale gross total',
  );
  if (grandTotalMinorUnits <= 0) {
    invalid('A sale total must be greater than zero.');
  }

  const nextProducts = new Map();
  for (const [productId, issued] of issuedByProduct) {
    const productSnapshot = productSnapshots.get(productId);
    const product = productSnapshot.data();
    const currentQuantity = product.quantityOnHandMilliUnits ?? 0;
    const currentUnitCost = product.purchasePriceMinorUnits ?? 0;
    if (!Number.isSafeInteger(currentQuantity) || currentQuantity < 0 ||
        !Number.isSafeInteger(currentUnitCost) || currentUnitCost < 0) {
      throw new HttpsError(
        'failed-precondition', 'Sale product quantity or price is corrupt.',
      );
    }
    const currentInventoryValue = product.inventoryValueMinorUnits ??
      multiplyAndRound(currentUnitCost, currentQuantity);
    if (!Number.isSafeInteger(currentInventoryValue) ||
        currentInventoryValue < 0 ||
        (currentQuantity === 0 && currentInventoryValue !== 0)) {
      throw new HttpsError(
        'failed-precondition', 'Sale product inventory value is corrupt.',
      );
    }
    const nextQuantity = checkedMinorAdd(
      currentQuantity, -issued.quantity, 'Sale stock quantity',
    );
    if (nextQuantity < 0) {
      throw new HttpsError(
        'failed-precondition',
        'The sale would create negative stock for ' + productId + '.',
      );
    }
    const nextInventoryValue = checkedMinorAdd(
      currentInventoryValue, -issued.cost, 'Sale stock value',
    );
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

  const totalDebitMinorUnits = checkedMinorAdd(
    grandTotalMinorUnits, costTotalMinorUnits, 'Sale total debits',
  );
  const totalCreditMinorUnits = checkedMinorAdd(
    checkedMinorAdd(
      subtotalMinorUnits, command.sale.taxMinorUnits, 'Sale sales + tax',
    ),
    costTotalMinorUnits, 'Sale total credits',
  );
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
        lineNumber: journalLines.length + 2,
        debitMinorUnits: zero,
        creditMinorUnits: costTotalMinorUnits,
      },
    );
  }

  const saleData = {
    storeId: command.storeId,
    idempotencyKey: command.sale.idempotencyKey,
    requestFingerprint: fingerprint,
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
        currency: command.sale.currency,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.sale.postedAt),
      },
    );
  }

  if (isCreditSale) {
    const prior = readPartyBalanceForPosting(
      customerBalanceSnapshot, {
        storeId: command.storeId,
        partyId: command.sale.customerId,
        partyType: 'customer',
        currency: command.sale.currency,
      },
    );
    const nextDebit = checkedMinorAdd(
      prior.debit, grandTotalMinorUnits, 'Sale customer receivable',
    );
    const nextCredit = prior.credit;
    const nextPartyNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Sale customer net receivable',
    );

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
        balanceMinorUnits: nextPartyNet,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  for (const accountId of accountIds) {
    const prior = readBalanceForPosting(
      balanceSnapshots.get(accountId), {
        storeId: command.storeId,
        accountId,
        currency: command.sale.currency,
      },
    );
    // Optional tax and service-only COGS accounts can legitimately have
    // no posting delta, but existing balances must still validate.
    const delta = accountDeltas.get(accountId) || { debit: 0, credit: 0 };
    const nextDebit = checkedMinorAdd(
      prior.debit, delta.debit, 'Sale GL account debit',
    );
    const nextCredit = checkedMinorAdd(
      prior.credit, delta.credit, 'Sale GL account credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Sale GL account net',
    );
    transaction.set(
      balanceRefs.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.sale.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
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
      requestFingerprint: fingerprint,
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

function paymentAccountControlType(paymentMethod, partyType) {
  switch (paymentMethod) {
    case 'cash':
      return 'cashBox';
    case 'bank':
      return 'bank';
    case 'card':
      return 'cardReceivable';
    case 'cheque':
      return partyType === 'supplier' ? 'checksPayable' : 'checks';
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


function parseChequeSettlementCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const action = stringValue(command.action, 'action');
  if (action !== 'clear' && action !== 'bounce') {
    invalid('Unsupported cheque settlement action.');
  }
  const accounts = asObject(command.accounts, 'accounts');
  const checksAccountId = safeId(
    accounts.checksAccountId,
    'checksAccountId',
  );
  const issuedChecksAccountId = safeId(
    accounts.issuedChecksAccountId,
    'issuedChecksAccountId',
  );
  const customerReceivableAccountId = safeId(
    accounts.customerReceivableAccountId,
    'customerReceivableAccountId',
  );
  const supplierPayableAccountId = safeId(
    accounts.supplierPayableAccountId,
    'supplierPayableAccountId',
  );
  const bankAccountId = action === 'clear'
    ? safeId(accounts.bankAccountId, 'bankAccountId')
    : null;
  const accountIds = [
    checksAccountId,
    issuedChecksAccountId,
    customerReceivableAccountId,
    supplierPayableAccountId,
    bankAccountId,
  ].filter((accountId) => accountId != null);
  if (new Set(accountIds).size !== accountIds.length) {
    invalid('Cheque settlement accounts must be different.');
  }
  return {
    storeId: safeId(command.storeId, 'storeId'),
    chequeId: safeId(command.chequeId, 'chequeId'),
    action,
    idempotencyKey: safeId(command.idempotencyKey, 'idempotencyKey'),
    postedAt: parseDate(command.postedAt, 'postedAt'),
    accounts: {
      checksAccountId,
      issuedChecksAccountId,
      customerReceivableAccountId,
      supplierPayableAccountId,
      bankAccountId,
    },
  };
}

exports.settleCheque = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseChequeSettlementCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return settleChequeInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('settleCheque failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The cheque could not be settled.',
    );
  }
});

async function settleChequeInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const chequeRef = storeRef.collection('party_payments').doc(command.chequeId);
  const settlementIdempotencyRef = storeRef
    .collection('cheque_settlement_idempotency')
    .doc(command.idempotencyKey);
  const journalEntryId = command.chequeId + '-cheque-' + command.action;
  const journalIdempotencyKey = command.idempotencyKey + ':journal';
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
    'settle cheques',
    PAYMENT_POSTING_ROLES,
  );
  const fingerprint = fingerprintChequeSettlement(command);
  const idempotencySnapshot = await transaction.get(settlementIdempotencyRef);
  if (idempotencySnapshot.exists) {
    const existing = idempotencySnapshot.data();
    if (existing.chequeId !== command.chequeId ||
        existing.action !== command.action ||
        existing.journalEntryId !== journalEntryId) {
      conflict('The cheque settlement idempotency key is already assigned.');
    }
    if (existing.requestFingerprint != null) {
      if (existing.requestFingerprint !== fingerprint) {
        conflict('Cheque settlement retry changed its financial details.');
      }
    } else {
      const previousCheque = await transaction.get(chequeRef);
      const previousJournal = await transaction.get(journalRef);
      const previousMarker = await transaction.get(journalIdempotencyRef);
      if (!previousCheque.exists || !previousJournal.exists ||
          !previousMarker.exists ||
          previousMarker.data().entryId !== journalEntryId ||
          !sameLegacyChequeSettlement(
            previousJournal.data(), previousCheque.data(),
            command, journalEntryId,
          )) {
        conflict('Cannot confirm old cheque settlement for retry.');
      }
      const previousLines = await transaction.get(journalRef.collection('lines'));
      if (!sameLegacyChequeLines(
        previousLines, previousCheque.data(), command, journalEntryId,
      )) {
        conflict('Historical cheque journal differs from settlement request.');
      }
    }
    return {
      status: command.action === 'clear' ? 'cleared' : 'bounced',
      chequeId: command.chequeId,
      journalEntryId,
    };
  }

  const chequeSnapshot = await transaction.get(chequeRef);
  if (!chequeSnapshot.exists) {
    invalid('Cheque was not found.');
  }
  const cheque = chequeSnapshot.data();
  if (cheque.storeId !== command.storeId) {
    deny('Cheque belongs to another store.');
  }
  if (cheque.paymentMethod !== 'cheque' ||
      (cheque.partyType !== 'customer' &&
       cheque.partyType !== 'supplier')) {
    invalid('Only customer and supplier cheques can be settled here.');
  }
  if (cheque.status !== 'pending') {
    conflict('The cheque is already settled.');
  }

  const existingJournalSnapshot = await transaction.get(journalRef);
  if (existingJournalSnapshot.exists) {
    conflict('The cheque settlement journal already exists.');
  }
  const existingJournalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (existingJournalIdempotencySnapshot.exists) {
    conflict('The cheque settlement journal idempotency key already exists.');
  }

  const isCustomerCheque = cheque.partyType === 'customer';
  const heldChequeAccountId = isCustomerCheque
    ? command.accounts.checksAccountId
    : command.accounts.issuedChecksAccountId;
  const counterpartyAccountId = command.action === 'clear'
    ? command.accounts.bankAccountId
    : isCustomerCheque
        ? command.accounts.customerReceivableAccountId
        : command.accounts.supplierPayableAccountId;
  const accountIds = [heldChequeAccountId, counterpartyAccountId];
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

  const amount = storedInt(cheque.amountMinorUnits, 0);
  if (amount <= 0) {
    invalid('Cheque amount is invalid.');
  }
  assertAccount(
    accountSnapshots.get(heldChequeAccountId),
    heldChequeAccountId,
    command.storeId,
    cheque.currency,
    isCustomerCheque ? 'asset' : 'liability',
    isCustomerCheque ? 'checks' : 'checksPayable',
  );
  if (command.action === 'clear') {
    assertAccount(
      accountSnapshots.get(command.accounts.bankAccountId),
      command.accounts.bankAccountId,
      command.storeId,
      cheque.currency,
      'asset',
      'bank',
    );
  } else {
    assertAccount(
      accountSnapshots.get(counterpartyAccountId),
      counterpartyAccountId,
      command.storeId,
      cheque.currency,
      isCustomerCheque ? 'asset' : 'liability',
      isCustomerCheque ? 'customerReceivable' : 'supplierPayable',
    );
  }

  let bouncedPartyLedgerRef;
  let bouncedPartyBalanceRef;
  let bouncedPartyBalance = {};
  if (command.action === 'bounce') {
    const partyLedgerId = command.chequeId + '-bounce';
    bouncedPartyLedgerRef = storeRef
      .collection('party_ledger_entries')
      .doc(partyLedgerId);
    bouncedPartyBalanceRef = storeRef
      .collection('party_balances')
      .doc(cheque.partyType + '-' + cheque.partyId);
    const bouncedLedgerSnapshot = await transaction.get(
      bouncedPartyLedgerRef,
    );
    if (bouncedLedgerSnapshot.exists) {
      conflict('The bounced cheque ledger entry already exists.');
    }
    const bouncedBalanceSnapshot = await transaction.get(
      bouncedPartyBalanceRef,
    );
    bouncedPartyBalance = readPartyBalanceForPosting(
      bouncedBalanceSnapshot,
      {
        storeId: command.storeId,
        partyType: cheque.partyType,
        partyId: cheque.partyId,
        currency: cheque.currency,
      },
    );
  }

  const debitAccountId = isCustomerCheque
    ? command.action === 'clear'
        ? command.accounts.bankAccountId
        : command.accounts.customerReceivableAccountId
    : heldChequeAccountId;
  const creditAccountId = isCustomerCheque
    ? heldChequeAccountId
    : command.action === 'clear'
        ? command.accounts.bankAccountId
        : command.accounts.supplierPayableAccountId;
  const journalLines = [
    {
      id: journalEntryId + '-debit',
      storeId: command.storeId,
      accountId: debitAccountId,
      description: command.action === 'clear'
        ? isCustomerCheque
            ? 'Incoming cheque deposited to bank'
            : 'Issued cheque paid through bank'
        : isCustomerCheque
            ? 'Bounced cheque returned to customer receivable'
            : 'Bounced supplier cheque returned to payable',
      lineNumber: 1,
      debitMinorUnits: amount,
      creditMinorUnits: 0,
    },
    {
      id: journalEntryId + '-credit',
      storeId: command.storeId,
      accountId: creditAccountId,
      description: isCustomerCheque
        ? 'Incoming cheque settlement'
        : 'Issued cheque settlement',
      lineNumber: 2,
      debitMinorUnits: 0,
      creditMinorUnits: amount,
    },
  ];

  const deltas = new Map();
  addDelta(deltas, debitAccountId, amount, 0);
  addDelta(deltas, creditAccountId, 0, amount);

  transaction.update(chequeRef, {
    status: command.action === 'clear' ? 'cleared' : 'bounced',
    settlementJournalEntryId: journalEntryId,
    settledAt: Timestamp.fromDate(command.postedAt),
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(journalRef, {
    storeId: command.storeId,
    idempotencyKey: journalIdempotencyKey,
    sourceType: command.action === 'clear'
      ? 'chequeClearance'
      : 'chequeBounce',
    description: cheque.description || 'Cheque settlement',
    status: 'posted',
    currency: cheque.currency,
    totalDebitMinorUnits: amount,
    totalCreditMinorUnits: amount,
    postedAt: Timestamp.fromDate(command.postedAt),
  });
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        postedAt: Timestamp.fromDate(command.postedAt),
        currency: cheque.currency,
      },
    );
  }

  if (command.action === 'bounce') {
    const partyDebit = isCustomerCheque ? amount : 0;
    const partyCredit = isCustomerCheque ? 0 : amount;
    const nextPartyDebit = checkedMinorAdd(
      bouncedPartyBalance.debit, partyDebit, 'Bounced cheque party debit',
    );
    const nextPartyCredit = checkedMinorAdd(
      bouncedPartyBalance.credit, partyCredit, 'Bounced cheque party credit',
    );
    const nextPartyNet = checkedMinorAdd(
      nextPartyDebit, -nextPartyCredit, 'Bounced cheque party net',
    );
    transaction.set(bouncedPartyLedgerRef, {
      storeId: command.storeId,
      partyType: cheque.partyType,
      partyId: cheque.partyId,
      sourceType: 'chequeBounce',
      sourceId: command.chequeId,
      currency: cheque.currency,
      debitMinorUnits: partyDebit,
      creditMinorUnits: partyCredit,
      description: isCustomerCheque
        ? 'Bounced cheque returned to customer receivable'
        : 'Bounced supplier cheque returned to payable',
      postedAt: Timestamp.fromDate(command.postedAt),
    });
    transaction.set(bouncedPartyBalanceRef, {
      storeId: command.storeId,
      partyType: cheque.partyType,
      partyId: cheque.partyId,
      currency: cheque.currency,
      debitMinorUnits: nextPartyDebit,
      creditMinorUnits: nextPartyCredit,
      balanceMinorUnits: nextPartyNet,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  for (const accountId of accountIds) {
    const previous = readBalanceForPosting(
      balanceSnapshots.get(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: cheque.currency,
      },
    );
    const delta = deltas.get(accountId);
    const nextDebit = checkedMinorAdd(
      previous.debit, delta.debit, 'Cheque settlement GL debit',
    );
    const nextCredit = checkedMinorAdd(
      previous.credit, delta.credit, 'Cheque settlement GL credit',
    );
    const nextNet = checkedMinorAdd(
      nextDebit, -nextCredit, 'Cheque settlement GL net',
    );
    transaction.set(
      storeRef.collection('account_balances').doc(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: cheque.currency,
        debitMinorUnits: nextDebit,
        creditMinorUnits: nextCredit,
        balanceMinorUnits: nextNet,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.set(settlementIdempotencyRef, {
    storeId: command.storeId,
    chequeId: command.chequeId,
    action: command.action,
    journalEntryId,
    idempotencyKey: command.idempotencyKey,
    requestFingerprint: fingerprint,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(journalIdempotencyRef, {
    storeId: command.storeId,
    entryId: journalEntryId,
    idempotencyKey: journalIdempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: command.action === 'clear' ? 'cleared' : 'bounced',
    chequeId: command.chequeId,
    journalEntryId,
  };
}


exports.auditAccountingIntegrity = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }

  const command = parseAccountingAuditCommand(request.data);

  try {
    return await runAccountingIntegrityAudit(
      request.auth.uid,
      command,
    );
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('auditAccountingIntegrity failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The accounting integrity audit could not be completed.',
    );
  }
});

function parseAccountingAuditCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  return {
    storeId: safeId(command.storeId, 'storeId'),
  };
}

async function runAccountingIntegrityAudit(userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const membershipSnapshot = await storeRef
    .collection('members')
    .doc(userId)
    .get();
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'run accounting audits',
    new Set(['owner', 'admin', 'accountant']),
  );

  // Read all pages from direct store-scoped collections. A read-only audit
  // must not silently skip later documents or confuse invoice lines with GL.
  const collectionNames = [
    'accounts',
    'account_balances',
    'journal_entries',
    'parties',
    'party_balances',
    'party_ledger_entries',
    'products',
    'inventory_movements',
  ];
  const scans = new Map();
  let scannedDocuments = 0;
  let scanIncomplete = false;
  for (const name of collectionNames) {
    if (scanIncomplete) {
      scans.set(name, {docs: [], size: 0, truncated: true});
      continue;
    }
    const remaining = MAX_AUDIT_TOTAL_DOCS - scannedDocuments;
    const snapshot = await readAuditPages(
      storeRef.collection(name), {
        maxDocuments: Math.min(MAX_AUDIT_DOCS_PER_COLLECTION, remaining),
      },
    );
    scans.set(name, snapshot);
    scannedDocuments += snapshot.size;
    scanIncomplete = snapshot.truncated;
  }

  const accountsSnapshot = scans.get('accounts');
  const accountBalancesSnapshot = scans.get('account_balances');
  const journalEntriesSnapshot = scans.get('journal_entries');
  const partiesSnapshot = scans.get('parties');
  const partyBalancesSnapshot = scans.get('party_balances');
  const partyLedgerSnapshot = scans.get('party_ledger_entries');
  const productsSnapshot = scans.get('products');
  const inventoryMovementsSnapshot = scans.get('inventory_movements');
  // Directly scan every journal's own lines. Unlike collectionGroup where
  // storeId is indexed, this detects malformed/missing line.storeId as well.
  const journalLinesSnapshot = scanIncomplete
    ? {docs: [], size: 0, truncated: true}
    : await readJournalAuditLines(journalEntriesSnapshot.docs, {
      maxDocuments: Math.min(
        MAX_AUDIT_DOCS_PER_COLLECTION,
        MAX_AUDIT_TOTAL_DOCS - scannedDocuments,
      ),
    });

  const issues = [];
  let totalIssueCount = 0;
  let totalErrorCount = 0;
  const addIssue = ({
    code,
    scope,
    referenceId,
    message,
    severity = 'error',
    valueKind,
    currency,
    expected,
    actual,
  }) => {
    totalIssueCount += 1;
    if (severity === 'error') totalErrorCount += 1;
    if (issues.length >= 200) {
      return;
    }
    issues.push({
      code,
      scope,
      referenceId,
      message,
      severity,
      valueKind: valueKind || null,
      currency: currency || null,
      expected: Number.isSafeInteger(expected) ? expected : null,
      actual: Number.isSafeInteger(actual) ? actual : null,
    });
  };

  const sources = {
    accounts: accountsSnapshot,
    balances: accountBalancesSnapshot,
    journals: journalEntriesSnapshot,
    ledgerLines: journalLinesSnapshot,
    parties: partiesSnapshot,
    partyBalances: partyBalancesSnapshot,
    partyMovements: partyLedgerSnapshot,
    products: productsSnapshot,
    stockMovements: inventoryMovementsSnapshot,
  };
  const truncated = Object.entries(sources)
    .filter(([, snapshot]) => snapshot.truncated)
    .map(([name]) => name);
  if (truncated.length > 0) {
    return {
      status: 'incomplete',
      complete: false,
      consistency: 'non_atomic',
      storeId: command.storeId,
      generatedAt: new Date().toISOString(),
      checked: {
        accounts: accountsSnapshot.size,
        journalEntries: journalEntriesSnapshot.size,
        journalLines: journalLinesSnapshot.size,
        parties: partiesSnapshot.size,
        partyLedgerEntries: partyLedgerSnapshot.size,
        products: productsSnapshot.size,
        inventoryMovements: inventoryMovementsSnapshot.size,
      },
      issueCount: 1,
      issues: [{
        code: 'AUDIT_INCOMPLETE_DATASET',
        scope: 'audit',
        referenceId: truncated.join(','),
        message: 'Data exceeds audit safety limit: no conclusion can be drawn.',
        severity: 'error',
        valueKind: null,
        currency: null,
        expected: null,
        actual: null,
      }],
    };
  }
  const readMinor = (value, scope, referenceId, allowNegative = false) =>
    auditInteger(value, {scope, referenceId}, addIssue, {allowNegative});
  const addMinor = (x, y, scope, referenceId, valueKind) =>
    auditSum(x, y, {scope, referenceId, valueKind}, addIssue);

  const accountMap = new Map();
  for (const document of accountsSnapshot.docs) {
    const data = document.data();
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'ACCOUNT_STORE_MISMATCH',
        scope: 'account',
        referenceId: document.id,
        message: 'الحساب مربوط بمتجر آخر أو بلا متجر صحيح.',
      });
      continue;
    }
    accountMap.set(document.id, data);
  }

  const accountTotals = new Map();
  const ensureAccountTotal = (accountId, currency) => {
    const existing = accountTotals.get(accountId);
    if (existing) {
      if (existing.currency !== currency) {
        addIssue({
          code: 'ACCOUNT_MULTI_CURRENCY',
          scope: 'account',
          referenceId: accountId,
          message: 'الحساب استُخدم بأكثر من عملة.',
          currency: currency,
        });
      }
      return existing;
    }
    const created = {
      debit: 0,
      credit: 0,
      currency,
    };
    accountTotals.set(accountId, created);
    return created;
  };

  const linesByEntry = new Map();
  for (const document of journalLinesSnapshot.docs) {
    if (!isJournalLinePath(document.ref, command.storeId)) {
      // Collection-group also contains sale and purchase invoice lines.
      continue;
    }
    const data = document.data();
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'JOURNAL_LINE_STORE_MISMATCH',
        scope: 'journalLine',
        referenceId: document.id,
        message: 'سطر القيد مربوط بمتجر آخر أو بلا متجر صحيح.',
      });
      continue;
    }

    const parentEntryId = document.ref.parent.parent.id;
    if (data.entryId !== parentEntryId) {
      addIssue({
        code: 'ORPHAN_JOURNAL_LINE',
        scope: 'journalLine',
        referenceId: document.id,
        message: 'سطر قيد بلا قيد أب معروف.',
      });
      continue;
    }

    const lineList = linesByEntry.get(parentEntryId) || [];
    lineList.push({id: document.id, data});
    linesByEntry.set(parentEntryId, lineList);
  }

  for (const document of journalEntriesSnapshot.docs) {
    const entry = document.data();
    const entryId = document.id;
    if (entry.storeId !== command.storeId) {
      addIssue({
        code: 'JOURNAL_STORE_MISMATCH',
        scope: 'journal',
        referenceId: entryId,
        message: 'Journal header is assigned to a different store.',
      });
    }
    const currency = typeof entry.currency === 'string'
      ? entry.currency
      : 'ILS';
    const lines = linesByEntry.get(entryId) || [];
    let totalDebit = 0;
    let totalCredit = 0;

    if (lines.length === 0) {
      addIssue({
        code: 'JOURNAL_WITHOUT_LINES',
        scope: 'journal',
        referenceId: entryId,
        message: 'القيد لا يحتوي على أي سطر دفتر.',
      });
    }

    for (const line of lines) {
      const data = line.data;
      const debit = readMinor(data.debitMinorUnits, 'journalLine', line.id);
      const credit = readMinor(data.creditMinorUnits, 'journalLine', line.id);
      totalDebit = addMinor(totalDebit, debit, 'journal', entryId);
      totalCredit = addMinor(totalCredit, credit, 'journal', entryId);

      if ((debit === 0) === (credit === 0)) {
        addIssue({
          code: 'INVALID_JOURNAL_LINE_SIDE',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'سطر القيد لا يحتوي على طرف واحد موجب فقط.',
          valueKind: 'minorUnits',
          currency,
          expected: 1,
          actual: 0,
        });
      }

      if (data.entryId && data.entryId !== entryId) {
        addIssue({
          code: 'JOURNAL_LINE_PARENT_MISMATCH',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'السطر يشير إلى قيد أب مختلف.',
        });
      }

      if (data.currency && data.currency !== currency) {
        addIssue({
          code: 'JOURNAL_LINE_CURRENCY_MISMATCH',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'عملة سطر القيد تختلف عن عملة القيد.',
        });
      }

      const accountId = data.accountId;
      if (typeof accountId !== 'string' || accountId.trim() === '') {
        addIssue({
          code: 'JOURNAL_LINE_ACCOUNT_MISSING',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'سطر القيد بلا حساب.',
        });
        continue;
      }

      const account = accountMap.get(accountId);
      if (!account) {
        addIssue({
          code: 'JOURNAL_LINE_ACCOUNT_NOT_FOUND',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'سطر القيد يشير إلى حساب غير موجود.',
        });
      } else if (account.currency !== currency) {
        addIssue({
          code: 'JOURNAL_LINE_ACCOUNT_CURRENCY_MISMATCH',
          scope: 'journalLine',
          referenceId: line.id,
          message: 'عملة حساب الأستاذ لا تطابق عملة القيد.',
          currency,
        });
      }

      const total = ensureAccountTotal(
        accountId,
        data.currency || currency,
      );
      total.debit = addMinor(total.debit, debit, 'accountBalance', accountId);
      total.credit = addMinor(total.credit, credit, 'accountBalance', accountId);
    }

    const headerDebit = readMinor(
      entry.totalDebitMinorUnits, 'journal', entryId,
    );
    const headerCredit = readMinor(
      entry.totalCreditMinorUnits, 'journal', entryId,
    );
    if (totalDebit !== headerDebit) {
      addIssue({
        code: 'JOURNAL_HEADER_TOTAL_MISMATCH',
        scope: 'journal',
        referenceId: entryId,
        message: 'إجمالي المدين في القيد لا يطابق مجموع سطوره.',
        valueKind: 'minorUnits',
        currency,
        expected: totalDebit,
        actual: headerDebit,
      });
    }
    if (totalCredit !== headerCredit) {
      addIssue({
        code: 'JOURNAL_HEADER_CREDIT_MISMATCH',
        scope: 'journal',
        referenceId: entryId,
        message: 'إجمالي الدائن في القيد لا يطابق مجموع سطوره.',
        valueKind: 'minorUnits',
        currency,
        expected: totalCredit,
        actual: headerCredit,
      });
    }

    if (totalDebit <= 0 || totalDebit !== totalCredit) {
      addIssue({
        code: 'UNBALANCED_JOURNAL',
        scope: 'journal',
        referenceId: entryId,
        message: 'القيد غير متوازن أو قيمته تساوي صفراً.',
        valueKind: 'minorUnits',
        currency,
        expected: totalDebit,
        actual: totalCredit,
      });
    }
  }

  const journalEntryIds = new Set(
    journalEntriesSnapshot.docs.map((document) => document.id),
  );
  for (const [entryId] of linesByEntry) {
    if (!journalEntryIds.has(entryId)) {
      addIssue({
        code: 'ORPHAN_JOURNAL_LINE',
        scope: 'journal',
        referenceId: entryId,
        message: 'توجد سطور دفتر لقيد غير موجود.',
      });
    }
  }

  const storedAccountBalances = new Map();
  for (const document of accountBalancesSnapshot.docs) {
    const data = document.data();
    const accountId = document.id;
    if (data.storeId !== command.storeId || data.accountId !== accountId) {
      addIssue({
        code: 'ACCOUNT_BALANCE_IDENTITY_MISMATCH',
        scope: 'accountBalance',
        referenceId: document.id,
        message: 'Balance projection has a wrong store or account identity.',
      });
    }
    storedAccountBalances.set(accountId, data);
  }

  const allAccountIds = new Set([
    ...accountMap.keys(),
    ...accountTotals.keys(),
    ...storedAccountBalances.keys(),
  ]);
  for (const accountId of allAccountIds) {
    const account = accountMap.get(accountId);
    const expected = accountTotals.get(accountId) || {
      debit: 0,
      credit: 0,
      currency: account && account.currency
        ? account.currency
        : 'ILS',
    };
    const stored = storedAccountBalances.get(accountId);
    if (!stored) {
      if (expected.debit !== 0 || expected.credit !== 0) {
        addIssue({
          code: 'ACCOUNT_BALANCE_MISSING',
          scope: 'accountBalance',
          referenceId: accountId,
          message: 'يوجد رصيد محاسبي متوقع بلا إسقاط مخزن.',
          valueKind: 'minorUnits',
          currency: expected.currency,
          expected: expected.debit - expected.credit,
          actual: 0,
        });
      }
      continue;
    }

    const storedCurrency = stored.currency || expected.currency;
    const storedDebit = readMinor(
      stored.debitMinorUnits, 'accountBalance', accountId,
    );
    const storedCredit = readMinor(
      stored.creditMinorUnits, 'accountBalance', accountId,
    );
    const storedBalance = readMinor(
      stored.balanceMinorUnits, 'accountBalance', accountId, true,
    );

    if (storedCurrency !== expected.currency) {
      addIssue({
        code: 'ACCOUNT_BALANCE_CURRENCY_MISMATCH',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'عملة إسقاط الحساب تختلف عن عملة حركته.',
      });
    }
    if (storedDebit !== expected.debit) {
      addIssue({
        code: 'ACCOUNT_DEBIT_MISMATCH',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'الرصيد المدين المخزن لا يطابق سطور القيود.',
        valueKind: 'minorUnits',
        currency: expected.currency,
        expected: expected.debit,
        actual: storedDebit,
      });
    }
    if (storedCredit !== expected.credit) {
      addIssue({
        code: 'ACCOUNT_CREDIT_MISMATCH',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'الرصيد الدائن المخزن لا يطابق سطور القيود.',
        valueKind: 'minorUnits',
        currency: expected.currency,
        expected: expected.credit,
        actual: storedCredit,
      });
    }
    if (storedBalance !== expected.debit - expected.credit) {
      addIssue({
        code: 'ACCOUNT_NET_BALANCE_MISMATCH',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'الرصيد الصافي المخزن لا يطابق المدين ناقص الدائن.',
        valueKind: 'minorUnits',
        currency: expected.currency,
        expected: expected.debit - expected.credit,
        actual: storedBalance,
      });
    }
    if (account && account.isHeader === true &&
        (storedDebit !== 0 || storedCredit !== 0)) {
      addIssue({
        code: 'HEADER_ACCOUNT_HAS_BALANCE',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'حساب التجميع يحتوي على حركة مباشرة.',
        severity: 'warning',
        valueKind: 'minorUnits',
        currency: storedCurrency,
        expected: 0,
        actual: storedBalance,
      });
    }
  }

  const partyMap = new Map();
  for (const document of partiesSnapshot.docs) {
    const data = document.data();
    const partyId = document.id;
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'PARTY_STORE_MISMATCH',
        scope: 'party',
        referenceId: partyId,
        message: 'الطرف مربوط بمتجر آخر أو بلا متجر صحيح.',
      });
      continue;
    }
    partyMap.set(
      (data.partyType || '') + ':' + partyId,
      data,
    );
  }

  const partyTotals = new Map();
  const ensurePartyTotal = (partyType, partyId, currency) => {
    const key = partyType + ':' + partyId;
    const existing = partyTotals.get(key);
    if (existing) {
      if (existing.currency !== currency) {
        addIssue({
          code: 'PARTY_MULTI_CURRENCY',
          scope: 'partyLedger',
          referenceId: key,
          message: 'Party movements have conflicting currency codes.',
        });
      }
      return existing;
    }
    const created = {
      partyType,
      partyId,
      debit: 0,
      credit: 0,
      currency,
    };
    partyTotals.set(key, created);
    return created;
  };

  for (const document of partyLedgerSnapshot.docs) {
    const data = document.data();
    const partyType = data.partyType;
    const partyId = data.partyId;
    const currency = data.currency || 'ILS';
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'PARTY_LEDGER_STORE_MISMATCH',
        scope: 'partyLedger',
        referenceId: document.id,
        message: 'Party ledger entry belongs to another store.',
      });
    }
    if (!partyType || !partyId) {
      addIssue({
        code: 'PARTY_LEDGER_ID_MISSING',
        scope: 'partyLedger',
        referenceId: document.id,
        message: 'حركة الطرف بلا نوع طرف أو معرف طرف.',
      });
      continue;
    }
    const total = ensurePartyTotal(partyType, partyId, currency);
    total.debit = addMinor(
      total.debit,
      readMinor(data.debitMinorUnits, 'partyLedger', document.id),
      'partyBalance', partyType + ':' + partyId,
    );
    total.credit = addMinor(
      total.credit,
      readMinor(data.creditMinorUnits, 'partyLedger', document.id),
      'partyBalance', partyType + ':' + partyId,
    );

    if (!partyMap.has(partyType + ':' + partyId)) {
      addIssue({
        code: 'PARTY_LEDGER_PARTY_NOT_FOUND',
        scope: 'partyLedger',
        referenceId: document.id,
        message: 'حركة الطرف تشير إلى عميل أو مورد غير موجود.',
      });
    }
  }

  const storedPartyBalances = new Map();
  for (const document of partyBalancesSnapshot.docs) {
    const data = document.data();
    const partyType = data.partyType;
    const partyId = data.partyId;
    if (!partyType || !partyId) {
      addIssue({
        code: 'PARTY_BALANCE_ID_MISSING',
        scope: 'partyBalance',
        referenceId: document.id,
        message: 'إسقاط الطرف بلا نوع أو معرف طرف.',
      });
      continue;
    }
    if (data.storeId !== command.storeId ||
        document.id !== partyType + '-' + partyId) {
      addIssue({
        code: 'PARTY_BALANCE_IDENTITY_MISMATCH',
        scope: 'partyBalance',
        referenceId: document.id,
        message: 'Party projection store or document identity does not match.',
      });
    }
    storedPartyBalances.set(partyType + ':' + partyId, data);
  }

  const allPartyKeys = new Set([
    ...partyTotals.keys(),
    ...storedPartyBalances.keys(),
  ]);
  for (const key of allPartyKeys) {
    const expected = partyTotals.get(key) || {
      debit: 0,
      credit: 0,
      currency: 'ILS',
    };
    const stored = storedPartyBalances.get(key);
    if (!stored) {
      if (expected.debit !== 0 || expected.credit !== 0) {
        addIssue({
          code: 'PARTY_BALANCE_MISSING',
          scope: 'partyBalance',
          referenceId: key,
          message: 'يوجد كشف طرف متوقع بلا رصيد مخزن.',
          valueKind: 'minorUnits',
          currency: expected.currency,
          expected: expected.debit - expected.credit,
          actual: 0,
        });
      }
      continue;
    }

    if (stored.currency !== expected.currency) {
      addIssue({
        code: 'PARTY_BALANCE_CURRENCY_MISMATCH',
        scope: 'partyBalance',
        referenceId: key,
        message: 'Party projection currency does not match movement currency.',
      });
    }
    const storedDebit = readMinor(
      stored.debitMinorUnits, 'partyBalance', key,
    );
    const storedCredit = readMinor(
      stored.creditMinorUnits, 'partyBalance', key,
    );
    const storedBalance = readMinor(
      stored.balanceMinorUnits, 'partyBalance', key, true,
    );
    if (storedDebit !== expected.debit ||
        storedCredit !== expected.credit ||
        storedBalance !== storedDebit - storedCredit ||
        storedBalance !== expected.debit - expected.credit) {
      addIssue({
        code: 'PARTY_BALANCE_MISMATCH',
        scope: 'partyBalance',
        referenceId: key,
        message: 'رصيد الطرف المخزن لا يطابق دفتر حركته.',
        valueKind: 'minorUnits',
        currency: expected.currency,
        expected: expected.debit - expected.credit,
        actual: storedBalance,
      });
    }
  }

  const productMap = new Map();
  for (const document of productsSnapshot.docs) {
    const data = document.data();
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'PRODUCT_STORE_MISMATCH',
        scope: 'inventory',
        referenceId: document.id,
        message: 'Product is attached to a different store.',
      });
      continue;
    }
    productMap.set(document.id, data);
  }

  const inventoryTotals = new Map();
  for (const document of inventoryMovementsSnapshot.docs) {
    const data = document.data();
    const productId = data.productId;
    if (data.storeId !== command.storeId) {
      addIssue({
        code: 'INVENTORY_MOVEMENT_STORE_MISMATCH',
        scope: 'inventoryMovement',
        referenceId: document.id,
        message: 'Stock movement is attached to a different store.',
      });
    }
    if (!productId) {
      addIssue({
        code: 'INVENTORY_MOVEMENT_PRODUCT_MISSING',
        scope: 'inventoryMovement',
        referenceId: document.id,
        message: 'حركة المخزون بلا صنف.',
      });
      continue;
    }
    // A matching quantity/value total must never hide a currency conflict.
    // Older movements may omit currency; in that case use the product's
    // currency as a read-only comparison fallback, never an exchange rate.
    const hasMovementCurrency = Object.prototype.hasOwnProperty.call(
      data, 'currency',
    );
    const explicitCurrency = typeof data.currency === 'string' &&
        data.currency.trim() !== '' ? data.currency : null;
    if (hasMovementCurrency && !explicitCurrency) {
      addIssue({
        code: 'INVENTORY_MOVEMENT_CURRENCY_INVALID',
        scope: 'inventoryMovement',
        referenceId: document.id,
        message: 'Stock movement currency is malformed or empty.',
      });
    }
    const product = productMap.get(productId);
    if (product && explicitCurrency && explicitCurrency !== product.currency) {
      addIssue({
        code: 'INVENTORY_MOVEMENT_PRODUCT_CURRENCY_MISMATCH',
        scope: 'inventoryMovement',
        referenceId: document.id,
        message: 'Stock movement currency differs from product currency.',
        currency: explicitCurrency,
      });
    }
    const existingTotal = inventoryTotals.get(productId);
    // Missing legacy currency is unknown, NOT evidence of another currency.
    if (existingTotal && explicitCurrency &&
        existingTotal.observedCurrency &&
        existingTotal.observedCurrency !== explicitCurrency) {
      addIssue({
        code: 'INVENTORY_MOVEMENT_MULTI_CURRENCY',
        scope: 'inventoryMovement',
        referenceId: document.id,
        message: 'Stock movements of one product use multiple currencies.',
        currency: explicitCurrency,
      });
    }
    const total = existingTotal || {
      quantity: 0,
      value: 0,
      currency: explicitCurrency || (product && product.currency) || 'ILS',
      observedCurrency: null,
    };
    if (explicitCurrency && !total.observedCurrency) {
      total.observedCurrency = explicitCurrency;
    }
    const quantity = readMinor(
      data.quantityDeltaMilliUnits, 'inventoryMovement', document.id, true,
    );
    const value = readMinor(
      data.totalCostMinorUnits, 'inventoryMovement', document.id,
    );
    total.quantity = addMinor(
      total.quantity, quantity, 'inventory', productId, 'milliUnits',
    );
    total.value = addMinor(
      total.value, quantity < 0 ? -value : value,
      'inventory', productId,
    );
    inventoryTotals.set(productId, total);
  }

  for (const [productId, expected] of inventoryTotals) {
    const product = productMap.get(productId);
    if (!product) {
      addIssue({
        code: 'INVENTORY_PRODUCT_NOT_FOUND',
        scope: 'inventory',
        referenceId: productId,
        message: 'حركة المخزون تشير إلى صنف غير موجود.',
      });
      continue;
    }

    const actualQuantity = readMinor(
      product.quantityOnHandMilliUnits, 'inventory', productId,
    );
    const actualValue = readMinor(
      product.inventoryValueMinorUnits, 'inventory', productId,
    );
    if (actualQuantity !== expected.quantity) {
      addIssue({
        code: 'INVENTORY_QUANTITY_MISMATCH',
        scope: 'inventory',
        referenceId: productId,
        message: 'كمية الصنف لا تطابق مجموع حركات المخزون.',
        valueKind: 'milliUnits',
        expected: expected.quantity,
        actual: actualQuantity,
      });
    }
    if (actualValue !== expected.value) {
      addIssue({
        code: 'INVENTORY_VALUE_MISMATCH',
        scope: 'inventory',
        referenceId: productId,
        message: 'قيمة مخزون الصنف لا تطابق مجموع حركاته.',
        valueKind: 'minorUnits',
        currency: expected.currency,
        expected: expected.value,
        actual: actualValue,
      });
    }
  }

  // Detect stock that lacks documented movement/opening provenance, and
  // independently compare the product valuation projection with inventory GL.
  const productValues = new Map();
  for (const [productId, product] of productMap) {
    if (product.isService === true) continue;
    const currency = product.currency;
    if (typeof currency !== 'string' || !currency.trim()) {
      addIssue({
        code: 'PRODUCT_CURRENCY_INVALID',
        scope: 'inventory',
        referenceId: productId,
        message: 'Stock product currency is missing or invalid.',
      });
      continue;
    }
    const value = readMinor(
      product.inventoryValueMinorUnits, 'inventory', productId,
    );
    const quantity = readMinor(
      product.quantityOnHandMilliUnits, 'inventory', productId,
    );
    if (!inventoryTotals.has(productId) && (value !== 0 || quantity !== 0)) {
      addIssue({
        code: 'INVENTORY_OPENING_SOURCE_UNVERIFIED',
        scope: 'inventory',
        referenceId: productId,
        message: 'Stock has value or quantity without movement/opening evidence.',
        currency,
        valueKind: 'minorUnits',
        actual: value,
      });
    }
    productValues.set(currency, addMinor(
      productValues.get(currency) || 0, value, 'inventory', productId,
    ));
  }
  const glInventoryValues = new Map();
  for (const [accountId, account] of accountMap) {
    if (account.controlType !== 'inventory' || account.isHeader === true) {
      continue;
    }
    const currency = account.currency;
    if (typeof currency !== 'string' || !currency.trim()) {
      addIssue({
        code: 'INVENTORY_GL_CURRENCY_INVALID',
        scope: 'accountBalance',
        referenceId: accountId,
        message: 'Inventory GL account currency is invalid.',
      });
      continue;
    }
    const projection = storedAccountBalances.get(accountId);
    const debit = projection
      ? readMinor(projection.debitMinorUnits, 'accountBalance', accountId) : 0;
    const credit = projection
      ? readMinor(projection.creditMinorUnits, 'accountBalance', accountId) : 0;
    const net = addMinor(debit, -credit, 'accountBalance', accountId);
    glInventoryValues.set(currency, addMinor(
      glInventoryValues.get(currency) || 0, net,
      'accountBalance', accountId,
    ));
  }
  const inventoryCurrencies = new Set([
    ...productValues.keys(), ...glInventoryValues.keys(),
  ]);
  for (const currency of inventoryCurrencies) {
    const productValue = productValues.get(currency) || 0;
    const ledgerValue = glInventoryValues.get(currency) || 0;
    if (productValue !== ledgerValue) {
      addIssue({
        code: 'INVENTORY_GL_VALUATION_MISMATCH',
        scope: 'inventory',
        referenceId: currency,
        message: 'Stock product valuations do not equal inventory GL net.',
        currency,
        valueKind: 'minorUnits',
        expected: ledgerValue,
        actual: productValue,
      });
    }
  }

  return {
    status: totalErrorCount > 0 ? 'issues_found' : 'healthy',
    complete: true,
    consistency: 'non_atomic',
    storeId: command.storeId,
    generatedAt: new Date().toISOString(),
    checked: {
      accounts: accountMap.size,
      journalEntries: journalEntriesSnapshot.size,
      journalLines: journalLinesSnapshot.size,
      parties: partyMap.size,
      partyLedgerEntries: partyLedgerSnapshot.size,
      products: productMap.size,
      inventoryMovements: inventoryMovementsSnapshot.size,
    },
    issueCount: totalIssueCount,
    errorCount: totalErrorCount,
    issuesTruncated: totalIssueCount > issues.length,
    issues,
  };
}


exports.createRepair = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseRepairCreateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return createRepairInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('createRepair failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError('internal', 'The repair could not be created.');
  }
});

exports.updateRepair = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseRepairUpdateCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return updateRepairInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('updateRepair failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError('internal', 'The repair could not be updated.');
  }
});

exports.deliverRepair = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseRepairDeliveryCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return deliverRepairInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('deliverRepair failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError('internal', 'The repair could not be delivered.');
  }
});

exports.postRepairAdvance = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseRepairPaymentCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return postRepairAdvanceInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postRepairAdvance failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The repair advance could not be posted.',
    );
  }
});

exports.postRepairPayment = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = parseRepairPaymentCommand(request.data);
  try {
    return await db.runTransaction(async (transaction) => {
      return postRepairPaymentInTransaction(
        transaction,
        request.auth.uid,
        command,
      );
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('postRepairPayment failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The repair payment could not be posted.',
    );
  }
});

function parseRepairCreateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const repair = parseRepairPayload(
    asObject(command.repair, 'repair'),
  );
  if (repair.status !== 'received') {
    invalid('A new repair must start with received status.');
  }
  return {storeId, repair};
}

function parseRepairUpdateCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const repairId = safeId(command.repairId, 'repairId');
  const repair = parseRepairPayload(
    asObject(command.repair, 'repair'),
  );
  if (repair.id !== repairId) {
    invalid('Repair id does not match the update target.');
  }
  if (repair.status === 'delivered') {
    invalid('Use the delivery command to complete a repair.');
  }
  return {storeId, repairId, repair};
}

function parseRepairDeliveryCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const rawAccounts = asObject(command.accounts, 'accounts');
  return {
    storeId: safeId(command.storeId, 'storeId'),
    repairId: safeId(command.repairId, 'repairId'),
    idempotencyKey: safeId(
      command.idempotencyKey,
      'idempotencyKey',
    ),
    postedAt: parseDate(command.postedAt, 'postedAt'),
    accounts: {
      customerReceivableAccountId: safeId(
        rawAccounts.customerReceivableAccountId,
        'customerReceivableAccountId',
      ),
      repairRevenueAccountId: safeId(
        rawAccounts.repairRevenueAccountId,
        'repairRevenueAccountId',
      ),
      inventoryAccountId: safeId(
        rawAccounts.inventoryAccountId,
        'inventoryAccountId',
      ),
      costOfSalesAccountId: safeId(
        rawAccounts.costOfSalesAccountId,
        'costOfSalesAccountId',
      ),
      customerAdvancesAccountId: safeId(
        rawAccounts.customerAdvancesAccountId,
        'customerAdvancesAccountId',
      ),
    },
  };
}

function parseRepairPaymentCommand(rawCommand) {
  const command = asObject(rawCommand, 'command');
  const rawPayment = asObject(command.payment, 'payment');
  const rawAccounts = asObject(
    command.postingAccounts,
    'postingAccounts',
  );
  const paymentMethod = stringValue(
    rawPayment.paymentMethod,
    'payment.paymentMethod',
  );
  if (!PARTY_PAYMENT_METHODS.has(paymentMethod)) {
    invalid('Unsupported repair payment method.');
  }

  return {
    storeId: safeId(command.storeId, 'storeId'),
    repairId: safeId(command.repairId, 'repairId'),
    payment: {
      id: safeId(rawPayment.id, 'payment id'),
      idempotencyKey: safeId(
        rawPayment.idempotencyKey,
        'payment idempotencyKey',
      ),
      postedAt: parseDate(rawPayment.postedAt, 'payment.postedAt'),
      paymentMethod,
      amountMinorUnits: positiveInt(
        rawPayment.amountMinorUnits,
        'payment.amountMinorUnits',
      ),
      currency: stringValue(rawPayment.currency, 'payment.currency'),
      description: rawPayment.description == null
        ? null
        : stringValue(rawPayment.description, 'payment.description'),
      chequeNumber: rawPayment.chequeNumber == null
        ? null
        : stringValue(rawPayment.chequeNumber, 'payment.chequeNumber'),
      bankName: rawPayment.bankName == null
        ? null
        : stringValue(rawPayment.bankName, 'payment.bankName'),
      dueDate: rawPayment.dueDate == null
        ? null
        : parseDate(rawPayment.dueDate, 'payment.dueDate'),
    },
    accounts: {
      settlementAccountId: safeId(
        rawAccounts.settlementAccountId,
        'settlementAccountId',
      ),
      customerReceivableAccountId: safeId(
        rawAccounts.customerReceivableAccountId,
        'customerReceivableAccountId',
      ),
      customerAdvancesAccountId: rawAccounts.customerAdvancesAccountId == null
        ? null
        : safeId(
          rawAccounts.customerAdvancesAccountId,
          'customerAdvancesAccountId',
        ),
    },
  };
}

function parseRepairPayload(rawRepair) {
  const rawParts = Array.isArray(rawRepair.parts)
    ? rawRepair.parts
    : [];
  if (rawParts.length > MAX_LINES) {
    invalid('A repair cannot contain more than 100 parts.');
  }

  const currency = stringValue(
    rawRepair.currency,
    'repair.currency',
  );
  const parts = rawParts.map((rawPart, index) => {
    const part = asObject(
      rawPart,
      'repair.parts[' + index + ']',
    );
    return {
      id: safeId(part.id, 'repair part id'),
      productId: safeId(part.productId, 'repair product id'),
      productName: stringValue(
        part.productName,
        'repair product name',
      ),
      quantityMilliUnits: positiveInt(
        part.quantityMilliUnits,
        'repair part quantityMilliUnits',
      ),
      unitPriceMinorUnits: nonNegativeInt(
        part.unitPriceMinorUnits,
        'repair part unitPriceMinorUnits',
      ),
      unitCostMinorUnits: nonNegativeInt(
        part.unitCostMinorUnits || 0,
        'repair part unitCostMinorUnits',
      ),
      source: part.source == null
        ? 'products'
        : stringValue(part.source, 'repair part source'),
    };
  });
  const partIds = new Set(parts.map((part) => part.id));
  if (partIds.size !== parts.length) {
    invalid('Repair part ids must be unique.');
  }

  const requiredParts = Array.isArray(rawRepair.requiredParts)
    ? rawRepair.requiredParts.map((value, index) => stringValue(
      value,
      'repair.requiredParts[' + index + ']',
    ))
    : [];
  const deviceImages = Array.isArray(rawRepair.deviceImages)
    ? rawRepair.deviceImages.map((value, index) => stringValue(
      value,
      'repair.deviceImages[' + index + ']',
    ))
    : [];
  const rawRequiredStatus = rawRepair.requiredPartsStatus;
  const requiredPartsStatus = {};
  if (rawRequiredStatus != null) {
    const statusObject = asObject(
      rawRequiredStatus,
      'repair.requiredPartsStatus',
    );
    for (const [key, value] of Object.entries(statusObject)) {
      requiredPartsStatus[stringValue(key, 'required part name')] =
        stringValue(value, 'required part status');
    }
  }

  return {
    id: safeId(rawRepair.id, 'repair id'),
    idempotencyKey: safeId(
      rawRepair.idempotencyKey,
      'repair idempotencyKey',
    ),
    customerId: safeId(rawRepair.customerId, 'repair customerId'),
    deviceName: stringValue(rawRepair.deviceName, 'repair deviceName'),
    deviceModel: stringValue(rawRepair.deviceModel, 'repair deviceModel'),
    problemDescription: optionalText(
      rawRepair.problemDescription,
      'repair.problemDescription',
    ),
    createdAt: parseDate(rawRepair.createdAt, 'repair.createdAt'),
    receivedAt: parseDate(rawRepair.receivedAt, 'repair.receivedAt'),
    expectedDeliveryDate: parseDate(
      rawRepair.expectedDeliveryDate,
      'repair.expectedDeliveryDate',
    ),
    status: rawRepair.status == null
      ? 'received'
      : stringValue(rawRepair.status, 'repair.status'),
    estimatedCostMinorUnits: nonNegativeInt(
      rawRepair.estimatedCostMinorUnits || 0,
      'repair.estimatedCostMinorUnits',
    ),
    laborCostMinorUnits: nonNegativeInt(
      rawRepair.laborCostMinorUnits || 0,
      'repair.laborCostMinorUnits',
    ),
    currency,
    technicianNotes: optionalText(
      rawRepair.technicianNotes,
      'repair.technicianNotes',
    ),
    serialNumber: optionalText(rawRepair.serialNumber, 'repair.serialNumber'),
    priority: rawRepair.priority == null
      ? 'normal'
      : stringValue(rawRepair.priority, 'repair.priority'),
    deviceCondition: rawRepair.deviceCondition == null
      ? 'notWorking'
      : stringValue(
        rawRepair.deviceCondition,
        'repair.deviceCondition',
      ),
    deviceConditionNotes: optionalText(
      rawRepair.deviceConditionNotes,
      'repair.deviceConditionNotes',
    ),
    requiredParts,
    requiredPartsStatus,
    deviceImages,
    parts,
  };
}

async function createRepairInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const repairRef = storeRef.collection('repairs').doc(command.repair.id);
  const idempotencyRef = storeRef
    .collection('repair_idempotency')
    .doc(command.repair.idempotencyKey);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'manage repairs',
    new Set(['owner', 'admin', 'accountant', 'sales']),
  );
  const [idempotencySnapshot, repairSnapshot, partySnapshot] =
    await Promise.all([
      transaction.get(idempotencyRef),
      transaction.get(repairRef),
      transaction.get(storeRef.collection('parties').doc(
        command.repair.customerId,
      )),
    ]);
  if (idempotencySnapshot.exists) {
    const data = idempotencySnapshot.data();
    if (data.repairId === command.repair.id) {
      return {
        status: 'already_created',
        repairId: command.repair.id,
      };
    }
    conflict('The repair idempotency key is already assigned.');
  }
  if (repairSnapshot.exists) {
    conflict('The repair id already exists.');
  }
  assertParty(
    partySnapshot,
    command.storeId,
    command.repair.customerId,
    'customer',
  );

  const parts = await canonicalRepairParts(
    transaction,
    storeRef,
    command.storeId,
    command.repair,
  );
  transaction.set(repairRef, repairDocument(
    command.storeId,
    command.repair,
    parts,
    userId,
  ));
  transaction.set(idempotencyRef, {
    storeId: command.storeId,
    repairId: command.repair.id,
    idempotencyKey: command.repair.idempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });
  return {status: 'created', repairId: command.repair.id};
}

async function updateRepairInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const repairRef = storeRef.collection('repairs').doc(command.repairId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'manage repairs',
    new Set(['owner', 'admin', 'accountant', 'sales']),
  );
  const repairSnapshot = await transaction.get(repairRef);
  if (!repairSnapshot.exists) {
    invalid('Repair request was not found.');
  }
  const existing = repairSnapshot.data();
  assertRepairTransition(existing.status || 'received', command.repair.status);
  if (existing.invoiceJournalEntryId) {
    invalid('An invoiced repair cannot be edited.');
  }

  const partySnapshot = await transaction.get(
    storeRef.collection('parties').doc(command.repair.customerId),
  );
  assertParty(
    partySnapshot,
    command.storeId,
    command.repair.customerId,
    'customer',
  );
  const parts = await canonicalRepairParts(
    transaction,
    storeRef,
    command.storeId,
    command.repair,
  );
  transaction.update(
    repairRef,
    repairEditableDocument(command.repair, parts),
  );
  return {status: 'updated', repairId: command.repairId};
}

async function canonicalRepairParts(
  transaction,
  storeRef,
  storeId,
  repair,
) {
  const productSnapshots = new Map();
  for (const part of repair.parts) {
    if (productSnapshots.has(part.productId)) {
      invalid('A repair cannot use the same product more than once.');
    }
    productSnapshots.set(
      part.productId,
      await transaction.get(
        storeRef.collection('products').doc(part.productId),
      ),
    );
  }

  return repair.parts.map((part) => {
    const productSnapshot = productSnapshots.get(part.productId);
    if (!productSnapshot.exists) {
      invalid('Repair product was not found: ' + part.productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== storeId) {
      deny('Repair product belongs to another store.');
    }
    if (product.isActive === false || product.isService === true) {
      invalid('Only active stock products can be used in a repair.');
    }
    const productCurrency = product.currency || 'ILS';
    if (productCurrency !== repair.currency) {
      invalid('Repair product currency does not match the repair.');
    }
    return {
      id: part.id,
      productId: part.productId,
      productName: product.name,
      quantityMilliUnits: part.quantityMilliUnits,
      unitPriceMinorUnits: part.unitPriceMinorUnits,
      unitCostMinorUnits: storedInt(
        product.purchasePriceMinorUnits,
        part.unitCostMinorUnits,
      ),
      currency: repair.currency,
      source: part.source,
    };
  });
}

function repairDocument(storeId, repair, parts, userId) {
  return {
    storeId,
    idempotencyKey: repair.idempotencyKey,
    customerId: repair.customerId,
    deviceName: repair.deviceName,
    deviceModel: repair.deviceModel,
    problemDescription: repair.problemDescription,
    createdAt: Timestamp.fromDate(repair.createdAt),
    receivedAt: Timestamp.fromDate(repair.receivedAt),
    expectedDeliveryDate: Timestamp.fromDate(repair.expectedDeliveryDate),
    status: 'received',
    estimatedCostMinorUnits: repair.estimatedCostMinorUnits,
    laborCostMinorUnits: repair.laborCostMinorUnits,
    currency: repair.currency,
    technicianNotes: repair.technicianNotes,
    serialNumber: repair.serialNumber,
    priority: repair.priority,
    deviceCondition: repair.deviceCondition,
    deviceConditionNotes: repair.deviceConditionNotes,
    requiredParts: repair.requiredParts,
    requiredPartsStatus: repair.requiredPartsStatus,
    deviceImages: repair.deviceImages,
    parts,
    advancePaidMinorUnits: 0,
    paidMinorUnits: 0,
    invoiceJournalEntryId: null,
    invoicedTotalMinorUnits: 0,
    costOfPartsMinorUnits: 0,
    createdBy: userId,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function repairEditableDocument(repair, parts) {
  return {
    customerId: repair.customerId,
    deviceName: repair.deviceName,
    deviceModel: repair.deviceModel,
    problemDescription: repair.problemDescription,
    receivedAt: Timestamp.fromDate(repair.receivedAt),
    expectedDeliveryDate: Timestamp.fromDate(repair.expectedDeliveryDate),
    status: repair.status,
    estimatedCostMinorUnits: repair.estimatedCostMinorUnits,
    laborCostMinorUnits: repair.laborCostMinorUnits,
    technicianNotes: repair.technicianNotes,
    serialNumber: repair.serialNumber,
    priority: repair.priority,
    deviceCondition: repair.deviceCondition,
    deviceConditionNotes: repair.deviceConditionNotes,
    requiredParts: repair.requiredParts,
    requiredPartsStatus: repair.requiredPartsStatus,
    deviceImages: repair.deviceImages,
    parts,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function assertRepairTransition(currentStatus, nextStatus) {
  const allowed = new Set([
    'received',
    'diagnosing',
    'inProgress',
    'ready',
    'cancelled',
  ]);
  if (!allowed.has(nextStatus)) {
    invalid('Unsupported repair status.');
  }
  if (currentStatus === 'delivered' || currentStatus === 'cancelled') {
    invalid('A completed or cancelled repair cannot be edited.');
  }
  const transitions = {
    received: new Set(['received', 'diagnosing', 'cancelled']),
    diagnosing: new Set(['diagnosing', 'inProgress', 'cancelled']),
    inProgress: new Set(['inProgress', 'ready', 'cancelled']),
    ready: new Set(['ready', 'inProgress', 'cancelled']),
  };
  if (!transitions[currentStatus] ||
      !transitions[currentStatus].has(nextStatus)) {
    invalid('Invalid repair status transition.');
  }
}

async function deliverRepairInTransaction(transaction, userId, command) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const repairRef = storeRef.collection('repairs').doc(command.repairId);
  const deliveryIdempotencyRef = storeRef
    .collection('repair_delivery_idempotency')
    .doc(command.idempotencyKey);
  const journalEntryId = command.repairId + '-invoice';
  const journalIdempotencyKey = command.idempotencyKey + ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'deliver repairs',
    new Set(['owner', 'admin', 'accountant', 'sales']),
  );

  const [
    deliveryIdempotencySnapshot,
    repairSnapshot,
    journalSnapshot,
    journalIdempotencySnapshot,
  ] = await Promise.all([
    transaction.get(deliveryIdempotencyRef),
    transaction.get(repairRef),
    transaction.get(journalRef),
    transaction.get(journalIdempotencyRef),
  ]);
  if (deliveryIdempotencySnapshot.exists) {
    const data = deliveryIdempotencySnapshot.data();
    return {
      status: 'already_delivered',
      repairId: command.repairId,
      journalEntryId: data.journalEntryId,
    };
  }
  if (!repairSnapshot.exists) {
    invalid('Repair request was not found.');
  }
  const repair = repairSnapshot.data();
  if (repair.storeId !== command.storeId) {
    deny('Repair belongs to another store.');
  }
  const partySnapshot = await transaction.get(
    storeRef.collection('parties').doc(repair.customerId),
  );
  if (repair.status === 'cancelled') {
    invalid('A cancelled repair cannot be delivered.');
  }
  if (repair.status === 'delivered' || repair.invoiceJournalEntryId) {
    invalid('The repair has already been delivered.');
  }
  if (journalSnapshot.exists || journalIdempotencySnapshot.exists) {
    conflict('The repair invoice journal already exists.');
  }
  assertParty(
    partySnapshot,
    command.storeId,
    repair.customerId,
    'customer',
  );

  const rawParts = Array.isArray(repair.parts) ? repair.parts : [];
  const productSnapshots = new Map();
  for (const part of rawParts) {
    const productId = safeId(part.productId, 'repair product id');
    if (productSnapshots.has(productId)) {
      invalid('A repair cannot use the same product more than once.');
    }
    productSnapshots.set(
      productId,
      await transaction.get(storeRef.collection('products').doc(productId)),
    );
  }

  const parts = [];
  let partsRevenue = 0;
  let partsCost = 0;
  const productChanges = [];
  for (const rawPart of rawParts) {
    const productId = safeId(rawPart.productId, 'repair product id');
    const productSnapshot = productSnapshots.get(productId);
    if (!productSnapshot.exists) {
      invalid('Repair product was not found: ' + productId);
    }
    const product = productSnapshot.data();
    if (product.storeId !== command.storeId ||
        product.isActive === false ||
        product.isService === true) {
      invalid('A repair product is no longer available.');
    }
    const currency = product.currency || 'ILS';
    if (currency !== repair.currency) {
      invalid('Repair product currency does not match the repair.');
    }
    const quantity = positiveInt(
      storedInt(rawPart.quantityMilliUnits, 0),
      'repair part quantity',
    );
    const unitPrice = nonNegativeInt(
      storedInt(rawPart.unitPriceMinorUnits, 0),
      'repair part unit price',
    );
    const unitCost = storedInt(product.purchasePriceMinorUnits, 0);
    const cost = multiplyAndRound(unitCost, quantity);
    const revenue = multiplyAndRound(unitPrice, quantity);
    const currentQuantity = storedInt(product.quantityOnHandMilliUnits, 0);
    const nextQuantity = currentQuantity - quantity;
    if (nextQuantity < 0) {
      throw new HttpsError(
        'failed-precondition',
        'Insufficient stock for repair product ' + productId + '.',
      );
    }
    const currentValue = Number.isSafeInteger(
      product.inventoryValueMinorUnits,
    )
      ? product.inventoryValueMinorUnits
      : multiplyAndRound(
        unitCost,
        currentQuantity,
      );
    const nextValue = currentValue - cost;
    if (nextValue < 0) {
      throw new HttpsError(
        'failed-precondition',
        'Repair would create negative inventory value.',
      );
    }
    partsRevenue += revenue;
    partsCost += cost;
    parts.push({
      id: safeId(rawPart.id, 'repair part id'),
      productId,
      productName: product.name,
      quantityMilliUnits: quantity,
      unitPriceMinorUnits: unitPrice,
      unitCostMinorUnits: unitCost,
      currency,
      source: rawPart.source || 'products',
    });
    productChanges.push({
      productId,
      productRef: storeRef.collection('products').doc(productId),
      currentQuantity,
      nextQuantity,
      nextValue,
      cost,
      movementId: command.repairId + '-part-' + productId,
      movementRef: storeRef
        .collection('inventory_movements')
        .doc(command.repairId + '-part-' + productId),
      movementIdempotencyRef: storeRef
        .collection('inventory_idempotency')
        .doc(command.idempotencyKey + ':inventory:' + productId),
    });
  }

  for (const change of productChanges) {
    change.movementSnapshot = await transaction.get(change.movementRef);
    change.movementIdempotencySnapshot = await transaction.get(
      change.movementIdempotencyRef,
    );
    if (change.movementSnapshot.exists ||
        change.movementIdempotencySnapshot.exists) {
      conflict('Repair inventory movement already exists.');
    }
  }

  const labor = storedInt(repair.laborCostMinorUnits, 0);
  const total = partsRevenue + labor;
  if (total <= 0) {
    invalid('A repair invoice must be greater than zero.');
  }
  const advance = storedInt(repair.advancePaidMinorUnits, 0);
  if (advance > total) {
    invalid('Repair advances cannot exceed the final invoice.');
  }

  const accountIds = [
    command.accounts.customerReceivableAccountId,
    command.accounts.repairRevenueAccountId,
  ];
  if (partsCost > 0) {
    accountIds.push(
      command.accounts.inventoryAccountId,
      command.accounts.costOfSalesAccountId,
    );
  }
  if (advance > 0) {
    accountIds.push(command.accounts.customerAdvancesAccountId);
  }
  const uniqueAccountIds = [...new Set(accountIds)];
  const accountSnapshots = new Map();
  const balanceSnapshots = new Map();
  for (const accountId of uniqueAccountIds) {
    accountSnapshots.set(
      accountId,
      await transaction.get(storeRef.collection('accounts').doc(accountId)),
    );
  }
  for (const accountId of uniqueAccountIds) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(
        storeRef.collection('account_balances').doc(accountId),
      ),
    );
  }
  const partyBalanceRef = storeRef
    .collection('party_balances')
    .doc('customer-' + repair.customerId);
  const partyBalanceSnapshot = await transaction.get(partyBalanceRef);
  const invoiceLedgerRef = storeRef
    .collection('party_ledger_entries')
    .doc(command.repairId + '-invoice-customer');
  const invoiceLedgerSnapshot = await transaction.get(invoiceLedgerRef);
  const advanceLedgerRef = storeRef
    .collection('party_ledger_entries')
    .doc(command.repairId + '-advance-application');
  const advanceLedgerSnapshot = await transaction.get(advanceLedgerRef);

  assertAccount(
    accountSnapshots.get(command.accounts.customerReceivableAccountId),
    command.accounts.customerReceivableAccountId,
    command.storeId,
    repair.currency,
    'asset',
    'customerReceivable',
  );
  assertAccount(
    accountSnapshots.get(command.accounts.repairRevenueAccountId),
    command.accounts.repairRevenueAccountId,
    command.storeId,
    repair.currency,
    'revenue',
  );
  if (partsCost > 0) {
    assertAccount(
      accountSnapshots.get(command.accounts.inventoryAccountId),
      command.accounts.inventoryAccountId,
      command.storeId,
      repair.currency,
      'asset',
      'inventory',
    );
    assertAccount(
      accountSnapshots.get(command.accounts.costOfSalesAccountId),
      command.accounts.costOfSalesAccountId,
      command.storeId,
      repair.currency,
      'expense',
    );
  }
  if (advance > 0) {
    assertAccount(
      accountSnapshots.get(command.accounts.customerAdvancesAccountId),
      command.accounts.customerAdvancesAccountId,
      command.storeId,
      repair.currency,
      'liability',
    );
  }
  if (invoiceLedgerSnapshot.exists || advanceLedgerSnapshot.exists) {
    conflict('Repair party ledger entries already exist.');
  }

  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    command.accounts.customerReceivableAccountId,
    total,
    advance,
  );
  addDelta(
    accountDeltas,
    command.accounts.repairRevenueAccountId,
    0,
    total,
  );
  if (partsCost > 0) {
    addDelta(
      accountDeltas,
      command.accounts.costOfSalesAccountId,
      partsCost,
      0,
    );
    addDelta(
      accountDeltas,
      command.accounts.inventoryAccountId,
      0,
      partsCost,
    );
  }
  if (advance > 0) {
    addDelta(
      accountDeltas,
      command.accounts.customerAdvancesAccountId,
      advance,
      0,
    );
  }

  const journalLines = [
    {
      id: command.repairId + '-receivable',
      storeId: command.storeId,
      accountId: command.accounts.customerReceivableAccountId,
      description: 'Repair invoice receivable',
      lineNumber: 1,
      debitMinorUnits: total,
      creditMinorUnits: 0,
    },
    {
      id: command.repairId + '-revenue',
      storeId: command.storeId,
      accountId: command.accounts.repairRevenueAccountId,
      description: 'Repair revenue',
      lineNumber: 2,
      debitMinorUnits: 0,
      creditMinorUnits: total,
    },
  ];
  if (partsCost > 0) {
    journalLines.push({
      id: command.repairId + '-cost',
      storeId: command.storeId,
      accountId: command.accounts.costOfSalesAccountId,
      description: 'Repair parts cost',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: partsCost,
      creditMinorUnits: 0,
    });
    journalLines.push({
      id: command.repairId + '-inventory',
      storeId: command.storeId,
      accountId: command.accounts.inventoryAccountId,
      description: 'Repair parts inventory issue',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: 0,
      creditMinorUnits: partsCost,
    });
  }
  if (advance > 0) {
    journalLines.push({
      id: command.repairId + '-advance',
      accountId: command.accounts.customerAdvancesAccountId,
      storeId: command.storeId,
      description: 'Apply customer advance to repair invoice',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: advance,
      creditMinorUnits: 0,
    });
    journalLines.push({
      id: command.repairId + '-advance-receivable',
      accountId: command.accounts.customerReceivableAccountId,
      storeId: command.storeId,
      description: 'Apply customer advance to receivable',
      lineNumber: journalLines.length + 1,
      debitMinorUnits: 0,
      creditMinorUnits: advance,
    });
  }

  const totalDebit = total + partsCost + advance;
  const totalCredit = total + partsCost + advance;
  transaction.set(journalRef, {
    storeId: command.storeId,
    idempotencyKey: journalIdempotencyKey,
    sourceType: 'repair',
    description: 'Repair invoice ' + command.repairId,
    status: 'posted',
    currency: repair.currency,
    totalDebitMinorUnits: totalDebit,
    totalCreditMinorUnits: totalCredit,
    postedAt: Timestamp.fromDate(command.postedAt),
  });
  for (const line of journalLines) {
    transaction.set(
      journalRef.collection('lines').doc(line.id),
      {
        ...line,
        entryId: journalEntryId,
        currency: repair.currency,
        postedAt: Timestamp.fromDate(command.postedAt),
      },
    );
  }

  for (const change of productChanges) {
    transaction.update(change.productRef, {
      quantityOnHandMilliUnits: change.nextQuantity,
      inventoryValueMinorUnits: change.nextValue,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const movementId = change.movementId;
    const movementRef = change.movementRef;
    const movementIdempotencyRef = change.movementIdempotencyRef;
    const part = parts.find(
      (candidate) => candidate.productId === change.productId,
    );
    if (!part) {
      invalid('Repair part snapshot was not found.');
    }
    transaction.set(movementRef, {
      storeId: command.storeId,
      productId: change.productId,
      type: 'saleIssue',
      quantityDeltaMilliUnits: -part.quantityMilliUnits,
      unitCostMinorUnits: part.unitCostMinorUnits,
      totalCostMinorUnits: part.unitCostMinorUnits == 0
          ? 0
          : change.cost,
      currency: repair.currency,
      idempotencyKey: command.idempotencyKey +
          ':inventory:' + change.productId,
      sourceType: 'repair',
      sourceId: command.repairId,
      occurredAt: Timestamp.fromDate(command.postedAt),
    });
    transaction.set(movementIdempotencyRef, {
      storeId: command.storeId,
      movementId,
      idempotencyKey: command.idempotencyKey +
          ':inventory:' + change.productId,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

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
  transaction.set(invoiceLedgerRef, {
    storeId: command.storeId,
    partyType: 'customer',
    partyId: repair.customerId,
    sourceType: 'repairInvoice',
    sourceId: command.repairId,
    currency: repair.currency,
    debitMinorUnits: total,
    creditMinorUnits: 0,
    description: 'Repair invoice',
    postedAt: Timestamp.fromDate(command.postedAt),
  });
  if (advance > 0) {
    transaction.set(advanceLedgerRef, {
      storeId: command.storeId,
      partyType: 'customer',
      partyId: repair.customerId,
      sourceType: 'repairAdvanceApplication',
      sourceId: command.repairId,
      currency: repair.currency,
      debitMinorUnits: 0,
      creditMinorUnits: advance,
      description: 'Repair customer advance applied',
      postedAt: Timestamp.fromDate(command.postedAt),
    });
  }
  transaction.set(partyBalanceRef, {
    storeId: command.storeId,
    partyType: 'customer',
    partyId: repair.customerId,
    currency: repair.currency,
    debitMinorUnits: currentPartyDebit + total,
    creditMinorUnits: currentPartyCredit + advance,
    balanceMinorUnits:
      currentPartyDebit + total - currentPartyCredit - advance,
    updatedAt: FieldValue.serverTimestamp(),
  });

  for (const accountId of uniqueAccountIds) {
    const balanceSnapshot = balanceSnapshots.get(accountId);
    const previous = balanceSnapshot.exists
      ? balanceSnapshot.data()
      : {};
    const delta = accountDeltas.get(accountId) || {
      debit: 0,
      credit: 0,
    };
    const currentDebit = storedInt(previous.debitMinorUnits, 0);
    const currentCredit = storedInt(previous.creditMinorUnits, 0);
    transaction.set(
      storeRef.collection('account_balances').doc(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: repair.currency,
        debitMinorUnits: currentDebit + delta.debit,
        creditMinorUnits: currentCredit + delta.credit,
        balanceMinorUnits:
          currentDebit + delta.debit - currentCredit - delta.credit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.update(repairRef, {
    status: 'delivered',
    completedAt: Timestamp.fromDate(command.postedAt),
    actualDeliveryDate: Timestamp.fromDate(command.postedAt),
    invoiceJournalEntryId: journalEntryId,
    invoicedTotalMinorUnits: total,
    costOfPartsMinorUnits: partsCost,
    paidMinorUnits: advance,
    parts,
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(deliveryIdempotencyRef, {
    storeId: command.storeId,
    repairId: command.repairId,
    idempotencyKey: command.idempotencyKey,
    journalEntryId,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(journalIdempotencyRef, {
    storeId: command.storeId,
    entryId: journalEntryId,
    idempotencyKey: journalIdempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: 'posted',
    repairId: command.repairId,
    journalEntryId,
    totalMinorUnits: total,
  };
}

async function postRepairAdvanceInTransaction(
  transaction,
  userId,
  command,
) {
  if (command.payment.paymentMethod === 'cheque') {
    invalid('Cheque advances need a posted repair invoice.');
  }
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'post repair advances',
    new Set(['owner', 'admin', 'accountant', 'sales']),
  );
  const repairRef = storeRef.collection('repairs').doc(command.repairId);
  const paymentRef = storeRef
    .collection('party_payments')
    .doc(command.payment.id);
  const paymentIdempotencyRef = storeRef
    .collection('repair_payment_idempotency')
    .doc(command.payment.idempotencyKey);
  const journalEntryId = command.payment.id + '-journal';
  const journalIdempotencyKey = command.payment.idempotencyKey + ':journal';
  const journalRef = storeRef
    .collection('journal_entries')
    .doc(journalEntryId);
  const journalIdempotencyRef = storeRef
    .collection('idempotency_keys')
    .doc(journalIdempotencyKey);

  const [
    repairSnapshot,
    paymentIdempotencySnapshot,
    paymentSnapshot,
    journalSnapshot,
    journalIdempotencySnapshot,
  ] = await Promise.all([
    transaction.get(repairRef),
    transaction.get(paymentIdempotencyRef),
    transaction.get(paymentRef),
    transaction.get(journalRef),
    transaction.get(journalIdempotencyRef),
  ]);
  if (paymentIdempotencySnapshot.exists) {
    const data = paymentIdempotencySnapshot.data();
    if (data.paymentId === command.payment.id) {
      return {
        status: 'already_posted',
        paymentId: command.payment.id,
        journalEntryId,
      };
    }
    conflict('The repair payment idempotency key is already assigned.');
  }
  if (paymentSnapshot.exists ||
      journalSnapshot.exists ||
      journalIdempotencySnapshot.exists) {
    conflict('The repair advance already exists.');
  }
  if (!repairSnapshot.exists) {
    invalid('Repair request was not found.');
  }
  const repair = repairSnapshot.data();
  if (repair.storeId !== command.storeId) {
    deny('Repair belongs to another store.');
  }
  const partySnapshot = await transaction.get(
    storeRef.collection('parties').doc(repair.customerId),
  );
  if (repair.status === 'cancelled' ||
      repair.status === 'delivered' ||
      repair.invoiceJournalEntryId) {
    invalid('An advance can only be posted before the repair invoice.');
  }
  assertParty(
    partySnapshot,
    command.storeId,
    repair.customerId,
    'customer',
  );
  if ((repair.currency || 'ILS') !== command.payment.currency) {
    invalid('Repair payment currency does not match the repair.');
  }

  const settlementAccountId = command.accounts.settlementAccountId;
  const advancesAccountId = command.accounts.customerAdvancesAccountId;
  if (!advancesAccountId) {
    invalid('A customer advances account is required.');
  }
  const accountIds = [settlementAccountId, advancesAccountId];
  const accountSnapshots = new Map();
  const balanceSnapshots = new Map();
  for (const accountId of accountIds) {
    accountSnapshots.set(
      accountId,
      await transaction.get(storeRef.collection('accounts').doc(accountId)),
    );
  }
  for (const accountId of accountIds) {
    balanceSnapshots.set(
      accountId,
      await transaction.get(
        storeRef.collection('account_balances').doc(accountId),
      ),
    );
  }
  assertAccount(
    accountSnapshots.get(settlementAccountId),
    settlementAccountId,
    command.storeId,
    command.payment.currency,
    'asset',
    paymentAccountControlType(
      command.payment.paymentMethod,
      'customer',
    ),
  );
  assertAccount(
    accountSnapshots.get(advancesAccountId),
    advancesAccountId,
    command.storeId,
    command.payment.currency,
    'liability',
  );

  const amount = command.payment.amountMinorUnits;
  const paymentData = {
    storeId: command.storeId,
    idempotencyKey: command.payment.idempotencyKey,
    postedAt: Timestamp.fromDate(command.payment.postedAt),
    partyType: 'customer',
    partyId: repair.customerId,
    repairId: command.repairId,
    paymentKind: 'advance',
    paymentMethod: command.payment.paymentMethod,
    amountMinorUnits: amount,
    currency: command.payment.currency,
    description: command.payment.description,
    status: 'posted',
    chequeNumber: null,
    bankName: null,
    dueDate: null,
    journalEntryId,
    createdAt: FieldValue.serverTimestamp(),
  };
  transaction.set(paymentRef, paymentData);
  transaction.set(journalRef, {
    storeId: command.storeId,
    idempotencyKey: journalIdempotencyKey,
    sourceType: 'repairAdvance',
    description: command.payment.description,
    status: 'posted',
    currency: command.payment.currency,
    totalDebitMinorUnits: amount,
    totalCreditMinorUnits: amount,
    postedAt: Timestamp.fromDate(command.payment.postedAt),
  });
  transaction.set(
    journalRef.collection('lines').doc(command.payment.id + '-settlement'),
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      accountId: settlementAccountId,
      description: command.payment.paymentMethod,
      lineNumber: 1,
      currency: command.payment.currency,
      debitMinorUnits: amount,
      creditMinorUnits: 0,
      postedAt: Timestamp.fromDate(command.payment.postedAt),
    },
  );
  transaction.set(
    journalRef.collection('lines').doc(command.payment.id + '-advance'),
    {
      storeId: command.storeId,
      entryId: journalEntryId,
      accountId: advancesAccountId,
      description: 'Customer repair advance',
      lineNumber: 2,
      currency: command.payment.currency,
      debitMinorUnits: 0,
      creditMinorUnits: amount,
      postedAt: Timestamp.fromDate(command.payment.postedAt),
    },
  );

  const deltas = new Map();
  addDelta(deltas, settlementAccountId, amount, 0);
  addDelta(deltas, advancesAccountId, 0, amount);
  for (const accountId of accountIds) {
    const previous = balanceSnapshots.get(accountId).exists
      ? balanceSnapshots.get(accountId).data()
      : {};
    const delta = deltas.get(accountId);
    const debit = storedInt(previous.debitMinorUnits, 0) + delta.debit;
    const credit = storedInt(previous.creditMinorUnits, 0) + delta.credit;
    transaction.set(
      storeRef.collection('account_balances').doc(accountId),
      {
        storeId: command.storeId,
        accountId,
        currency: command.payment.currency,
        debitMinorUnits: debit,
        creditMinorUnits: credit,
        balanceMinorUnits: debit - credit,
        updatedAt: FieldValue.serverTimestamp(),
      },
    );
  }

  transaction.update(repairRef, {
    advancePaidMinorUnits:
      storedInt(repair.advancePaidMinorUnits, 0) + amount,
    paidMinorUnits: storedInt(repair.paidMinorUnits, 0) + amount,
    updatedAt: FieldValue.serverTimestamp(),
  });
  transaction.set(paymentIdempotencyRef, {
    storeId: command.storeId,
    paymentId: command.payment.id,
    repairId: command.repairId,
    idempotencyKey: command.payment.idempotencyKey,
    journalEntryId,
    createdAt: FieldValue.serverTimestamp(),
  });
  transaction.set(journalIdempotencyRef, {
    storeId: command.storeId,
    entryId: journalEntryId,
    idempotencyKey: journalIdempotencyKey,
    createdAt: FieldValue.serverTimestamp(),
  });

  return {
    status: 'posted',
    paymentId: command.payment.id,
    journalEntryId,
  };
}

async function postRepairPaymentInTransaction(
  transaction,
  userId,
  command,
) {
  const storeRef = db.collection('stores').doc(command.storeId);
  const memberSnapshot = await transaction.get(
    storeRef.collection('members').doc(userId),
  );
  assertMembership(
    memberSnapshot,
    command.storeId,
    'post repair payments',
    new Set(['owner', 'admin', 'accountant', 'sales']),
  );
  const repairRef = storeRef.collection('repairs').doc(command.repairId);
  const repairSnapshot = await transaction.get(repairRef);
  if (!repairSnapshot.exists) {
    invalid('Repair request was not found.');
  }
  const repair = repairSnapshot.data();
  if (repair.storeId !== command.storeId ||
      repair.invoiceJournalEntryId == null) {
    invalid('A repair payment requires a posted repair invoice.');
  }
  if (repair.status === 'cancelled') {
    invalid('A cancelled repair cannot receive a payment.');
  }
  if ((repair.currency || 'ILS') !== command.payment.currency) {
    invalid('Repair payment currency does not match the repair.');
  }
  const total = storedInt(repair.invoicedTotalMinorUnits, 0);
  const paid = storedInt(repair.paidMinorUnits, 0);
  if (command.payment.amountMinorUnits > total - paid) {
    invalid('Repair payment exceeds the outstanding amount.');
  }

  const paymentCommand = {
    storeId: command.storeId,
    payment: {
      id: command.payment.id,
      idempotencyKey: command.payment.idempotencyKey,
      postedAt: command.payment.postedAt,
      partyType: 'customer',
      partyId: repair.customerId,
      paymentMethod: command.payment.paymentMethod,
      amountMinorUnits: command.payment.amountMinorUnits,
      currency: command.payment.currency,
      description: command.payment.description,
      chequeNumber: command.payment.chequeNumber,
      bankName: command.payment.bankName,
      dueDate: command.payment.dueDate,
    },
    accounts: {
      settlementAccountId: command.accounts.settlementAccountId,
      partyAccountId: command.accounts.customerReceivableAccountId,
    },
  };
  const result = await postPartyPaymentInTransaction(
    transaction,
    userId,
    paymentCommand,
  );
  if (result.status === 'already_posted') {
    return {
      ...result,
      repairId: command.repairId,
    };
  }

  const paymentRef = storeRef
    .collection('party_payments')
    .doc(command.payment.id);
  transaction.update(paymentRef, {
    repairId: command.repairId,
    paymentKind: 'settlement',
  });
  transaction.update(repairRef, {
    paidMinorUnits: paid + command.payment.amountMinorUnits,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    ...result,
    repairId: command.repairId,
  };
}


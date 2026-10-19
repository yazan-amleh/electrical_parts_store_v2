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
const PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);

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
    settlementAccountId: safeId(
      postingAccounts.settlementAccountId,
      'settlementAccountId',
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

  const accountIds = [
    accounts.settlementAccountId,
    accounts.salesAccountId,
    accounts.inventoryAccountId,
    accounts.costOfSalesAccountId,
  ];
  if (accounts.taxAccountId) {
    accountIds.push(accounts.taxAccountId);
  }
  if (new Set(accountIds).size !== accountIds.length) {
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

async function postSaleInTransaction(transaction, userId, command) {
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

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(membershipSnapshot, command.storeId);

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

  const journalIdempotencySnapshot = await transaction.get(
    journalIdempotencyRef,
  );
  if (journalIdempotencySnapshot.exists) {
    conflict('The journal idempotency key already exists.');
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

  const accountIds = [
    command.accounts.settlementAccountId,
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

  assertAccount(
    accountSnapshots.get(command.accounts.settlementAccountId),
    command.accounts.settlementAccountId,
    command.storeId,
    command.sale.currency,
    'asset',
  );
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
      issuedByProduct.set(
        line.productId,
        (issuedByProduct.get(line.productId) || 0) +
          baseQuantityMilliUnits,
      );
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

  const nextQuantities = new Map();
  for (const [productId, issuedQuantity] of issuedByProduct) {
    const productSnapshot = productSnapshots.get(productId);
    const product = productSnapshot.data();
    const currentQuantity = storedInt(
      product.quantityOnHandMilliUnits,
      0,
    );
    const nextQuantity = currentQuantity - issuedQuantity;
    if (nextQuantity < 0) {
      throw new HttpsError(
        'failed-precondition',
        'The sale would create negative stock for ' + productId + '.',
      );
    }
    nextQuantities.set(productId, nextQuantity);
  }

  const accountDeltas = new Map();
  addDelta(
    accountDeltas,
    command.accounts.settlementAccountId,
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
      accountId: command.accounts.settlementAccountId,
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

  for (const [productId, nextQuantity] of nextQuantities) {
    transaction.update(
      productRefs.get(productId),
      {
        quantityOnHandMilliUnits: nextQuantity,
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
      line,
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

function assertMembership(snapshot, storeId) {
  if (!snapshot.exists) {
    deny('The user is not a member of this store.');
  }
  const member = snapshot.data();
  if (member.storeId && member.storeId !== storeId) {
    deny('The membership belongs to another store.');
  }
  if (member.isActive !== true || !POSTING_ROLES.has(member.role)) {
    deny('The user cannot post sales in this store.');
  }
}

function assertAccount(
  snapshot,
  accountId,
  storeId,
  currency,
  expectedType,
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
    invalid('Account currency does not match the sale.');
  }
  if (account.type !== expectedType) {
    invalid('Account type is invalid: ' + accountId);
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

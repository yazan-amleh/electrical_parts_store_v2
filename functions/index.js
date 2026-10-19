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
const PARTY_PAYMENT_METHODS = new Set(['cash', 'bank', 'card']);
const EXPENSE_PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);
const PAYMENT_POSTING_ROLES = new Set(['owner', 'admin', 'accountant']);
const PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);
const PURCHASE_PAYMENT_METHODS = new Set(['cash', 'bank', 'card', 'credit']);

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

async function postPurchaseInTransaction(transaction, userId, command) {
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

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(
    membershipSnapshot,
    command.storeId,
    'post purchases',
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

  let supplierLedgerSnapshot = null;
  let supplierBalanceSnapshot = null;
  if (isCreditPurchase) {
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
      line,
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

  const membershipSnapshot = await transaction.get(memberRef);
  assertMembership(membershipSnapshot, command.storeId, 'post sales');

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

  let customerLedgerSnapshot = null;
  let customerBalanceSnapshot = null;
  if (isCreditSale) {
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
      line,
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
    invalid('Account currency does not match the sale.');
  }
  if (account.type !== expectedType) {
    invalid('Account type is invalid: ' + accountId);
  }
  if (expectedControlType &&
      account.controlType !== expectedControlType) {
    invalid('Account control type is invalid: ' + accountId);
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

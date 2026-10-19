'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-electrical-parts-v2-rules';
const STORE_ID = 'store-a';

let testEnv;
let ownerDb;
let accountantDb;
let salesDb;
let warehouseDb;
let inactiveDb;
let outsiderDb;
let unauthenticatedDb;

function storeDoc(db, ...segments) {
  return doc(db, 'stores', STORE_ID, ...segments);
}

async function seedStore() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'stores', STORE_ID), {
      ownerId: 'owner-1',
      name: 'Store A',
    });

    const members = [
      ['owner-1', 'owner', true],
      ['accountant-1', 'accountant', true],
      ['sales-1', 'sales', true],
      ['warehouse-1', 'warehouse', true],
      ['inactive-1', 'sales', false],
    ];

    for (const [userId, role, isActive] of members) {
      await setDoc(storeDoc(db, 'members', userId), {
        storeId: STORE_ID,
        role,
        isActive,
      });
    }

    await setDoc(storeDoc(db, 'accounts', '1110'), {
      storeId: STORE_ID,
      id: '1110',
      code: '1110',
      name: 'Cash box',
      type: 'asset',
      isHeader: false,
      isActive: true,
    });
    await setDoc(storeDoc(db, 'products', 'product-1'), {
      storeId: STORE_ID,
      name: 'Product 1',
      isActive: true,
      quantityOnHandMilliUnits: 0,
      inventoryValueMinorUnits: 0,
    });
    await setDoc(storeDoc(db, 'sales', 'sale-1'), {
      storeId: STORE_ID,
      status: 'posted',
    });
    await setDoc(storeDoc(db, 'purchases', 'purchase-1'), {
      storeId: STORE_ID,
      status: 'posted',
    });
    await setDoc(storeDoc(db, 'journal_entries', 'journal-1'), {
      storeId: STORE_ID,
      status: 'posted',
      totalDebitMinorUnits: 100,
      totalCreditMinorUnits: 100,
    });
    await setDoc(storeDoc(db, 'journal_entries', 'journal-1', 'lines', 'line-1'), {
      storeId: STORE_ID,
      accountId: '1110',
      debitMinorUnits: 100,
      creditMinorUnits: 0,
    });
    await setDoc(storeDoc(db, 'party_ledger_entries', 'party-entry-1'), {
      storeId: STORE_ID,
      partyType: 'customer',
      partyId: 'customer-1',
    });
    await setDoc(storeDoc(db, 'party_balances', 'customer-1'), {
      storeId: STORE_ID,
      partyType: 'customer',
      partyId: 'customer-1',
      balanceMinorUnits: 100,
    });
  });
}

describe('Firestore security rules', function () {
  this.timeout(60000);

  before(async () => {
    const rules = fs.readFileSync(
      path.join(__dirname, '..', 'firestore.rules'),
      'utf8',
    );

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules },
    });

    ownerDb = testEnv.authenticatedContext('owner-1').firestore();
    accountantDb = testEnv.authenticatedContext('accountant-1').firestore();
    salesDb = testEnv.authenticatedContext('sales-1').firestore();
    warehouseDb = testEnv.authenticatedContext('warehouse-1').firestore();
    inactiveDb = testEnv.authenticatedContext('inactive-1').firestore();
    outsiderDb = testEnv.authenticatedContext('outsider-1').firestore();
    unauthenticatedDb = testEnv.unauthenticatedContext().firestore();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedStore();
  });

  after(async () => {
    await testEnv.cleanup();
  });

  it('requires an active store membership for reads', async () => {
    await assertSucceeds(getDoc(storeDoc(accountantDb, 'accounts', '1110')));
    await assertSucceeds(getDoc(storeDoc(accountantDb, 'party_balances', 'customer-1')));
    await assertSucceeds(
      getDoc(storeDoc(accountantDb, 'journal_entries', 'journal-1', 'lines', 'line-1')),
    );

    await assertFails(getDoc(storeDoc(outsiderDb, 'accounts', '1110')));
    await assertFails(getDoc(storeDoc(inactiveDb, 'accounts', '1110')));
    await assertFails(getDoc(storeDoc(unauthenticatedDb, 'accounts', '1110')));
  });

  it('keeps store data tenant-scoped', async () => {
    await assertSucceeds(getDoc(storeDoc(salesDb, 'products', 'product-1')));
    await assertSucceeds(getDoc(storeDoc(salesDb, 'sales', 'sale-1')));

    await assertFails(
      getDoc(doc(outsiderDb, 'stores', 'store-b', 'accounts', '1110')),
    );
    await assertFails(
      getDoc(doc(salesDb, 'stores', 'store-b', 'accounts', '1110')),
    );
  });

  it('allows only the intended roles to manage accounts and inventory', async () => {
    await assertSucceeds(
      setDoc(storeDoc(ownerDb, 'accounts', '1121'), {
        storeId: STORE_ID,
        id: '1121',
        code: '1121',
        name: 'Main bank',
        type: 'asset',
        isHeader: false,
        isActive: true,
      }),
    );
    await assertFails(
      setDoc(storeDoc(accountantDb, 'accounts', '1122'), {
        storeId: STORE_ID,
        id: '1122',
        code: '1122',
        name: 'Unauthorized account',
      }),
    );
    await assertSucceeds(
      setDoc(storeDoc(warehouseDb, 'inventory_movements', 'movement-1'), {
        storeId: STORE_ID,
        productId: 'product-1',
        quantityDeltaMilliUnits: 1000,
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'inventory_movements', 'movement-2'), {
        storeId: STORE_ID,
        productId: 'product-1',
        quantityDeltaMilliUnits: 1000,
      }),
    );
  });

  it('keeps posted business documents immutable from clients', async () => {
    const forbiddenWrites = [
      ['sales', 'sale-2'],
      ['purchases', 'purchase-2'],
      ['expenses', 'expense-1'],
      ['party_payments', 'payment-1'],
      ['account_transfers', 'transfer-1'],
    ];

    for (const [collection, id] of forbiddenWrites) {
      await assertFails(
        setDoc(storeDoc(accountantDb, collection, id), {
          storeId: STORE_ID,
          status: 'posted',
        }),
      );
    }

    await assertFails(
      deleteDoc(storeDoc(accountantDb, 'sales', 'sale-1')),
    );
    await assertFails(
      updateDoc(storeDoc(accountantDb, 'purchases', 'purchase-1'), {
        status: 'void',
      }),
    );
  });

  it('keeps journals and balance projections server-owned', async () => {
    await assertFails(
      setDoc(storeDoc(accountantDb, 'journal_entries', 'manual-1'), {
        storeId: STORE_ID,
        status: 'posted',
        totalDebitMinorUnits: 100,
        totalCreditMinorUnits: 100,
      }),
    );
    await assertFails(
      setDoc(
        storeDoc(
          accountantDb,
          'journal_entries',
          'journal-1',
          'lines',
          'line-2',
        ),
        {
          storeId: STORE_ID,
          accountId: '1110',
          debitMinorUnits: 100,
          creditMinorUnits: 0,
        },
      ),
    );
    await assertFails(
      setDoc(storeDoc(accountantDb, 'account_balances', '1110'), {
        storeId: STORE_ID,
        accountId: '1110',
        debitMinorUnits: 100,
        creditMinorUnits: 0,
        balanceMinorUnits: 100,
      }),
    );
  });

  it('keeps idempotency documents server-owned', async () => {
    const idempotencyCollections = [
      'sale_idempotency',
      'purchase_idempotency',
      'expense_idempotency',
      'party_payment_idempotency',
      'account_transfer_idempotency',
    ];

    for (const collection of idempotencyCollections) {
      await assertFails(
        setDoc(storeDoc(accountantDb, collection, 'key-1'), {
          storeId: STORE_ID,
        }),
      );
      await assertFails(
        getDoc(storeDoc(accountantDb, collection, 'key-1')),
      );
    }
  });

  it('allows an active member to own only pending outbox commands', async () => {
    const commandRef = storeDoc(accountantDb, 'command_outbox', 'command-1');

    await assertSucceeds(
      setDoc(commandRef, {
        storeId: STORE_ID,
        createdBy: 'accountant-1',
        status: 'pending',
        operation: 'postExpense',
        idempotencyKey: 'expense-key-1',
        payload: {},
      }),
    );
    await assertSucceeds(updateDoc(commandRef, { attemptCount: 1 }));
    await assertFails(getDoc(storeDoc(ownerDb, 'command_outbox', 'command-1')));

    await assertFails(
      setDoc(storeDoc(accountantDb, 'command_outbox', 'command-completed'), {
        storeId: STORE_ID,
        createdBy: 'accountant-1',
        status: 'completed',
        operation: 'postExpense',
        idempotencyKey: 'expense-key-2',
      }),
    );
    await assertFails(
      setDoc(storeDoc(accountantDb, 'command_outbox', 'command-unknown'), {
        storeId: STORE_ID,
        createdBy: 'accountant-1',
        status: 'pending',
        operation: 'deleteAllAccounting',
        idempotencyKey: 'dangerous-key',
      }),
    );
    await assertFails(
      setDoc(storeDoc(accountantDb, 'command_outbox', 'command-foreign'), {
        storeId: STORE_ID,
        createdBy: 'owner-1',
        status: 'pending',
        operation: 'postExpense',
        idempotencyKey: 'foreign-key',
      }),
    );
  });
});

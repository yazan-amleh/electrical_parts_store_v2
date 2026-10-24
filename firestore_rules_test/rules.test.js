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
  Timestamp,
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
      currency: 'ILS',
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
    await setDoc(storeDoc(db, 'purchase_orders', 'order-1'), {
      storeId: STORE_ID,
      status: 'pending',
      supplierId: 'supplier-1',
      lines: [],
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
    await setDoc(storeDoc(db, 'parties', 'customer-1'), {
      storeId: STORE_ID,
      partyType: 'customer',
      name: 'Customer 1',
      isActive: true,
    });
    await setDoc(storeDoc(db, 'categories', 'general'), {
      storeId: STORE_ID,
      name: 'General',
      parentId: null,
      sortOrder: 0,
      isActive: true,
    });
    await setDoc(storeDoc(db, 'party_balances', 'customer-1'), {
      storeId: STORE_ID,
      partyType: 'customer',
      partyId: 'customer-1',
      balanceMinorUnits: 100,
    });

    await setDoc(storeDoc(db, 'chatRooms', 'room-1'), {
      storeId: STORE_ID,
      name: 'Support',
      participantIds: ['owner-1', 'sales-1'],
      participants: [
        {
          userId: 'owner-1',
          displayName: 'Owner',
          joinedAt: Timestamp.fromMillis(1000),
          isAdmin: true,
        },
        {
          userId: 'sales-1',
          displayName: 'Sales',
          joinedAt: Timestamp.fromMillis(1000),
          isAdmin: false,
        },
      ],
      createdAt: Timestamp.fromMillis(1000),
      updatedAt: Timestamp.fromMillis(1000),
      lastMessageAt: null,
      lastMessageText: '',
      lastMessageSenderId: '',
      unreadCountByUser: { 'owner-1': 0, 'sales-1': 0 },
      isGroup: false,
      groupDescription: null,
      createdBy: 'owner-1',
      type: 'support',
      isArchived: false,
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
    await assertSucceeds(
      getDoc(storeDoc(salesDb, 'purchase_orders', 'order-1')),
    );

    await assertFails(
      getDoc(doc(outsiderDb, 'stores', 'store-b', 'accounts', '1110')),
    );
    await assertFails(
      getDoc(doc(salesDb, 'stores', 'store-b', 'accounts', '1110')),
    );
  });

  it('requires server-side chart writes and preserves inventory role controls', async () => {
    await assertFails(
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
      updateDoc(storeDoc(ownerDb, 'accounts', '1110'), {
        name: 'Owner must use chart callable',
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
      setDoc(storeDoc(warehouseDb, 'products', 'product-2'), {
        storeId: STORE_ID,
        name: 'Product 2',
        quantityOnHandMilliUnits: 0,
        inventoryValueMinorUnits: 0,
      }),
    );
    await assertFails(
      updateDoc(storeDoc(warehouseDb, 'products', 'product-1'), {
        quantityOnHandMilliUnits: 1000,
        inventoryValueMinorUnits: 100,
      }),
    );
    await assertFails(
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

  it('protects party directory writes by role and tenant', async () => {
    await assertSucceeds(
      getDoc(storeDoc(accountantDb, 'parties', 'customer-1')),
    );

    await assertSucceeds(
      setDoc(storeDoc(salesDb, 'parties', 'customer-2'), {
        storeId: STORE_ID,
        partyType: 'customer',
        name: 'Customer 2',
        isActive: true,
      }),
    );
    await assertSucceeds(
      updateDoc(storeDoc(salesDb, 'parties', 'customer-2'), {
        name: 'Renamed Customer',
      }),
    );
    await assertFails(
      updateDoc(storeDoc(salesDb, 'parties', 'customer-2'), {
        partyType: 'supplier',
      }),
    );
    await assertFails(
      deleteDoc(storeDoc(salesDb, 'parties', 'customer-2')),
    );
    await assertFails(
      setDoc(storeDoc(warehouseDb, 'parties', 'customer-3'), {
        storeId: STORE_ID,
        partyType: 'customer',
        name: 'Warehouse Customer',
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'parties', 'foreign-party'), {
        storeId: 'store-b',
        partyType: 'customer',
        name: 'Foreign Customer',
      }),
    );
    await assertFails(
      setDoc(storeDoc(accountantDb, 'party_balances', 'customer-2'), {
        storeId: STORE_ID,
        partyType: 'customer',
        partyId: 'customer-2',
        balanceMinorUnits: 100,
      }),
    );
  });

  it('restricts store settings and member management', async () => {
    await assertSucceeds(
      updateDoc(storeDoc(ownerDb), {
        name: 'Renamed Store',
        currency: 'ILS',
      }),
    );
    await assertFails(
      updateDoc(storeDoc(accountantDb), {
        name: 'Unauthorized Rename',
      }),
    );
    await assertFails(
      updateDoc(storeDoc(ownerDb), {
        ownerId: 'owner-2',
      }),
    );
    await assertFails(
      updateDoc(storeDoc(ownerDb), {
        currency: 'USD',
      }),
    );

    await assertSucceeds(
      updateDoc(storeDoc(ownerDb, 'members', 'sales-1'), {
        role: 'accountant',
        isActive: true,
      }),
    );
    await assertFails(
      updateDoc(storeDoc(accountantDb, 'members', 'sales-1'), {
        role: 'admin',
      }),
    );
  });

  it('protects category writes by role and tenant', async () => {
    await assertSucceeds(
      getDoc(storeDoc(accountantDb, 'categories', 'general')),
    );
    await assertSucceeds(
      setDoc(storeDoc(warehouseDb, 'categories', 'electrical'), {
        storeId: STORE_ID,
        name: 'Electrical',
        parentId: 'general',
        sortOrder: 1,
        isActive: true,
      }),
    );
    await assertSucceeds(
      updateDoc(storeDoc(warehouseDb, 'categories', 'electrical'), {
        name: 'Electrical Parts',
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'categories', 'forbidden'), {
        storeId: STORE_ID,
        name: 'Forbidden',
      }),
    );
    await assertFails(
      setDoc(storeDoc(warehouseDb, 'categories', 'foreign-category'), {
        storeId: 'store-b',
        name: 'Foreign',
      }),
    );
    await assertFails(
      deleteDoc(storeDoc(warehouseDb, 'categories', 'electrical')),
    );
  });

  it('scopes personal notes and keeps activity logs read-only', async () => {
    await assertSucceeds(
      setDoc(storeDoc(salesDb, 'notes', 'note-1'), {
        storeId: STORE_ID,
        userId: 'sales-1',
        title: 'Follow up',
        content: 'Call customer',
        type: 'customer',
        priority: 'high',
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'notes', 'note-2'), {
        storeId: STORE_ID,
        userId: 'owner-1',
        title: 'Owner note',
        content: 'Private',
        type: 'general',
        priority: 'medium',
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'notes', 'foreign-note'), {
        storeId: 'store-b',
        userId: 'sales-1',
        title: 'Foreign',
        content: 'Denied',
        type: 'general',
        priority: 'low',
      }),
    );
    await assertSucceeds(
      updateDoc(storeDoc(salesDb, 'notes', 'note-1'), {
        content: 'Updated customer call',
      }),
    );
    await assertFails(
      deleteDoc(storeDoc(salesDb, 'notes', 'note-1')),
    );

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(
        doc(context.firestore(), 'stores', STORE_ID, 'activity_logs', 'log-1'),
        {
          storeId: STORE_ID,
          description: 'Sale posted',
          timestamp: Timestamp.now(),
        },
      );
    });
    await assertSucceeds(
      getDoc(storeDoc(salesDb, 'activity_logs', 'log-1')),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'activity_logs', 'log-2'), {
        storeId: STORE_ID,
        description: 'Client write',
        timestamp: Timestamp.now(),
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
      ['purchase_orders', 'order-2'],
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
      'purchase_order_receipt_idempotency',
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
  it('enforces participant-scoped chat rooms and atomic room ownership', async () => {
    await assertSucceeds(
      getDoc(storeDoc(ownerDb, 'chatRooms', 'room-1')),
    );
    await assertSucceeds(
      getDoc(storeDoc(salesDb, 'chatRooms', 'room-1')),
    );
    await assertFails(
      getDoc(storeDoc(accountantDb, 'chatRooms', 'room-1')),
    );
    await assertFails(
      getDoc(storeDoc(outsiderDb, 'chatRooms', 'room-1')),
    );
    await assertFails(
      getDoc(storeDoc(inactiveDb, 'chatRooms', 'room-1')),
    );

    await assertSucceeds(
      setDoc(storeDoc(salesDb, 'chatRooms', 'room-2'), {
        storeId: STORE_ID,
        name: 'Accounting',
        participantIds: ['sales-1', 'accountant-1'],
        participants: [
          {
            userId: 'sales-1',
            displayName: 'Sales',
            joinedAt: Timestamp.fromMillis(1000),
            isAdmin: true,
          },
          {
            userId: 'accountant-1',
            displayName: 'Accountant',
            joinedAt: Timestamp.fromMillis(1000),
            isAdmin: false,
          },
        ],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        lastMessageAt: null,
        lastMessageText: '',
        lastMessageSenderId: '',
        unreadCountByUser: { 'sales-1': 0, 'accountant-1': 0 },
        isGroup: true,
        groupDescription: 'Accounting support',
        createdBy: 'sales-1',
        type: 'group',
        isArchived: false,
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'chatRooms', 'room-3'), {
        storeId: STORE_ID,
        name: 'Invalid',
        participantIds: ['accountant-1'],
        participants: [],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        createdBy: 'sales-1',
        type: 'group',
        isGroup: true,
      }),
    );
    await assertFails(
      setDoc(storeDoc(outsiderDb, 'chatRooms', 'room-4'), {
        storeId: STORE_ID,
        name: 'Outsider',
        participantIds: ['outsider-1'],
        participants: [],
        createdAt: Timestamp.fromMillis(1000),
        updatedAt: Timestamp.fromMillis(1000),
        createdBy: 'outsider-1',
        type: 'direct',
        isGroup: false,
      }),
    );
  });

  it('restricts chat messages, unread projections and participant management', async () => {
    const messageRef = storeDoc(
      salesDb,
      'chatRooms',
      'room-1',
      'messages',
      'message-1',
    );

    await assertSucceeds(
      setDoc(messageRef, {
        storeId: STORE_ID,
        roomId: 'room-1',
        senderId: 'sales-1',
        senderName: 'Sales',
        content: 'Hello',
        sentAt: Timestamp.fromMillis(2000),
        type: 'text',
        attachmentUrls: [],
        isDeleted: false,
      }),
    );
    await assertFails(
      setDoc(
        storeDoc(
          accountantDb,
          'chatRooms',
          'room-1',
          'messages',
          'message-2',
        ),
        {
          storeId: STORE_ID,
          roomId: 'room-1',
          senderId: 'accountant-1',
          senderName: 'Accountant',
          content: 'Not a participant',
          sentAt: Timestamp.fromMillis(2000),
          type: 'text',
          attachmentUrls: [],
          isDeleted: false,
        },
      ),
    );
    await assertFails(
      setDoc(
        storeDoc(
          salesDb,
          'chatRooms',
          'room-1',
          'messages',
          'message-3',
        ),
        {
          storeId: STORE_ID,
          roomId: 'room-1',
          senderId: 'owner-1',
          senderName: 'Spoofed owner',
          content: 'Spoofed',
          sentAt: Timestamp.fromMillis(2000),
          type: 'text',
          attachmentUrls: [],
          isDeleted: false,
        },
      ),
    );
    await assertFails(
      getDoc(
        storeDoc(
          outsiderDb,
          'chatRooms',
          'room-1',
          'messages',
          'message-1',
        ),
      ),
    );
    await assertSucceeds(
      updateDoc(messageRef, {
        isDeleted: true,
      }),
    );
    await assertFails(
      updateDoc(
        storeDoc(
          ownerDb,
          'chatRooms',
          'room-1',
          'messages',
          'message-1',
        ),
        {
          isDeleted: true,
        },
      ),
    );
    await assertFails(deleteDoc(messageRef));

    const messageTime = Timestamp.fromMillis(3000);
    await assertSucceeds(
      updateDoc(storeDoc(salesDb, 'chatRooms', 'room-1'), {
        lastMessageAt: messageTime,
        lastMessageText: 'Hello',
        lastMessageSenderId: 'sales-1',
        updatedAt: messageTime,
        unreadCountByUser: { 'owner-1': 1, 'sales-1': 0 },
      }),
    );
    await assertSucceeds(
      updateDoc(storeDoc(ownerDb, 'chatRooms', 'room-1'), {
        unreadCountByUser: { 'owner-1': 0, 'sales-1': 0 },
        updatedAt: Timestamp.fromMillis(4000),
      }),
    );
    await assertFails(
      updateDoc(storeDoc(salesDb, 'chatRooms', 'room-1'), {
        name: 'Participant rename',
      }),
    );

    await assertSucceeds(
      updateDoc(storeDoc(ownerDb, 'chatRooms', 'room-1'), {
        participantIds: ['owner-1', 'sales-1', 'warehouse-1'],
        participants: [
          {
            userId: 'owner-1',
            displayName: 'Owner',
            joinedAt: Timestamp.fromMillis(1000),
            isAdmin: true,
          },
          {
            userId: 'sales-1',
            displayName: 'Sales',
            joinedAt: Timestamp.fromMillis(1000),
            isAdmin: false,
          },
          {
            userId: 'warehouse-1',
            displayName: 'Warehouse',
            joinedAt: Timestamp.fromMillis(4000),
            isAdmin: false,
          },
        ],
      }),
    );
    await assertSucceeds(
      getDoc(storeDoc(warehouseDb, 'chatRooms', 'room-1')),
    );
    await assertFails(
      deleteDoc(storeDoc(ownerDb, 'chatRooms', 'room-1')),
    );
  });

  it('keeps notification tokens private and user-owned', async () => {
    const tokenRef = storeDoc(
      salesDb,
      'notificationTokens',
      'token-1',
    );
    await assertSucceeds(
      setDoc(tokenRef, {
        storeId: STORE_ID,
        userId: 'sales-1',
        token: 'fcm-token-1',
        platform: 'web',
      }),
    );
    await assertFails(getDoc(tokenRef));
    await assertFails(
      updateDoc(tokenRef, {
        userId: 'owner-1',
      }),
    );
    await assertFails(
      setDoc(storeDoc(salesDb, 'notificationTokens', 'token-2'), {
        storeId: STORE_ID,
        userId: 'owner-1',
        token: 'fcm-token-2',
        platform: 'web',
      }),
    );
    await assertFails(
      setDoc(storeDoc(outsiderDb, 'notificationTokens', 'token-3'), {
        storeId: STORE_ID,
        userId: 'outsider-1',
        token: 'fcm-token-3',
        platform: 'web',
      }),
    );
    await assertSucceeds(deleteDoc(tokenRef));
  });


  it('requires server-side bootstrap for new stores', async () => {
    await assertFails(
      setDoc(doc(outsiderDb, 'stores', 'unowned-new-store'), {
        ownerId: 'outsider-1', name: 'Fake Store', currency: 'ILS',
      }),
    );
    await assertFails(
      setDoc(doc(ownerDb, 'stores', 'owner-new-store'), {
        ownerId: 'owner-1', name: 'New Store', currency: 'ILS',
      }),
    );
  });

  it('allows self membership lookup when not provisioned, but no tenant reads', async () => {
    const missing = await assertSucceeds(
      getDoc(storeDoc(outsiderDb, 'members', 'outsider-1')),
    );
    assert.equal(missing.exists(), false);
    await assertSucceeds(
      getDoc(storeDoc(inactiveDb, 'members', 'inactive-1')),
    );
    await assertFails(
      getDoc(storeDoc(outsiderDb, 'members', 'owner-1')),
    );
    await assertFails(
      getDoc(storeDoc(outsiderDb, 'products', 'product-1')),
    );
  });

  it('restricts the selected-store preference to the user and server writes', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'user_store_preferences', 'owner-1'), {
        userId: 'owner-1', selectedStoreId: STORE_ID,
      });
    });
    await assertSucceeds(
      getDoc(doc(ownerDb, 'user_store_preferences', 'owner-1')),
    );
    await assertFails(
      getDoc(doc(outsiderDb, 'user_store_preferences', 'owner-1')),
    );
    await assertFails(
      setDoc(doc(ownerDb, 'user_store_preferences', 'owner-1'), {
        userId: 'owner-1', selectedStoreId: 'other-store',
      }),
    );
    await assertFails(
      setDoc(doc(outsiderDb, 'user_store_preferences', 'outsider-1'), {
        userId: 'outsider-1', selectedStoreId: STORE_ID,
      }),
    );
  });

  it('does not allow owners to forge or remove seeded chart metadata', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), 'stores', STORE_ID), {
        initialChartVersion: 1,
        initialChartAccountCount: 25,
      });
    });
    await assertFails(
      updateDoc(doc(ownerDb, 'stores', STORE_ID), {
        initialChartVersion: 2,
      }),
    );
    await assertFails(
      updateDoc(doc(ownerDb, 'stores', STORE_ID), {
        initialChartAccountCount: 0,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(ownerDb, 'stores', STORE_ID), {
        name: 'New Store Name',
      }),
    );
  });


  it('keeps journal header reconciliation checkpoints and results server-only', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(storeDoc(adminDb, 'accounting_journal_runs', 'run-1'), {
        storeId: STORE_ID, createdBy: 'owner-1', certified: false,
      });
      await setDoc(storeDoc(adminDb, 'accounting_journal_runs', 'run-1',
        'entry_results', 'journal-1'), {
        storeId: STORE_ID, entryId: 'journal-1', matched: false,
      });
    });
    const run = storeDoc(ownerDb, 'accounting_journal_runs', 'run-1');
    const result = storeDoc(accountantDb, 'accounting_journal_runs', 'run-1',
      'entry_results', 'journal-1');
    await assertFails(getDoc(run));
    await assertFails(getDoc(result));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_journal_runs', 'fake'), {
      storeId: STORE_ID, certified: true,
    }));
    await assertFails(updateDoc(run, {certified: true}));
    await assertFails(setDoc(storeDoc(accountantDb,
      'accounting_journal_runs', 'run-1', 'entry_results', 'forgery'), {
      entryId: 'journal-1', matched: true,
    }));
  });

  it('blocks client forgery of GL reconciliation runs and results', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();
      await setDoc(storeDoc(adminDb, 'accounting_ledger_runs',
        'verified-run'), {
        storeId: STORE_ID, createdBy: 'owner-1',
        status: 'running', certified: false,
      });
      await setDoc(storeDoc(adminDb, 'accounting_ledger_runs',
        'verified-run', 'account_results', '1110'), {
        storeId: STORE_ID, accountId: '1110', matched: false,
      });
    });
    const run = storeDoc(ownerDb, 'accounting_ledger_runs',
      'verified-run');
    const result = storeDoc(accountantDb, 'accounting_ledger_runs',
      'verified-run', 'account_results', '1110');
    await assertFails(getDoc(run));
    await assertFails(getDoc(result));
    await assertFails(setDoc(storeDoc(ownerDb, 'accounting_ledger_runs',
      'fake-run'), {storeId: STORE_ID, certified: true}));
    await assertFails(updateDoc(run, {certified: true}));
    await assertFails(setDoc(storeDoc(accountantDb,
      'accounting_ledger_runs', 'verified-run',
      'account_results', 'forge'), {
      accountId: '1110', matched: true,
    }));
  });

  it('denies client forgery or disabling of accounting close controls', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(storeDoc(context.firestore(),
        'accounting_period_control', 'current'), {
        storeId: STORE_ID, status: 'locked', closeId: 'audit-lock',
      });
      await setDoc(storeDoc(context.firestore(),
        'accounting_close_events', 'audit-lock'), {
        storeId: STORE_ID, kind: 'began',
      });
    });
    const control = storeDoc(ownerDb, 'accounting_period_control', 'current');
    await assertFails(getDoc(control));
    await assertFails(updateDoc(control, {status: 'open'}));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_period_control', 'other'), {status: 'open'}));
    await assertFails(getDoc(storeDoc(accountantDb,
      'accounting_close_events', 'audit-lock')));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_close_events', 'forged'), {kind: 'reopened'}));
  });

  it('denies clients reading or forging sharded posting epochs', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(storeDoc(context.firestore(),
        'accounting_posting_epochs', '00'), {
        version: 1, sequence: 1,
      });
    });
    const epoch = storeDoc(ownerDb, 'accounting_posting_epochs', '00');
    await assertFails(getDoc(epoch));
    await assertFails(getDoc(storeDoc(accountantDb,
      'accounting_posting_epochs', '00')));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_posting_epochs', '01'), {
      version: 1, sequence: 999,
    }));
    await assertFails(updateDoc(epoch, {sequence: 0}));
  });

  it('denies all client access to reverse balance census checkpoints', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      await setDoc(storeDoc(db, 'accounting_balance_path_runs', 'reverse-1'), {
        storeId: STORE_ID, createdBy: 'owner-1', certified: false,
      });
    });
    const doc = storeDoc(ownerDb, 'accounting_balance_path_runs',
      'reverse-1');
    await assertFails(getDoc(doc));
    await assertFails(getDoc(storeDoc(accountantDb,
      'accounting_balance_path_runs', 'reverse-1')));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_balance_path_runs', 'forgery'), {
      storeId: STORE_ID, status: 'enumeration_complete',
      certified: true,
    }));
    await assertFails(updateDoc(doc, {certified: true}));
  });

  it('blocks client reads and forgery of path-based orphan scan results', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(storeDoc(context.firestore(), 'accounting_orphan_path_runs',
        'orphan-run'), {
        storeId: STORE_ID, createdBy: 'owner-1',
        status: 'running', certified: false,
      });
    });
    const checkpoint = storeDoc(ownerDb, 'accounting_orphan_path_runs',
      'orphan-run');
    await assertFails(getDoc(checkpoint));
    await assertFails(getDoc(storeDoc(accountantDb,
      'accounting_orphan_path_runs', 'orphan-run')));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_orphan_path_runs', 'forged'), {
      storeId: STORE_ID, status: 'enumeration_complete',
      certified: true,
    }));
    await assertFails(updateDoc(checkpoint, {certified: true}));
  });

  it('keeps accounting inventory checkpoints server-only', async () => {
    const runRef = storeDoc(ownerDb, 'accounting_audit_runs', 'run-1');
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(storeDoc(context.firestore(), 'accounting_audit_runs',
        'run-1'), {
        storeId: STORE_ID,
        createdBy: 'owner-1',
        phaseIndex: 0,
        cursor: null,
        certified: false,
      });
    });
    await assertFails(getDoc(runRef));
    await assertFails(getDoc(storeDoc(accountantDb,
      'accounting_audit_runs', 'run-1')));
    await assertFails(getDoc(storeDoc(outsiderDb,
      'accounting_audit_runs', 'run-1')));
    await assertFails(setDoc(storeDoc(ownerDb,
      'accounting_audit_runs', 'fake'), {
      storeId: STORE_ID, status: 'enumeration_complete', certified: true,
    }));
    await assertFails(updateDoc(runRef, {certified: true}));
  });


});

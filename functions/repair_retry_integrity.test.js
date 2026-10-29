'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'repair-retry-accountant';
const DATE = '2026-10-29T12:00:00.000Z';

function deliveryRequest(storeId, revenueAccountId = '4110') {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      repairId: 'repair-1',
      idempotencyKey: 'repair-delivery-repair-1',
      postedAt: DATE,
      accounts: {
        customerReceivableAccountId: '1140',
        repairRevenueAccountId: revenueAccountId,
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5100',
        customerAdvancesAccountId: '2130',
      },
    },
  };
}

function advanceRequest(storeId, amountMinorUnits = 100) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      repairId: 'repair-1',
      payment: {
        id: 'advance-1',
        idempotencyKey: 'advance-1-key',
        postedAt: DATE,
        paymentMethod: 'cash',
        amountMinorUnits,
        currency: 'ILS',
        description: 'Repair advance',
        chequeNumber: null,
        bankName: null,
        dueDate: null,
      },
      postingAccounts: {
        settlementAccountId: '1110',
        customerReceivableAccountId: '1140',
        customerAdvancesAccountId: '2130',
      },
    },
  };
}

async function seed(storeId) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId, currency: 'ILS'});
  batch.set(store.collection('members').doc(USER), {
    storeId,
    userId: USER,
    role: 'accountant',
    isActive: true,
  });
  batch.set(store.collection('parties').doc('customer-1'), {
    storeId,
    partyType: 'customer',
    name: 'Repair customer',
    isActive: true,
  });
  for (const [id, type, controlType, normalSide] of [
    ['1110', 'asset', 'cashBox', 'debit'],
    ['1140', 'asset', 'customerReceivable', 'debit'],
    ['1150', 'asset', 'inventory', 'debit'],
    ['4110', 'revenue', 'none', 'credit'],
    ['4120', 'revenue', 'none', 'credit'],
    ['5100', 'expense', 'none', 'debit'],
    ['2130', 'liability', 'none', 'credit'],
  ]) {
    batch.set(store.collection('accounts').doc(id), {
      storeId,
      id,
      code: id,
      name: id,
      type,
      controlType,
      normalSide,
      currency: 'ILS',
      isHeader: false,
      isActive: true,
    });
  }
  batch.set(store.collection('repairs').doc('repair-1'), {
    storeId,
    customerId: 'customer-1',
    status: 'ready',
    currency: 'ILS',
    laborCostMinorUnits: 500,
    estimatedCostMinorUnits: 500,
    advancePaidMinorUnits: 0,
    paidMinorUnits: 0,
    parts: [],
  });
  await batch.commit();
  return store;
}

describe('repair financial retry integrity', () => {
  after(async () => {await admin.app().delete();});

  it('replays exact delivery and rejects changed posting accounts', async () => {
    const store = await seed('repair-delivery-fingerprint');
    const request = deliveryRequest(store.id);

    const first = await functions.deliverRepair.run(request);
    assert.equal(first.status, 'posted');

    const exact = await functions.deliverRepair.run(request);
    assert.equal(exact.status, 'already_delivered');

    await assert.rejects(
      functions.deliverRepair.run(deliveryRequest(store.id, '4120')),
      (error) => error.code === 'already-exists',
    );

    const marker = (await store
      .collection('repair_delivery_idempotency')
      .doc('repair-delivery-repair-1')
      .get()).data();
    assert.equal(typeof marker.requestFingerprint, 'string');

    assert.equal((await store.collection('journal_entries').get()).size, 1);
    const repair = (await store.collection('repairs')
      .doc('repair-1').get()).data();
    assert.equal(repair.status, 'delivered');
    assert.equal(repair.invoicedTotalMinorUnits, 500);
    await db.recursiveDelete(store);
  });

  it('depletes repair parts using exact inventory carrying value', async () => {
    const store = await seed('repair-exact-carrying-value');
    await store.collection('products').doc('product-a').set({
      storeId: store.id,
      currency: 'ILS',
      isService: false,
      isActive: true,
      quantityOnHandMilliUnits: 3000,
      purchasePriceMinorUnits: 333,
      inventoryValueMinorUnits: 1000,
    });
    await store.collection('repairs').doc('repair-1').update({
      laborCostMinorUnits: 0,
      parts: [{
        id: 'part-a',
        productId: 'product-a',
        productName: 'Electrical component',
        quantityMilliUnits: 3000,
        unitPriceMinorUnits: 500,
        unitCostMinorUnits: 333,
        currency: 'ILS',
        source: 'products',
      }],
    });

    const result = await functions.deliverRepair.run(
      deliveryRequest(store.id),
    );
    assert.equal(result.status, 'posted');

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);

    const repair = (await store.collection('repairs')
      .doc('repair-1').get()).data();
    assert.equal(repair.costOfPartsMinorUnits, 1000);
    assert.equal(repair.invoicedTotalMinorUnits, 1500);

    const movement = (await store.collection('inventory_movements')
      .doc('repair-1-part-product-a').get()).data();
    assert.equal(movement.totalCostMinorUnits, 1000);

    const costLine = (await store.collection('journal_entries')
      .doc('repair-1-invoice')
      .collection('lines').doc('repair-1-cost').get()).data();
    assert.equal(costLine.debitMinorUnits, 1000);
    await db.recursiveDelete(store);
  });

  it('replays exact advance and rejects a changed amount', async () => {
    const store = await seed('repair-advance-fingerprint');
    const request = advanceRequest(store.id, 100);

    const first = await functions.postRepairAdvance.run(request);
    assert.equal(first.status, 'posted');

    const exact = await functions.postRepairAdvance.run(request);
    assert.equal(exact.status, 'already_posted');

    await assert.rejects(
      functions.postRepairAdvance.run(advanceRequest(store.id, 200)),
      (error) => error.code === 'already-exists',
    );

    const marker = (await store
      .collection('repair_payment_idempotency')
      .doc('advance-1-key')
      .get()).data();
    assert.equal(typeof marker.requestFingerprint, 'string');

    const repair = (await store.collection('repairs')
      .doc('repair-1').get()).data();
    assert.equal(repair.advancePaidMinorUnits, 100);
    assert.equal(repair.paidMinorUnits, 100);
    assert.equal((await store.collection('party_payments').get()).size, 1);
    await db.recursiveDelete(store);
  });
});

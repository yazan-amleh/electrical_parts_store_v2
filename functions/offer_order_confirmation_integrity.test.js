'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'offer-confirm-accountant';
const DATE = '2026-10-29T10:00:00.000Z';

function request(storeId, {
  paymentMethod = 'cash',
  settlementAccountId = '1110',
} = {}) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      orderId: 'order-1',
      idempotencyKey: 'confirm-order-1',
      postedAt: DATE,
      paymentMethod,
      postingAccounts: {
        settlementAccountId:
          paymentMethod === 'credit' ? null : settlementAccountId,
        customerReceivableAccountId: '1140',
        salesAccountId: '4110',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5110',
        taxAccountId: null,
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
    name: 'Offer customer',
    isActive: true,
  });
  for (const [id, type, controlType, normalSide] of [
    ['1110', 'asset', 'cashBox', 'debit'],
    ['1121', 'asset', 'bank', 'debit'],
    ['1140', 'asset', 'customerReceivable', 'debit'],
    ['1150', 'asset', 'inventory', 'debit'],
    ['4110', 'revenue', 'none', 'credit'],
    ['5110', 'expense', 'none', 'debit'],
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
  batch.set(store.collection('products').doc('product-a'), {
    storeId,
    currency: 'ILS',
    isService: false,
    isActive: true,
    quantityOnHandMilliUnits: 3000,
    purchasePriceMinorUnits: 400,
    inventoryValueMinorUnits: 1200,
  });
  batch.set(store.collection('offer_orders').doc('order-1'), {
    storeId,
    orderNumber: 'OO-1',
    offerId: 'offer-1',
    offerNumber: 'OFFER-1',
    customerId: 'customer-1',
    customerName: 'Offer customer',
    status: 'pending',
    currency: 'ILS',
    globalDiscountMinorUnits: 0,
    createdAt: admin.firestore.Timestamp.fromDate(
      new Date('2026-10-28T10:00:00.000Z'),
    ),
    lines: [{
      id: 'line-a',
      productId: 'product-a',
      productName: 'Electrical component',
      originalUnitPriceMinorUnits: 1000,
      finalUnitPriceMinorUnits: 900,
      quantityMilliUnits: 1000,
      unitFactorToBaseMilliUnits: 1000,
      priceType: 'retail',
      unitId: null,
      unitName: null,
      isService: false,
    }],
  });
  await batch.commit();
  return store;
}

describe('offer order confirmation idempotency integrity', () => {
  after(async () => {await admin.app().delete();});

  it('replays the exact confirmation and rejects changed financial details', async () => {
    const store = await seed('offer-confirm-fingerprint');
    const exact = request(store.id);

    const first = await functions.confirmOfferOrder.run(exact);
    assert.equal(first.status, 'confirmed');
    assert.equal(first.saleId, 'sale-offer-order-order-1');

    const retry = await functions.confirmOfferOrder.run(exact);
    assert.equal(retry.status, 'already_confirmed');
    assert.equal(retry.saleId, first.saleId);
    assert.equal(retry.journalEntryId, first.journalEntryId);

    await assert.rejects(
      functions.confirmOfferOrder.run(request(store.id, {
        paymentMethod: 'bank',
        settlementAccountId: '1121',
      })),
      (error) => error.code === 'already-exists',
    );

    const marker = (await store
      .collection('offer_order_confirmation_idempotency')
      .doc('confirm-order-1')
      .get()).data();
    assert.equal(typeof marker.requestFingerprint, 'string');
    assert.ok(marker.requestFingerprint.length > 20);

    const sales = await store.collection('sales').get();
    const journals = await store.collection('journal_entries').get();
    assert.equal(sales.size, 1);
    assert.equal(journals.size, 1);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 2000);
    assert.equal(product.inventoryValueMinorUnits, 800);
    await db.recursiveDelete(store);
  });
});

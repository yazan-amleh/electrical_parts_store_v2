'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'po-receiver-1';
const DATE = '2026-10-08T09:00:00.000Z';

function request(storeId, options = {}) {
  const credit = options.credit === true;
  const tax = options.tax ?? 0;
  return {
    auth: { uid: USER, token: { uid: USER } },
    data: {
      storeId,
      orderId: 'order-1',
      receiptId: options.receiptId ?? 'receipt-1',
      idempotencyKey: options.key ?? 'receipt-key-1',
      postedAt: options.date ?? DATE,
      paymentMethod: credit ? 'credit' : 'cash',
      currency: 'ILS',
      taxMinorUnits: tax,
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        inventoryAccountId: '1150',
        supplierPayableAccountId: credit ? '2110' : null,
        inputTaxAccountId: tax ? '1170' : null,
      },
    },
  };
}

async function seed(storeId, opts = {}) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, { storeId, currency: 'ILS' });
  batch.set(store.collection('members').doc(USER), {
    storeId, userId: USER, isActive: true, role: 'accountant',
  });
  batch.set(store.collection('parties').doc('supplier-1'), {
    storeId, partyType: 'supplier', isActive: true, name: 'Parts Supplier',
  });
  for (const [id, type, controlType] of [
    ['1110', 'asset', 'cashBox'],
    ['1150', 'asset', 'inventory'],
    ['1170', 'asset', 'inputTax'],
    ['2110', 'liability', 'supplierPayable'],
  ]) {
    batch.set(store.collection('accounts').doc(id), {
      id, code: id, name: id, storeId,
      type, controlType, currency: 'ILS',
      isActive: true, isHeader: false,
    });
  }
  batch.set(store.collection('products').doc('product-a'), {
    storeId, currency: 'ILS', isActive: true, isService: false,
    purchasePriceMinorUnits: 600,
    quantityOnHandMilliUnits: 2000,
    inventoryValueMinorUnits: 1200,
  });
  batch.set(store.collection('purchase_orders').doc('order-1'), {
    storeId,
    supplierId: 'supplier-1',
    supplierName: 'Parts Supplier',
    orderNumber: 'PO-001',
    currency: 'ILS',
    status: 'pending',
    lines: [{
      id: 'line-1',
      productId: 'product-a',
      productName: 'Electrical Part',
      unitId: null,
      unitName: null,
      quantityMilliUnits: 1000,
      unitFactorToBaseMilliUnits: 1000,
      unitCostMinorUnits: 700,
      receivedQuantityMilliUnits: opts.receivedQuantity ?? 0,
      totalMinorUnits: 700,
      currency: 'ILS',
    }],
  });
  await batch.commit();
  return store;
}

const receive = (req) => functions.receivePurchaseOrder.run(req);

describe('purchase order receipt atomicity and replay', () => {
  after(async () => { await admin.app().delete(); });

  it('receives exactly once under simultaneous requests', async () => {
    const store = await seed('po-receipt-concurrent');
    const req = request(store.id);
    const results = await Promise.all([receive(req), receive(req)]);
    assert.deepEqual(
      new Set(results.map((r) => r.status)),
      new Set(['received', 'already_received']),
    );
    assert.equal((await store.collection('purchases').get()).size, 1);
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    const order = (await store.collection('purchase_orders').doc('order-1').get()).data();
    const product = (await store.collection('products').doc('product-a').get()).data();
    assert.equal(order.status, 'completed');
    assert.equal(order.receiptId, 'receipt-1');
    assert.equal(product.quantityOnHandMilliUnits, 3000);
    assert.equal(product.inventoryValueMinorUnits, 1900);
    const marker = (await store.collection('purchase_order_receipt_idempotency')
      .doc('receipt-key-1').get()).data();
    assert.match(marker.requestFingerprint, /^[a-f0-9]{64}$/);
    await db.recursiveDelete(store);
  });

  it('rejects changed tax or payment method using the original receipt key', async () => {
    const store = await seed('po-receipt-changed');
    await receive(request(store.id));
    await assert.rejects(
      receive(request(store.id, { tax: 119 })),
      (err) => err.code === 'already-exists',
    );
    await assert.rejects(
      receive(request(store.id, { credit: true })),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('purchases').get()).size, 1);
    assert.equal((await store.collection('account_balances').doc('1150').get())
      .data().debitMinorUnits, 700);
    await db.recursiveDelete(store);
  });

  it('rejects changed receipt ID under the same idempotency key', async () => {
    const store = await seed('po-receipt-different-id');
    await receive(request(store.id));
    await assert.rejects(
      receive(request(store.id, { receiptId: 'receipt-other' })),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('replays pre-fingerprint receipts only after matching historical GL lines', async () => {
    const store = await seed('po-receipt-legacy');
    const req = request(store.id, { credit: true, tax: 119 });
    await receive(req);
    const marker = store.collection('purchase_order_receipt_idempotency')
      .doc('receipt-key-1');
    await marker.update({ requestFingerprint: admin.firestore.FieldValue.delete() });
    assert.equal((await receive(req)).status, 'already_received');
    await assert.rejects(
      receive(request(store.id, { credit: true, tax: 120 })),
      (err) => err.code === 'already-exists',
    );
    await assert.rejects(
      receive(request(store.id)),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('refuses completed orders with a missing marker instead of silent acknowledgement', async () => {
    const store = await seed('po-receipt-marker-missing');
    const req = request(store.id);
    await receive(req);
    await store.collection('purchase_order_receipt_idempotency')
      .doc('receipt-key-1').delete();
    await assert.rejects(
      receive(req),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('rejects malformed persisted received quantities with no financial writes', async () => {
    const store = await seed('po-receipt-corrupt-qty', {
      receivedQuantity: 'invalid',
    });
    await assert.rejects(
      receive(request(store.id)),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects a cancelled order before posting any journal or stock', async () => {
    const store = await seed('po-receipt-cancelled');
    await store.collection('purchase_orders').doc('order-1')
      .update({ status: 'cancelled' });
    await assert.rejects(
      receive(request(store.id)),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

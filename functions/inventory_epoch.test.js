'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'epoch-inventory-owner';
const command = (storeId, id, idempotencyKey = id, quantity = 1000) => ({
  auth: {uid: USER, token: {uid: USER}},
  data: {
    storeId,
    movement: {
      id, idempotencyKey, productId: 'part-a',
      type: 'openingBalance',
      quantityDeltaMilliUnits: quantity,
      unitCostMinorUnits: 150,
      totalCostMinorUnits: 150,
      currency: 'ILS',
      sourceType: 'manual',
      sourceId: null,
      occurredAt: '2026-10-24T09:00:00.000Z',
    },
  },
});
async function setup(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  await store.set({storeId: id, currency: 'ILS'});
  await store.collection('members').doc(USER).set({
    storeId: id, userId: USER, role: 'owner', isActive: true,
  });
  await store.collection('products').doc('part-a').set({
    storeId: id, id: 'part-a', currency: 'ILS',
    isService: false, quantityOnHandMilliUnits: 0,
    inventoryValueMinorUnits: 0, purchasePriceMinorUnits: 150,
  });
  return store;
}
async function totalEpoch(store) {
  const docs = await store.collection('accounting_posting_epochs').get();
  return docs.docs.reduce((sum, item) => sum + item.data().sequence, 0);
}
describe('transactional inventory-only mutation revision', () => {
  after(async () => {await admin.app().delete();});
  it('fences a stock valuation movement once without creating a journal', async () => {
    const store = await setup('inventory-source-epoch');
    const first = await functions.postInventoryMovement.run(
      command(store.id, 'movement-1'));
    assert.equal(first.status, 'posted');
    assert.equal(await totalEpoch(store), 1);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    const repeat = await functions.postInventoryMovement.run(
      command(store.id, 'movement-1'));
    assert.equal(repeat.status, 'already_posted');
    assert.equal(await totalEpoch(store), 1);
    assert.equal((await store.collection('products').doc('part-a').get())
      .data().inventoryValueMinorUnits, 150);
    await db.recursiveDelete(store);
  });

  it('does not increment the fence for invalid negative stock', async () => {
    const store = await setup('inventory-no-partial-epoch');
    await assert.rejects(
      functions.postInventoryMovement.run(
        command(store.id, 'movement-2', 'movement-2', -1000)),
      (error) => error.code === 'failed-precondition');
    assert.equal(await totalEpoch(store), 0);
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    await db.recursiveDelete(store);
  });
});

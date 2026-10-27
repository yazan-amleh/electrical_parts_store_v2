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
async function setup(id, product = {}) {
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
    ...product,
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
    await assert.rejects(
      functions.postInventoryMovement.run(
        command(store.id, 'movement-1', 'movement-1', 2000)),
      (error) => error.code === 'already-exists');
    assert.equal(await totalEpoch(store), 1);
    assert.equal((await store.collection('products').doc('part-a').get())
      .data().inventoryValueMinorUnits, 150);
    await db.recursiveDelete(store);
  });

  it('verifies legacy inventory retries instead of trusting the key alone', async () => {
    const store = await setup('inventory-legacy-idempotency');
    const original = command(store.id, 'movement-legacy');
    await functions.postInventoryMovement.run(original);
    await store.collection('inventory_idempotency').doc('movement-legacy')
      .update({
        requestFingerprint: admin.firestore.FieldValue.delete(),
      });

    assert.equal(
      (await functions.postInventoryMovement.run(original)).status,
      'already_posted',
    );
    await assert.rejects(
      functions.postInventoryMovement.run(
        command(store.id, 'movement-legacy', 'movement-legacy', 2000)),
      (error) => error.code === 'already-exists',
    );
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    assert.equal(await totalEpoch(store), 1);
    await db.recursiveDelete(store);
  });

  it('fails closed on corrupt persisted stock instead of coercing it to zero', async () => {
    const store = await setup('inventory-corrupt-stock', {
      quantityOnHandMilliUnits: '1000',
      inventoryValueMinorUnits: 150,
    });
    await assert.rejects(
      functions.postInventoryMovement.run(
        command(store.id, 'movement-corrupt')),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    assert.equal(await totalEpoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('rejects stock-only sale and purchase return commands', async () => {
    for (const type of ['saleReturn', 'purchaseReturn']) {
      const store = await setup('inventory-block-' + type);
      const req = command(store.id, 'movement-' + type);
      req.data.movement.type = type;
      await assert.rejects(
        functions.postInventoryMovement.run(req),
        (error) => error.code === 'invalid-argument',
      );
      assert.equal((await store.collection('inventory_movements').get())
        .empty, true);
      assert.equal(await totalEpoch(store), 0);
      await db.recursiveDelete(store);
    }
  });

  it('requires exact valuation when an adjustment fully depletes stock', async () => {
    const store = await setup('inventory-full-depletion-value', {
      quantityOnHandMilliUnits: 1000,
      inventoryValueMinorUnits: 151,
    });
    await assert.rejects(
      functions.postInventoryMovement.run(
        command(store.id, 'movement-full-out', 'movement-full-out', -1000)),
      (error) => error.code === 'failed-precondition',
    );
    const product = (await store.collection('products').doc('part-a').get())
      .data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 151);
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    assert.equal(await totalEpoch(store), 0);
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

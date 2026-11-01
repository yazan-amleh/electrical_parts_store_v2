'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'epoch-inventory-owner';
const WAREHOUSE = 'epoch-inventory-warehouse';
const ACCOUNTANT = 'epoch-inventory-accountant';
const command = (
  storeId,
  id,
  idempotencyKey = id,
  quantity = 1000,
  options = {},
) => {
  const unitCost = options.unitCost ?? 150;
  const totalCost = options.totalCost ?? Math.round(
    unitCost * Math.abs(quantity) / 1000,
  );
  const uid = options.uid ?? USER;
  return {
    auth: {uid, token: {uid}},
    data: {
      storeId,
      movement: {
        id,
        idempotencyKey,
        productId: 'part-a',
        type: options.type ?? 'adjustment',
        quantityDeltaMilliUnits: quantity,
        unitCostMinorUnits: unitCost,
        totalCostMinorUnits: totalCost,
        currency: 'ILS',
        sourceType: 'manual',
        sourceId: null,
        occurredAt: '2026-10-24T09:00:00.000Z',
      },
    },
  };
};
async function setup(id, product = {}) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  await store.set({storeId: id, currency: 'ILS'});
  await store.collection('members').doc(USER).set({
    storeId: id, userId: USER, role: 'owner', isActive: true,
  });
  await store.collection('members').doc(WAREHOUSE).set({
    storeId: id, userId: WAREHOUSE, role: 'warehouse', isActive: true,
  });
  await store.collection('members').doc(ACCOUNTANT).set({
    storeId: id, userId: ACCOUNTANT, role: 'accountant', isActive: true,
  });
  await store.collection('products').doc('part-a').set({
    storeId: id, id: 'part-a', currency: 'ILS',
    isService: false, quantityOnHandMilliUnits: 0,
    inventoryValueMinorUnits: 0, purchasePriceMinorUnits: 150,
    ...product,
  });
  return store;
}
async function seedOpeningAccounts(store) {
  const batch = db.batch();
  batch.set(store.collection('accounts').doc('1150'), {
    storeId: store.id,
    id: '1150',
    code: '1150',
    name: 'Inventory',
    type: 'asset',
    normalSide: 'debit',
    controlType: 'inventory',
    statementSection: 'assets',
    parentId: '1100',
    currency: 'ILS',
    isHeader: false,
    isActive: true,
    sortOrder: 150,
  });
  batch.set(store.collection('accounts').doc('3400'), {
    storeId: store.id,
    id: '3400',
    code: '3400',
    name: 'Opening Balance Equity',
    type: 'equity',
    normalSide: 'credit',
    controlType: 'none',
    statementSection: 'equity',
    parentId: '3100',
    currency: 'ILS',
    isHeader: false,
    isActive: true,
    sortOrder: 420,
  });
  await batch.commit();
}

async function totalEpoch(store) {
  const docs = await store.collection('accounting_posting_epochs').get();
  return docs.docs.reduce((sum, item) => sum + item.data().sequence, 0);
}
describe('transactional inventory-only mutation revision', () => {
  after(async () => {await admin.app().delete();});
  it('fences a manual adjustment once without creating a journal', async () => {
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

  it('posts opening inventory and its GL entry atomically exactly once', async () => {
    const store = await setup('inventory-opening-accounted');
    await seedOpeningAccounts(store);
    const req = command(
      store.id,
      'movement-opening',
      'movement-opening',
      1000,
      {type: 'openingBalance'},
    );

    const first = await functions.postInventoryMovement.run(req);
    assert.equal(first.status, 'posted');
    assert.equal(first.journalEntryId, 'movement-opening-opening-journal');

    const product = (await store.collection('products').doc('part-a').get())
      .data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 150);

    const movement = (await store.collection('inventory_movements')
      .doc('movement-opening').get()).data();
    assert.equal(movement.journalEntryId, 'movement-opening-opening-journal');

    const journal = (await store.collection('journal_entries')
      .doc('movement-opening-opening-journal').get()).data();
    assert.equal(journal.sourceType, 'openingInventory');
    assert.equal(journal.totalDebitMinorUnits, 150);
    assert.equal(journal.totalCreditMinorUnits, 150);

    const lines = await store.collection('journal_entries')
      .doc('movement-opening-opening-journal').collection('lines').get();
    assert.equal(lines.size, 2);
    const inventoryLine = lines.docs.find((item) =>
      item.data().accountId === '1150').data();
    const equityLine = lines.docs.find((item) =>
      item.data().accountId === '3400').data();
    assert.equal(inventoryLine.debitMinorUnits, 150);
    assert.equal(inventoryLine.creditMinorUnits, 0);
    assert.equal(equityLine.debitMinorUnits, 0);
    assert.equal(equityLine.creditMinorUnits, 150);

    const inventoryBalance = (await store.collection('account_balances')
      .doc('1150').get()).data();
    const equityBalance = (await store.collection('account_balances')
      .doc('3400').get()).data();
    assert.equal(inventoryBalance.debitMinorUnits, 150);
    assert.equal(inventoryBalance.creditMinorUnits, 0);
    assert.equal(inventoryBalance.balanceMinorUnits, 150);
    assert.equal(equityBalance.debitMinorUnits, 0);
    assert.equal(equityBalance.creditMinorUnits, 150);
    assert.equal(equityBalance.balanceMinorUnits, -150);
    assert.equal(await totalEpoch(store), 1);

    const repeat = await functions.postInventoryMovement.run(req);
    assert.equal(repeat.status, 'already_posted');
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    assert.equal(await totalEpoch(store), 1);
    await db.recursiveDelete(store);
  });

  it('fails opening inventory closed when chart prerequisites are missing', async () => {
    const store = await setup('inventory-opening-missing-chart');
    await assert.rejects(
      functions.postInventoryMovement.run(command(
        store.id,
        'opening-missing-chart',
        'opening-missing-chart',
        1000,
        {type: 'openingBalance'},
      )),
      (error) => error.code === 'invalid-argument',
    );
    const product = (await store.collection('products').doc('part-a').get())
      .data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal(await totalEpoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('rejects repeated opening inventory on a non-empty product', async () => {
    const store = await setup('inventory-opening-nonempty', {
      quantityOnHandMilliUnits: 1000,
      inventoryValueMinorUnits: 150,
    });
    await seedOpeningAccounts(store);
    await assert.rejects(
      functions.postInventoryMovement.run(command(
        store.id,
        'opening-nonempty',
        'opening-nonempty',
        1000,
        {type: 'openingBalance'},
      )),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal(await totalEpoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('limits opening inventory to accounting-capable roles', async () => {
    const store = await setup('inventory-opening-role');
    await seedOpeningAccounts(store);
    await assert.rejects(
      functions.postInventoryMovement.run(command(
        store.id,
        'opening-warehouse',
        'opening-warehouse',
        1000,
        {type: 'openingBalance', uid: WAREHOUSE},
      )),
      (error) => error.code === 'permission-denied',
    );

    const accountant = await functions.postInventoryMovement.run(command(
      store.id,
      'opening-accountant',
      'opening-accountant',
      1000,
      {type: 'openingBalance', uid: ACCOUNTANT},
    ));
    assert.equal(accountant.status, 'posted');
    assert.equal(await totalEpoch(store), 1);
    await db.recursiveDelete(store);
  });

  it('rejects a negative opening inventory quantity', async () => {
    const store = await setup('inventory-opening-negative');
    await seedOpeningAccounts(store);
    await assert.rejects(
      functions.postInventoryMovement.run(command(
        store.id,
        'opening-negative',
        'opening-negative',
        -1000,
        {type: 'openingBalance'},
      )),
      (error) => error.code === 'invalid-argument',
    );
    assert.equal((await store.collection('inventory_movements').get())
      .empty, true);
    assert.equal(await totalEpoch(store), 0);
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

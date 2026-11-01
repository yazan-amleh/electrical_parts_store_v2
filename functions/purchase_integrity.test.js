'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'purchase-accountant';
const DATE = '2026-10-05T12:00:00.000Z';
const invoke = (request) => functions.postPurchase.run(request);

function request(storeId, id, key, options = {}) {
  const credit = options.credit === true;
  return {
    auth: { uid: USER, token: { uid: USER } },
    data: {
      storeId,
      purchase: {
        id,
        idempotencyKey: key,
        postedAt: DATE,
        paymentMethod: credit ? 'credit' : 'cash',
        supplierId: credit ? 'supplier-1' : null,
        description: 'V2 stock receipt',
        currency: 'ILS',
        taxMinorUnits: options.tax ?? 0,
        lines: [{
          id: 'line-a',
          productId: 'product-a',
          description: 'Electrical component',
          quantityMilliUnits: 1000,
          unitFactorToBaseMilliUnits: 1000,
          unitCostMinorUnits: options.cost ?? 700,
          discountMinorUnits: 0,
          unitId: null,
          unitName: null,
        }],
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        inventoryAccountId: '1150',
        supplierPayableAccountId: credit ? '2110' : null,
        inputTaxAccountId: options.tax ? '1170' : null,
      },
    },
  };
}

async function seed(storeId, product = {}) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  batch.set(ref, { storeId, currency: 'ILS' });
  batch.set(ref.collection('members').doc(USER), {
    storeId, userId: USER, isActive: true, role: 'accountant',
  });
  batch.set(ref.collection('parties').doc('supplier-1'), {
    storeId, partyType: 'supplier', isActive: true, name: 'Parts supplier',
  });
  for (const [id, type, controlType] of [
    ['1110', 'asset', 'cashBox'],
    ['1150', 'asset', 'inventory'],
    ['1170', 'asset', 'inputTax'],
    ['2110', 'liability', 'supplierPayable'],
  ]) {
    batch.set(ref.collection('accounts').doc(id), {
      storeId, id, code: id, name: id, type,
      controlType, currency: 'ILS', isHeader: false, isActive: true,
    });
  }
  batch.set(ref.collection('products').doc('product-a'), {
    storeId, isActive: true, isService: false, currency: 'ILS',
    quantityOnHandMilliUnits: 1000,
    purchasePriceMinorUnits: 1000,
    inventoryValueMinorUnits: 1001,
    ...product,
  });
  await batch.commit();
  return ref;
}

describe('purchase stock and accounting integrity', () => {
  after(async () => { await admin.app().delete(); });

  it('posts an inventory purchase exactly once even under concurrent retries', async () => {
    const store = await seed('purchase-concurrent');
    const req = request(store.id, 'purchase-1', 'purchase-key-1');
    const result = await Promise.all([invoke(req), invoke(req)]);
    assert.deepEqual(new Set(result.map((x) => x.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await store.collection('purchases').get()).size, 1);
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    const product = (await store.collection('products').doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 2000);
    // 1001 persisted value + 700 received = 1701; never recompute from
    // previous average cost 1000 (which would lose 1 minor unit).
    assert.equal(product.inventoryValueMinorUnits, 1701);
    assert.equal((await store.collection('account_balances').doc('1150').get())
      .data().debitMinorUnits, 700);
    assert.equal((await store.collection('account_balances').doc('1110').get())
      .data().balanceMinorUnits, -700);
    await db.recursiveDelete(store);
  });

  it('cannot reuse key with changed purchase unit cost or posting identity', async () => {
    const store = await seed('purchase-changed-retry');
    await invoke(request(store.id, 'purchase-2', 'purchase-key-2'));
    await assert.rejects(
      invoke(request(store.id, 'purchase-2', 'purchase-key-2', { cost: 750 })),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('purchases').get()).size, 1);
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('checks full legacy invoice and journal lines on pre-fingerprint replay', async () => {
    const store = await seed('purchase-legacy');
    const req = request(store.id, 'purchase-3', 'purchase-key-3');
    await invoke(req);
    await store.collection('purchase_idempotency').doc('purchase-key-3').update({
      requestFingerprint: admin.firestore.FieldValue.delete(),
    });
    assert.equal((await invoke(req)).status, 'already_posted');
    await assert.rejects(
      invoke(request(store.id, 'purchase-3', 'purchase-key-3', { cost: 750 })),
      (err) => err.code === 'already-exists',
    );
    await db.recursiveDelete(store);
  });

  it('credit purchase with tax updates supplier payable and balanced journal', async () => {
    const store = await seed('purchase-credit-tax');
    const req = request(store.id, 'purchase-4', 'purchase-key-4', {
      credit: true, tax: 119,
    });
    assert.equal((await invoke(req)).status, 'posted');
    const party = (await store.collection('party_balances')
      .doc('supplier-supplier-1').get()).data();
    assert.equal(party.creditMinorUnits, 819);
    assert.equal(party.balanceMinorUnits, -819);
    const inventory = (await store.collection('account_balances')
      .doc('1150').get()).data();
    const inputTax = (await store.collection('account_balances')
      .doc('1170').get()).data();
    const payable = (await store.collection('account_balances')
      .doc('2110').get()).data();
    assert.equal(inventory.debitMinorUnits, 700);
    assert.equal(inputTax.debitMinorUnits, 119);
    assert.equal(payable.creditMinorUnits, 819);
    assert.equal((await store.collection('journal_entries')
      .doc('purchase-4-journal').collection('lines').get()).size, 3);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt supplier balance without partial purchase or stock change', async () => {
    const store = await seed('purchase-corrupt-party');
    await store.collection('party_balances').doc('supplier-supplier-1').set({
      storeId: store.id, partyId: 'supplier-1', partyType: 'supplier',
      currency: 'ILS', debitMinorUnits: 0, creditMinorUnits: 500,
      balanceMinorUnits: 0,
    });
    await assert.rejects(
      invoke(request(store.id, 'purchase-5', 'purchase-key-5', { credit: true })),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    assert.equal((await store.collection('products').doc('product-a').get())
      .data().quantityOnHandMilliUnits, 1000);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt stock valuation and keeps all records unchanged', async () => {
    const store = await seed('purchase-corrupt-stock', {
      inventoryValueMinorUnits: '1001',
    });
    await assert.rejects(
      invoke(request(store.id, 'purchase-6', 'purchase-key-6')),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects tax-inclusive total beyond safe integer range', async () => {
    const store = await seed('purchase-unsafe-tax');
    await assert.rejects(
      invoke(request(store.id, 'purchase-7', 'purchase-key-7', {
        tax: Number.MAX_SAFE_INTEGER,
      })),
      (err) => err.code === 'invalid-argument',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects mismatched GL projection without masking it as zero', async () => {
    const store = await seed('purchase-corrupt-gl');
    await store.collection('account_balances').doc('1150').set({
      storeId: store.id, accountId: '1150', currency: 'ILS',
      debitMinorUnits: 400, creditMinorUnits: 0, balanceMinorUnits: 0,
    });
    await assert.rejects(
      invoke(request(store.id, 'purchase-8', 'purchase-key-8')),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('purchases').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

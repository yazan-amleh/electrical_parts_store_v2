'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'sale-accountant';
const DATE = '2026-10-06T13:00:00.000Z';
const invoke = (req) => functions.postSale.run(req);

function request(storeId, id, key, options = {}) {
  const credit = options.credit === true;
  const tax = options.tax ?? 0;
  return {
    auth: { uid: USER, token: { uid: USER } },
    data: {
      storeId,
      sale: {
        id,
        idempotencyKey: key,
        postedAt: DATE,
        paymentMethod: credit ? 'credit' : 'cash',
        customerId: credit ? 'customer-1' : null,
        description: 'V2 electrical part sale',
        currency: 'ILS',
        taxMinorUnits: tax,
        lines: [{
          id: 'line-a',
          productId: 'product-a',
          description: 'Electrical component',
          quantityMilliUnits: options.quantity ?? 1000,
          unitFactorToBaseMilliUnits: 1000,
          unitPriceMinorUnits: options.price ?? 900,
          unitCostMinorUnits: options.service ? 0 : 400,
          discountMinorUnits: 0,
          unitId: null,
          unitName: null,
          isService: options.service === true,
        }],
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        customerReceivableAccountId: credit ? '1140' : null,
        salesAccountId: '4110',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5110',
        taxAccountId: tax || options.keepOptionalTax ? '2120' : null,
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
    storeId, userId: USER, role: 'accountant', isActive: true,
  });
  batch.set(ref.collection('parties').doc('customer-1'), {
    storeId, partyType: 'customer', name: 'Test customer', isActive: true,
  });
  for (const [id, type, controlType] of [
    ['1110', 'asset', 'cashBox'],
    ['1140', 'asset', 'customerReceivable'],
    ['1150', 'asset', 'inventory'],
    ['4110', 'revenue', 'none'],
    ['5110', 'expense', 'none'],
    ['2120', 'liability', 'tax'],
  ]) {
    batch.set(ref.collection('accounts').doc(id), {
      storeId, id, code: id, name: id, type, controlType,
      currency: 'ILS', isHeader: false, isActive: true,
    });
  }
  batch.set(ref.collection('products').doc('product-a'), {
    storeId, currency: 'ILS', isService: false, isActive: true,
    quantityOnHandMilliUnits: 3000,
    purchasePriceMinorUnits: 400,
    inventoryValueMinorUnits: 1200,
    ...product,
  });
  await batch.commit();
  return ref;
}

describe('sales inventory, journal and receivable integrity', () => {
  after(async () => { await admin.app().delete(); });

  it('posts a cash sale once with balanced revenue, COGS and stock', async () => {
    const store = await seed('sale-cash-concurrent');
    const req = request(store.id, 'sale-1', 'sale-key-1');
    const answers = await Promise.all([invoke(req), invoke(req)]);
    assert.deepEqual(new Set(answers.map((x) => x.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await store.collection('sales').get()).size, 1);
    assert.equal((await store.collection('inventory_movements').get()).size, 1);
    const stock = (await store.collection('products').doc('product-a').get()).data();
    assert.equal(stock.quantityOnHandMilliUnits, 2000);
    assert.equal(stock.inventoryValueMinorUnits, 800);
    const balances = await store.collection('account_balances').get();
    assert.equal(balances.docs.reduce((total, doc) =>
      total + doc.data().balanceMinorUnits, 0), 0);
    const lines = await store.collection('journal_entries')
      .doc('sale-1-journal').collection('lines').get();
    assert.equal(lines.size, 4);
    assert.deepEqual([...lines.docs.map((d) => d.data().lineNumber)].sort(),
      [1, 2, 3, 4]);
    await db.recursiveDelete(store);
  });

  it('rejects a changed line price despite the same sale key and ID', async () => {
    const store = await seed('sale-changed-replay');
    await invoke(request(store.id, 'sale-2', 'sale-key-2'));
    await assert.rejects(
      invoke(request(store.id, 'sale-2', 'sale-key-2', { price: 950 })),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await store.collection('sales').get()).size, 1);
    assert.equal((await store.collection('account_balances').doc('4110').get())
      .data().creditMinorUnits, 900);
    await db.recursiveDelete(store);
  });

  it('replays historical fingerprintless sales after verifying every journal line', async () => {
    const store = await seed('sale-legacy-replay');
    const req = request(store.id, 'sale-3', 'sale-key-3');
    await invoke(req);
    await store.collection('sale_idempotency').doc('sale-key-3').update({
      requestFingerprint: admin.firestore.FieldValue.delete(),
    });
    assert.equal((await invoke(req)).status, 'already_posted');
    await assert.rejects(
      invoke(request(store.id, 'sale-3', 'sale-key-3', { price: 951 })),
      (err) => err.code === 'already-exists',
    );
    await db.recursiveDelete(store);
  });

  it('credit sale with tax creates matching customer receivable and GL', async () => {
    const store = await seed('sale-credit-tax');
    assert.equal((await invoke(request(store.id, 'sale-4', 'sale-key-4', {
      credit: true, tax: 153,
    }))).status, 'posted');
    const customer = (await store.collection('party_balances')
      .doc('customer-customer-1').get()).data();
    assert.equal(customer.debitMinorUnits, 1053);
    assert.equal(customer.balanceMinorUnits, 1053);
    const receivable = (await store.collection('account_balances')
      .doc('1140').get()).data();
    assert.equal(receivable.debitMinorUnits, 1053);
    const tax = (await store.collection('account_balances')
      .doc('2120').get()).data();
    assert.equal(tax.creditMinorUnits, 153);
    await db.recursiveDelete(store);
  });

  it('service-only sale safely posts without COGS or inventory movements', async () => {
    const store = await seed('sale-service-zero-deltas', {
      isService: true,
      quantityOnHandMilliUnits: 0,
      purchasePriceMinorUnits: 0,
      inventoryValueMinorUnits: 0,
    });
    const response = await invoke(request(
      store.id, 'sale-service', 'sale-service-key',
      { service: true, keepOptionalTax: true },
    ));
    assert.equal(response.status, 'posted');
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    const journal = (await store.collection('journal_entries')
      .doc('sale-service-journal').get()).data();
    assert.equal(journal.totalDebitMinorUnits, 900);
    assert.equal(journal.totalCreditMinorUnits, 900);
    assert.equal((await store.collection('journal_entries')
      .doc('sale-service-journal').collection('lines').get()).size, 2);
    assert.equal((await store.collection('account_balances').doc('5110').get())
      .data().balanceMinorUnits, 0);
    await db.recursiveDelete(store);
  });

  it('allocates a positive valuation remainder to COGS on full depletion', async () => {
    const store = await seed('sale-full-depletion-positive-rounding', {
      inventoryValueMinorUnits: 1201,
    });
    const response = await invoke(request(
      store.id,
      'sale-full-positive',
      'sale-full-positive-key',
      { quantity: 3000 },
    ));
    assert.equal(response.status, 'posted');

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);

    const sale = (await store.collection('sales')
      .doc('sale-full-positive').get()).data();
    assert.equal(sale.costTotalMinorUnits, 1201);
    assert.equal(sale.lines[0].costTotalMinorUnits, 1201);
    assert.equal(sale.lines[0].costAllocationAdjustmentMinorUnits, 1);

    const movement = (await store.collection('inventory_movements')
      .doc('sale-full-positive-inventory-line-a').get()).data();
    assert.equal(movement.totalCostMinorUnits, 1201);

    const cogs = (await store.collection('account_balances')
      .doc('5110').get()).data();
    const inventory = (await store.collection('account_balances')
      .doc('1150').get()).data();
    assert.equal(cogs.debitMinorUnits, 1201);
    assert.equal(inventory.creditMinorUnits, 1201);
    await db.recursiveDelete(store);
  });

  it('reduces rounded COGS to exact inventory value on full depletion', async () => {
    const store = await seed('sale-full-depletion-negative-rounding', {
      inventoryValueMinorUnits: 1199,
    });
    const response = await invoke(request(
      store.id,
      'sale-full-negative',
      'sale-full-negative-key',
      { quantity: 3000 },
    ));
    assert.equal(response.status, 'posted');

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);

    const sale = (await store.collection('sales')
      .doc('sale-full-negative').get()).data();
    assert.equal(sale.costTotalMinorUnits, 1199);
    assert.equal(sale.lines[0].costTotalMinorUnits, 1199);
    assert.equal(sale.lines[0].costAllocationAdjustmentMinorUnits, -1);

    const movement = (await store.collection('inventory_movements')
      .doc('sale-full-negative-inventory-line-a').get()).data();
    assert.equal(movement.totalCostMinorUnits, 1199);

    const cogs = (await store.collection('account_balances')
      .doc('5110').get()).data();
    const inventory = (await store.collection('account_balances')
      .doc('1150').get()).data();
    assert.equal(cogs.debitMinorUnits, 1199);
    assert.equal(inventory.creditMinorUnits, 1199);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt inventory valuation before an invoice is committed', async () => {
    const store = await seed('sale-stock-corrupt', {
      inventoryValueMinorUnits: '1200',
    });
    await assert.rejects(
      invoke(request(store.id, 'sale-5', 'sale-key-5')),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('sales').get()).empty, true);
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt customer projection with no invoice or stock change', async () => {
    const store = await seed('sale-customer-corrupt');
    await store.collection('party_balances').doc('customer-customer-1').set({
      storeId: store.id, partyType: 'customer', partyId: 'customer-1',
      currency: 'ILS', debitMinorUnits: 20, creditMinorUnits: 0,
      balanceMinorUnits: 0,
    });
    await assert.rejects(
      invoke(request(store.id, 'sale-6', 'sale-key-6', { credit: true })),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('sales').get()).empty, true);
    assert.equal((await store.collection('products').doc('product-a').get())
      .data().quantityOnHandMilliUnits, 3000);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt GL balance without writing a partial sale', async () => {
    const store = await seed('sale-gl-corrupt');
    await store.collection('account_balances').doc('1150').set({
      storeId: store.id, accountId: '1150', currency: 'ILS',
      debitMinorUnits: 100, creditMinorUnits: 0,
      balanceMinorUnits: 0,
    });
    await assert.rejects(
      invoke(request(store.id, 'sale-7', 'sale-key-7')),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('sales').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects stock shortages without financial or inventory mutations', async () => {
    const store = await seed('sale-stock-shortage', {
      quantityOnHandMilliUnits: 500,
      purchasePriceMinorUnits: 400,
      inventoryValueMinorUnits: 200,
    });
    await assert.rejects(
      invoke(request(store.id, 'sale-8', 'sale-key-8')),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await store.collection('sales').get()).empty, true);
    assert.equal((await store.collection('inventory_movements').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects invoice totals that exceed Javascript safe integer range', async () => {
    const store = await seed('sale-unsafe-total');
    await assert.rejects(
      invoke(request(store.id, 'sale-9', 'sale-key-9', {
        tax: Number.MAX_SAFE_INTEGER,
      })),
      (err) => err.code === 'invalid-argument',
    );
    assert.equal((await store.collection('sales').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'sale-return-accountant';
const SALE_DATE = '2026-10-27T10:00:00.000Z';
const RETURN_DATE = '2026-10-28T10:00:00.000Z';

function saleRequest(storeId, {
  credit = false,
  tax = 0,
  quantity = 1000,
  price = 900,
  lines = null,
} = {}) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      sale: {
        id: 'sale-original',
        idempotencyKey: 'sale-original-key',
        postedAt: SALE_DATE,
        paymentMethod: credit ? 'credit' : 'cash',
        customerId: credit ? 'customer-1' : null,
        description: 'Original sale',
        currency: 'ILS',
        taxMinorUnits: tax,
        lines: lines ?? [{
          id: 'line-a',
          productId: 'product-a',
          description: 'Electrical component',
          quantityMilliUnits: quantity,
          unitFactorToBaseMilliUnits: 1000,
          unitPriceMinorUnits: price,
          unitCostMinorUnits: 400,
          discountMinorUnits: 0,
          unitId: null,
          unitName: null,
          isService: false,
        }],
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        customerReceivableAccountId: credit ? '1140' : null,
        salesAccountId: '4110',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5110',
        taxAccountId: tax > 0 ? '2120' : null,
      },
    },
  };
}

function purchaseRequest(storeId) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      purchase: {
        id: 'purchase-after-sale',
        idempotencyKey: 'purchase-after-sale-key',
        postedAt: '2026-10-27T12:00:00.000Z',
        paymentMethod: 'cash',
        supplierId: null,
        description: 'Intervening stock receipt',
        currency: 'ILS',
        taxMinorUnits: 0,
        lines: [{
          id: 'purchase-line-a',
          productId: 'product-a',
          description: 'Electrical component',
          quantityMilliUnits: 1000,
          unitFactorToBaseMilliUnits: 1000,
          unitCostMinorUnits: 700,
          discountMinorUnits: 0,
          unitId: null,
          unitName: null,
        }],
      },
      postingAccounts: {
        settlementAccountId: '1110',
        inventoryAccountId: '1150',
        supplierPayableAccountId: null,
        inputTaxAccountId: null,
      },
    },
  };
}

function returnRequest(storeId, {
  id = 'return-1',
  key = 'return-key-1',
  reason = 'Customer return',
  credit = false,
  tax = 0,
  postedAt = RETURN_DATE,
  lines = null,
} = {}) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      saleReturn: {
        id,
        idempotencyKey: key,
        originalSaleId: 'sale-original',
        postedAt,
        reason,
        lines,
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        customerReceivableAccountId: credit ? '1140' : null,
        salesReturnsAccountId: '4200',
        inventoryAccountId: '1150',
        costOfSalesAccountId: '5110',
        taxAccountId: tax > 0 ? '2120' : null,
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
    storeId, userId: USER, role: 'accountant', isActive: true,
  });
  batch.set(store.collection('parties').doc('customer-1'), {
    storeId, partyType: 'customer', name: 'Customer', isActive: true,
  });
  const accounts = [
    ['1110', 'asset', 'cashBox', 'debit'],
    ['1140', 'asset', 'customerReceivable', 'debit'],
    ['1150', 'asset', 'inventory', 'debit'],
    ['4110', 'revenue', 'none', 'credit'],
    ['4200', 'revenue', 'none', 'debit'],
    ['5110', 'expense', 'none', 'debit'],
    ['2120', 'liability', 'tax', 'credit'],
  ];
  for (const [id, type, controlType, normalSide] of accounts) {
    batch.set(store.collection('accounts').doc(id), {
      storeId, id, code: id, name: id, type, controlType, normalSide,
      currency: 'ILS', isHeader: false, isActive: true,
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
  await batch.commit();
  return store;
}

describe('atomic full sale returns', () => {
  after(async () => { await admin.app().delete(); });

  it('fully reverses a cash sale and restores exact inventory value', async () => {
    const store = await seed('sale-return-cash');
    await functions.postSale.run(saleRequest(store.id));

    const result = await functions.postSaleReturn.run(returnRequest(store.id));
    assert.equal(result.status, 'returned');

    const product = (await store.collection('products').doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 3000);
    assert.equal(product.inventoryValueMinorUnits, 1200);

    const original = (await store.collection('sales').doc('sale-original').get()).data();
    assert.equal(original.returnStatus, 'full');
    assert.equal(original.returnId, 'return-1');

    const returned = (await store.collection('sales_returns').doc('return-1').get()).data();
    assert.equal(returned.totalMinorUnits, 900);
    assert.equal(returned.costTotalMinorUnits, 400);

    assert.equal((await store.collection('account_balances').doc('1110').get())
      .data().balanceMinorUnits, 0);
    assert.equal((await store.collection('account_balances').doc('1150').get())
      .data().balanceMinorUnits, 0);
    assert.equal((await store.collection('account_balances').doc('5110').get())
      .data().balanceMinorUnits, 0);
    assert.equal((await store.collection('account_balances').doc('4110').get())
      .data().balanceMinorUnits, -900);
    assert.equal((await store.collection('account_balances').doc('4200').get())
      .data().balanceMinorUnits, 900);

    const returnJournal = (await store.collection('journal_entries')
      .doc('return-1-journal').get()).data();
    assert.equal(returnJournal.totalDebitMinorUnits, 1300);
    assert.equal(returnJournal.totalCreditMinorUnits, 1300);
    await db.recursiveDelete(store);
  });

  it('recomputes weighted average cost after an intervening purchase', async () => {
    const store = await seed('sale-return-weighted-average');
    await functions.postSale.run(saleRequest(store.id));
    await functions.postPurchase.run(purchaseRequest(store.id));

    const beforeReturn = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(beforeReturn.quantityOnHandMilliUnits, 3000);
    assert.equal(beforeReturn.inventoryValueMinorUnits, 1500);
    assert.equal(beforeReturn.purchasePriceMinorUnits, 500);

    await functions.postSaleReturn.run(returnRequest(store.id));
    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 4000);
    assert.equal(product.inventoryValueMinorUnits, 1900);
    assert.equal(product.purchasePriceMinorUnits, 475);
    await db.recursiveDelete(store);
  });

  it('posts a partial return and later returns the exact remainder', async () => {
    const store = await seed('sale-return-partial-complete');
    await functions.postSale.run(saleRequest(store.id, {
      tax: 300,
      quantity: 3000,
    }));

    const first = await functions.postSaleReturn.run(returnRequest(store.id, {
      id: 'return-partial-1',
      key: 'return-partial-key-1',
      tax: 300,
      lines: [{lineId: 'line-a', quantityMilliUnits: 1000}],
    }));
    assert.equal(first.status, 'returned');
    assert.equal(first.returnStatus, 'partial');

    let original = (await store.collection('sales')
      .doc('sale-original').get()).data();
    assert.equal(original.returnStatus, 'partial');
    assert.equal(original.returnedSubtotalMinorUnits, 900);
    assert.equal(original.returnedTaxMinorUnits, 100);
    assert.equal(original.returnedCostMinorUnits, 400);
    assert.equal(original.returnedLines[0].returnedQuantityMilliUnits, 1000);

    let product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 400);

    const partialDoc = (await store.collection('sales_returns')
      .doc('return-partial-1').get()).data();
    assert.equal(partialDoc.returnType, 'partial');
    assert.equal(partialDoc.subtotalMinorUnits, 900);
    assert.equal(partialDoc.taxMinorUnits, 100);
    assert.equal(partialDoc.totalMinorUnits, 1000);
    assert.equal(partialDoc.costTotalMinorUnits, 400);
    assert.equal(partialDoc.completedOriginalSale, false);

    const completion = await functions.postSaleReturn.run(returnRequest(
      store.id,
      {
        id: 'return-remainder',
        key: 'return-remainder-key',
        tax: 300,
      },
    ));
    assert.equal(completion.returnStatus, 'full');

    original = (await store.collection('sales')
      .doc('sale-original').get()).data();
    assert.equal(original.returnStatus, 'full');
    assert.equal(original.returnedSubtotalMinorUnits, 2700);
    assert.equal(original.returnedTaxMinorUnits, 300);
    assert.equal(original.returnedCostMinorUnits, 1200);
    assert.equal(original.returnIds.length, 2);

    product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 3000);
    assert.equal(product.inventoryValueMinorUnits, 1200);
    await db.recursiveDelete(store);
  });

  it('serializes competing partial returns and prevents over-return', async () => {
    const store = await seed('sale-return-partial-race');
    await functions.postSale.run(saleRequest(store.id, {quantity: 3000}));

    const first = returnRequest(store.id, {
      id: 'return-race-a',
      key: 'return-race-key-a',
      lines: [{lineId: 'line-a', quantityMilliUnits: 2000}],
    });
    const second = returnRequest(store.id, {
      id: 'return-race-b',
      key: 'return-race-key-b',
      lines: [{lineId: 'line-a', quantityMilliUnits: 2000}],
    });
    const results = await Promise.allSettled([
      functions.postSaleReturn.run(first),
      functions.postSaleReturn.run(second),
    ]);

    const fulfilled = results.filter((result) => result.status === 'fulfilled');
    const rejected = results.filter((result) => result.status === 'rejected');
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.equal(rejected[0].reason.code, 'failed-precondition');

    const original = (await store.collection('sales')
      .doc('sale-original').get()).data();
    assert.equal(original.returnStatus, 'partial');
    assert.equal(original.returnedLines[0].returnedQuantityMilliUnits, 2000);
    assert.equal((await store.collection('sales_returns').get()).size, 1);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 2000);
    assert.equal(product.inventoryValueMinorUnits, 800);
    await db.recursiveDelete(store);
  });

  it('allocates tiny header tax cumulatively across partial returns', async () => {
    const store = await seed('sale-return-partial-tax-rounding');
    await functions.postSale.run(saleRequest(store.id, {
      tax: 1,
      quantity: 3000,
      price: 100,
    }));

    const taxParts = [];
    for (let index = 0; index < 3; index++) {
      const response = await functions.postSaleReturn.run(returnRequest(
        store.id,
        {
          id: 'tax-return-' + index,
          key: 'tax-return-key-' + index,
          tax: 1,
          lines: [{lineId: 'line-a', quantityMilliUnits: 1000}],
        },
      ));
      const row = (await store.collection('sales_returns')
        .doc(response.returnId).get()).data();
      taxParts.push(row.taxMinorUnits);
    }
    assert.deepEqual(taxParts, [0, 1, 0]);
    assert.equal(taxParts.reduce((sum, value) => sum + value, 0), 1);

    const original = (await store.collection('sales')
      .doc('sale-original').get()).data();
    assert.equal(original.returnStatus, 'full');
    assert.equal(original.returnedTaxMinorUnits, 1);
    await db.recursiveDelete(store);
  });

  it('is idempotent under concurrent retries', async () => {
    const store = await seed('sale-return-concurrent');
    await functions.postSale.run(saleRequest(store.id));
    const req = returnRequest(store.id);
    const results = await Promise.all([
      functions.postSaleReturn.run(req),
      functions.postSaleReturn.run(req),
    ]);
    assert.deepEqual(
      new Set(results.map((value) => value.status)),
      new Set(['returned', 'already_returned']),
    );
    assert.equal((await store.collection('sales_returns').get()).size, 1);
    assert.equal((await store.collection('inventory_movements')
      .where('sourceType', '==', 'saleReturn').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('rejects a changed retry and a second distinct full return', async () => {
    const store = await seed('sale-return-conflicts');
    await functions.postSale.run(saleRequest(store.id));
    await functions.postSaleReturn.run(returnRequest(store.id));

    await assert.rejects(
      functions.postSaleReturn.run(returnRequest(store.id, {
        reason: 'Changed reason',
      })),
      (error) => error.code === 'already-exists',
    );
    await assert.rejects(
      functions.postSaleReturn.run(returnRequest(store.id, {
        id: 'return-2',
        key: 'return-key-2',
      })),
      (error) => error.code === 'already-exists',
    );
    assert.equal((await store.collection('sales_returns').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('rejects a return dated before the original sale', async () => {
    const store = await seed('sale-return-backdated');
    await functions.postSale.run(saleRequest(store.id));
    await assert.rejects(
      functions.postSaleReturn.run(returnRequest(store.id, {
        postedAt: '2026-10-26T10:00:00.000Z',
      })),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('sales_returns').get()).empty, true);
    assert.equal((await store.collection('inventory_movements')
      .where('sourceType', '==', 'saleReturn').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('fails closed when the original sale journal no longer reconciles', async () => {
    const store = await seed('sale-return-corrupt-journal');
    await functions.postSale.run(saleRequest(store.id));
    await store.collection('journal_entries').doc('sale-original-journal')
      .collection('lines').doc('sale-original-sales').update({
        creditMinorUnits: 899,
      });

    await assert.rejects(
      functions.postSaleReturn.run(returnRequest(store.id)),
      (error) => error.code === 'failed-precondition',
    );
    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 2000);
    assert.equal(product.inventoryValueMinorUnits, 800);
    assert.equal((await store.collection('sales_returns').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('reverses credit receivable and output tax with the customer ledger', async () => {
    const store = await seed('sale-return-credit-tax');
    await functions.postSale.run(saleRequest(store.id, {
      credit: true,
      tax: 153,
    }));
    const before = (await store.collection('party_balances')
      .doc('customer-customer-1').get()).data();
    assert.equal(before.balanceMinorUnits, 1053);

    const result = await functions.postSaleReturn.run(returnRequest(store.id, {
      credit: true,
      tax: 153,
    }));
    assert.equal(result.status, 'returned');

    const customer = (await store.collection('party_balances')
      .doc('customer-customer-1').get()).data();
    assert.equal(customer.balanceMinorUnits, 0);
    assert.equal(customer.debitMinorUnits, 1053);
    assert.equal(customer.creditMinorUnits, 1053);

    const tax = (await store.collection('account_balances').doc('2120').get()).data();
    assert.equal(tax.balanceMinorUnits, 0);
    const receivable = (await store.collection('account_balances').doc('1140').get()).data();
    assert.equal(receivable.balanceMinorUnits, 0);
    await db.recursiveDelete(store);
  });
});

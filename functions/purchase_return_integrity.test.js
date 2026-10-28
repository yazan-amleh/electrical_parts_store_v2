'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const USER = 'purchase-return-accountant';
const PURCHASE_DATE = '2026-10-27T10:00:00.000Z';
const RETURN_DATE = '2026-10-28T10:00:00.000Z';

function purchaseRequest(storeId, {
  id = 'purchase-original',
  key = 'purchase-original-key',
  postedAt = PURCHASE_DATE,
  quantity = 1000,
  cost = 700,
  tax = 0,
  credit = false,
} = {}) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      purchase: {
        id,
        idempotencyKey: key,
        postedAt,
        paymentMethod: credit ? 'credit' : 'cash',
        supplierId: credit ? 'supplier-1' : null,
        description: 'Original purchase',
        currency: 'ILS',
        taxMinorUnits: tax,
        lines: [{
          id: 'line-a',
          productId: 'product-a',
          description: 'Electrical component',
          quantityMilliUnits: quantity,
          unitFactorToBaseMilliUnits: 1000,
          unitCostMinorUnits: cost,
          discountMinorUnits: 0,
          unitId: null,
          unitName: null,
        }],
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        inventoryAccountId: '1150',
        supplierPayableAccountId: credit ? '2110' : null,
        inputTaxAccountId: tax > 0 ? '1170' : null,
      },
    },
  };
}

function returnRequest(storeId, {
  id = 'purchase-return-1',
  key = 'purchase-return-key-1',
  originalPurchaseId = 'purchase-original',
  postedAt = RETURN_DATE,
  reason = 'Return to supplier',
  lines = null,
} = {}) {
  return {
    auth: {uid: USER, token: {uid: USER}},
    data: {
      storeId,
      purchaseReturn: {
        id,
        idempotencyKey: key,
        originalPurchaseId,
        postedAt,
        reason,
        lines,
      },
      postingAccounts: {
        settlementAccountId: '1110',
        supplierPayableAccountId: '2110',
        inventoryAccountId: '1150',
        inputTaxAccountId: '1170',
        purchaseReturnVarianceAccountId: '5200',
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
  batch.set(store.collection('parties').doc('supplier-1'), {
    storeId,
    partyType: 'supplier',
    name: 'Supplier',
    isActive: true,
  });
  for (const [id, type, controlType, normalSide] of [
    ['1110', 'asset', 'cashBox', 'debit'],
    ['1150', 'asset', 'inventory', 'debit'],
    ['1170', 'asset', 'inputTax', 'debit'],
    ['2110', 'liability', 'supplierPayable', 'credit'],
    ['5200', 'expense', 'none', 'debit'],
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
    quantityOnHandMilliUnits: 0,
    purchasePriceMinorUnits: 0,
    inventoryValueMinorUnits: 0,
  });
  await batch.commit();
  return store;
}

describe('atomic purchase returns with moving-average valuation', () => {
  after(async () => {await admin.app().delete();});

  it('fully reverses a cash purchase when refund and carrying value match', async () => {
    const store = await seed('purchase-return-full-cash');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 2000,
      cost: 400,
    }));

    const result = await functions.postPurchaseReturn.run(
      returnRequest(store.id),
    );
    assert.equal(result.status, 'returned');
    assert.equal(result.returnStatus, 'full');
    assert.equal(result.inventoryCarryingValueMinorUnits, 800);
    assert.equal(result.valuationVarianceMinorUnits, 0);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);
    assert.equal(product.purchasePriceMinorUnits, 0);

    const original = (await store.collection('purchases')
      .doc('purchase-original').get()).data();
    assert.equal(original.returnStatus, 'full');
    assert.equal(original.returnId, 'purchase-return-1');

    const returned = (await store.collection('purchase_returns')
      .doc('purchase-return-1').get()).data();
    assert.equal(returned.subtotalMinorUnits, 800);
    assert.equal(returned.inventoryCarryingValueMinorUnits, 800);
    assert.equal(returned.valuationVarianceMinorUnits, 0);
    assert.equal(returned.completedOriginalPurchase, true);

    const journal = await store.collection('journal_entries')
      .doc('purchase-return-1-journal').collection('lines').get();
    assert.equal(journal.size, 2);
    await db.recursiveDelete(store);
  });

  it('posts moving-average valuation difference to account 5200', async () => {
    const store = await seed('purchase-return-moving-average');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 1000,
      cost: 700,
    }));
    await functions.postPurchase.run(purchaseRequest(store.id, {
      id: 'purchase-later',
      key: 'purchase-later-key',
      postedAt: '2026-10-27T12:00:00.000Z',
      quantity: 1000,
      cost: 1300,
    }));

    const before = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(before.quantityOnHandMilliUnits, 2000);
    assert.equal(before.inventoryValueMinorUnits, 2000);
    assert.equal(before.purchasePriceMinorUnits, 1000);

    const result = await functions.postPurchaseReturn.run(
      returnRequest(store.id),
    );
    assert.equal(result.inventoryCarryingValueMinorUnits, 1000);
    assert.equal(result.valuationVarianceMinorUnits, -300);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 1000);
    assert.equal(product.purchasePriceMinorUnits, 1000);

    const variance = (await store.collection('journal_entries')
      .doc('purchase-return-1-journal')
      .collection('lines').doc('purchase-return-1-variance').get()).data();
    assert.equal(variance.accountId, '5200');
    assert.equal(variance.debitMinorUnits, 300);
    assert.equal(variance.creditMinorUnits, 0);

    const balance = (await store.collection('account_balances')
      .doc('5200').get()).data();
    assert.equal(balance.debitMinorUnits, 300);
    assert.equal(balance.creditMinorUnits, 0);
    await db.recursiveDelete(store);
  });

  it('allocates partial refund and input tax cumulatively without drift', async () => {
    const store = await seed('purchase-return-partial-tax');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 3000,
      cost: 100,
      tax: 1,
    }));

    const taxParts = [];
    for (let index = 0; index < 3; index++) {
      const result = await functions.postPurchaseReturn.run(
        returnRequest(store.id, {
          id: 'partial-return-' + index,
          key: 'partial-return-key-' + index,
          lines: [{lineId: 'line-a', quantityMilliUnits: 1000}],
        }),
      );
      const row = (await store.collection('purchase_returns')
        .doc(result.returnId).get()).data();
      taxParts.push(row.taxMinorUnits);
      if (index < 2) {
        assert.equal(result.returnStatus, 'partial');
      } else {
        assert.equal(result.returnStatus, 'full');
      }
    }

    assert.deepEqual(taxParts, [0, 1, 0]);
    assert.equal(taxParts.reduce((sum, value) => sum + value, 0), 1);

    const original = (await store.collection('purchases')
      .doc('purchase-original').get()).data();
    assert.equal(original.returnStatus, 'full');
    assert.equal(original.returnedSubtotalMinorUnits, 300);
    assert.equal(original.returnedTaxMinorUnits, 1);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);
    await db.recursiveDelete(store);
  });

  it('serializes competing partial returns and prevents over-return', async () => {
    const store = await seed('purchase-return-race');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 3000,
      cost: 100,
    }));

    const first = returnRequest(store.id, {
      id: 'race-return-a',
      key: 'race-return-key-a',
      lines: [{lineId: 'line-a', quantityMilliUnits: 2000}],
    });
    const second = returnRequest(store.id, {
      id: 'race-return-b',
      key: 'race-return-key-b',
      lines: [{lineId: 'line-a', quantityMilliUnits: 2000}],
    });
    const results = await Promise.allSettled([
      functions.postPurchaseReturn.run(first),
      functions.postPurchaseReturn.run(second),
    ]);

    const fulfilled = results.filter((item) => item.status === 'fulfilled');
    const rejected = results.filter((item) => item.status === 'rejected');
    assert.equal(fulfilled.length, 1);
    assert.equal(rejected.length, 1);
    assert.equal(rejected[0].reason.code, 'failed-precondition');

    const original = (await store.collection('purchases')
      .doc('purchase-original').get()).data();
    assert.equal(original.returnStatus, 'partial');
    assert.equal(original.returnedLines[0].returnedQuantityMilliUnits, 2000);

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 100);
    assert.equal((await store.collection('purchase_returns').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('reduces supplier payable and input tax for a credit purchase return', async () => {
    const store = await seed('purchase-return-credit-tax');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      credit: true,
      quantity: 1000,
      cost: 700,
      tax: 119,
    }));

    let supplier = (await store.collection('party_balances')
      .doc('supplier-supplier-1').get()).data();
    assert.equal(supplier.creditMinorUnits, 819);
    assert.equal(supplier.balanceMinorUnits, -819);

    await functions.postPurchaseReturn.run(returnRequest(store.id));
    supplier = (await store.collection('party_balances')
      .doc('supplier-supplier-1').get()).data();
    assert.equal(supplier.debitMinorUnits, 819);
    assert.equal(supplier.creditMinorUnits, 819);
    assert.equal(supplier.balanceMinorUnits, 0);

    const payable = (await store.collection('account_balances')
      .doc('2110').get()).data();
    const inputTax = (await store.collection('account_balances')
      .doc('1170').get()).data();
    assert.equal(payable.debitMinorUnits, 819);
    assert.equal(payable.creditMinorUnits, 819);
    assert.equal(inputTax.debitMinorUnits, 119);
    assert.equal(inputTax.creditMinorUnits, 119);
    await db.recursiveDelete(store);
  });

  it('rejects a return larger than current physical stock', async () => {
    const store = await seed('purchase-return-stock-shortage');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 3000,
      cost: 100,
    }));
    await store.collection('products').doc('product-a').update({
      quantityOnHandMilliUnits: 1000,
      purchasePriceMinorUnits: 100,
      inventoryValueMinorUnits: 100,
    });

    await assert.rejects(
      functions.postPurchaseReturn.run(returnRequest(store.id, {
        lines: [{lineId: 'line-a', quantityMilliUnits: 2000}],
      })),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('purchase_returns').get()).empty, true);
    assert.equal((await store.collection('inventory_movements')
      .where('sourceType', '==', 'purchaseReturn').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects a return dated before the purchase and a corrupt source journal', async () => {
    const store = await seed('purchase-return-source-integrity');
    await functions.postPurchase.run(purchaseRequest(store.id));

    await assert.rejects(
      functions.postPurchaseReturn.run(returnRequest(store.id, {
        postedAt: '2026-10-26T10:00:00.000Z',
      })),
      (error) => error.code === 'failed-precondition',
    );

    await store.collection('journal_entries').doc('purchase-original-journal')
      .collection('lines').doc('purchase-original-inventory').update({
        debitMinorUnits: 699,
      });
    await assert.rejects(
      functions.postPurchaseReturn.run(returnRequest(store.id)),
      (error) => error.code === 'failed-precondition',
    );

    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 1000);
    assert.equal(product.inventoryValueMinorUnits, 700);
    assert.equal((await store.collection('purchase_returns').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('is idempotent under concurrent retries of the same command', async () => {
    const store = await seed('purchase-return-idempotent');
    await functions.postPurchase.run(purchaseRequest(store.id, {
      quantity: 2000,
      cost: 400,
    }));
    const request = returnRequest(store.id);
    const results = await Promise.all([
      functions.postPurchaseReturn.run(request),
      functions.postPurchaseReturn.run(request),
    ]);

    assert.deepEqual(
      new Set(results.map((item) => item.status)),
      new Set(['returned', 'already_returned']),
    );
    assert.equal((await store.collection('purchase_returns').get()).size, 1);
    assert.equal((await store.collection('inventory_movements')
      .where('sourceType', '==', 'purchaseReturn').get()).size, 1);
    const product = (await store.collection('products')
      .doc('product-a').get()).data();
    assert.equal(product.quantityOnHandMilliUnits, 0);
    assert.equal(product.inventoryValueMinorUnits, 0);
    await db.recursiveDelete(store);
  });
});

'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'expense-accountant-1';
const POSTED_AT = '2026-10-01T14:00:00.000Z';

function command(storeId, id, key, amount, opts = {}) {
  const credit = opts.credit === true;
  const taxed = opts.tax ?? 0;
  return {
    auth: { uid: UID, token: { uid: UID } },
    data: {
      storeId,
      expense: {
        id, idempotencyKey: key, postedAt: POSTED_AT,
        paymentMethod: credit ? 'credit' : 'cash',
        expenseAccountId: '6110', supplierId: credit ? 'supplier-1' : null,
        description: 'Office expense', currency: 'ILS',
        amountMinorUnits: amount, taxMinorUnits: taxed,
      },
      postingAccounts: {
        settlementAccountId: credit ? null : '1110',
        supplierPayableAccountId: credit ? '2110' : null,
        inputTaxAccountId: taxed ? '1170' : null,
      },
    },
  };
}

async function seed(storeId) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  batch.set(ref, { ownerId: UID, currency: 'ILS' });
  batch.set(ref.collection('members').doc(UID),
    { userId: UID, storeId, role: 'accountant', isActive: true });
  const accounts = [
    ['6110', 'expense', 'none'],
    ['1110', 'asset', 'cashBox'],
    ['1170', 'asset', 'inputTax'],
    ['2110', 'liability', 'supplierPayable'],
  ];
  for (const [id, type, controlType] of accounts) {
    batch.set(ref.collection('accounts').doc(id), {
      id, code: id, name: id, storeId, type, controlType,
      currency: 'ILS', isActive: true, isHeader: false,
    });
  }
  await batch.commit();
  return ref;
}

const post = (payload) => functions.postExpense.run(payload);

describe('expense accounting integrity', () => {
  after(async () => { await admin.app().delete(); });

  it('concurrent cash expense is posted once, with balanced GL and replay', async () => {
    const store = await seed('expense-cash-concurrent');
    const request = command(store.id, 'expense-1', 'expense-key-1', 4000);
    const results = await Promise.all([post(request), post(request)]);
    assert.deepEqual(new Set(results.map((x) => x.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await store.collection('expenses').get()).size, 1);
    const expense = (await store.collection('expenses').doc('expense-1').get()).data();
    assert.match(expense.requestFingerprint, /^[0-9a-f]{64}$/);
    const cash = (await store.collection('account_balances').doc('1110').get()).data();
    const cost = (await store.collection('account_balances').doc('6110').get()).data();
    assert.equal(cash.balanceMinorUnits, -4000);
    assert.equal(cost.balanceMinorUnits, 4000);
    assert.equal(cash.balanceMinorUnits + cost.balanceMinorUnits, 0);
    await db.recursiveDelete(store);
  });

  it('rejects changing expense amount under previously used idempotency key', async () => {
    const store = await seed('expense-replay-changed');
    await post(command(store.id, 'expense-2', 'expense-key-2', 400));
    await assert.rejects(
      post(command(store.id, 'expense-2', 'expense-key-2', 500)),
      (e) => e.code === 'already-exists',
    );
    assert.equal((await store.collection('expenses').get()).size, 1);
    assert.equal((await store.collection('account_balances').doc('6110').get())
      .data().debitMinorUnits, 400);
    await db.recursiveDelete(store);
  });

  it('verifies legacy expense and full journal lines when fingerprint is missing', async () => {
    const store = await seed('expense-legacy-replay');
    const request = command(store.id, 'expense-3', 'expense-key-3', 400);
    await post(request);
    await store.collection('expense_idempotency').doc('expense-key-3').update({
      requestFingerprint: admin.firestore.FieldValue.delete(),
    });
    assert.equal((await post(request)).status, 'already_posted');
    await assert.rejects(
      post(command(store.id, 'expense-3', 'expense-key-3', 401)),
      (e) => e.code === 'already-exists',
    );
    await db.recursiveDelete(store);
  });

  it('credit expense with input tax updates three GL accounts and supplier ledger', async () => {
    const store = await seed('expense-credit-tax');
    const request = command(store.id, 'expense-4', 'expense-key-4', 1000, {
      credit: true, tax: 170,
    });
    const result = await post(request);
    assert.equal(result.status, 'posted');
    const gl = await store.collection('account_balances').get();
    assert.equal(gl.size, 3);
    const balances = Object.fromEntries(gl.docs.map((d) => [d.id, d.data().balanceMinorUnits]));
    assert.equal(balances['6110'], 1000);
    assert.equal(balances['1170'], 170);
    assert.equal(balances['2110'], -1170);
    assert.equal(Object.values(balances).reduce((a, b) => a + b, 0), 0);
    const supplier = (await store.collection('party_balances').doc('supplier-supplier-1').get()).data();
    assert.equal(supplier.creditMinorUnits, 1170);
    assert.equal(supplier.balanceMinorUnits, -1170);
    assert.equal((await store.collection('party_ledger_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('rejects invalid stored supplier projection before financial mutation', async () => {
    const store = await seed('expense-corrupt-supplier');
    await store.collection('party_balances').doc('supplier-supplier-1').set({
      storeId: store.id, partyType: 'supplier', partyId: 'supplier-1',
      currency: 'ILS', debitMinorUnits: 100, creditMinorUnits: 200,
      balanceMinorUnits: 0,
    });
    await assert.rejects(
      post(command(store.id, 'expense-5', 'expense-key-5', 100, { credit: true })),
      (e) => e.code === 'failed-precondition',
    );
    assert.equal((await store.collection('expenses').get()).empty, true);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects a tax-inclusive total that exceeds the safe integer limit', async () => {
    const store = await seed('expense-unsafe-total');
    await assert.rejects(
      post(command(store.id, 'expense-6', 'expense-key-6',
        Number.MAX_SAFE_INTEGER, { tax: 1 })),
      (e) => e.code === 'invalid-argument',
    );
    assert.equal((await store.collection('expenses').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects a stored GL balance overflow without touching original value', async () => {
    const store = await seed('expense-running-overflow');
    const prev = Number.MAX_SAFE_INTEGER - 1;
    await store.collection('account_balances').doc('6110').set({
      storeId: store.id, accountId: '6110', currency: 'ILS',
      debitMinorUnits: prev, creditMinorUnits: 0, balanceMinorUnits: prev,
    });
    await assert.rejects(
      post(command(store.id, 'expense-7', 'expense-key-7', 5)),
      (e) => e.code === 'invalid-argument',
    );
    assert.equal((await store.collection('account_balances').doc('6110').get())
      .data().debitMinorUnits, prev);
    assert.equal((await store.collection('expenses').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

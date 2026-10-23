'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'party-accountant-1';
const DATE = '2026-10-02T10:00:00.000Z';

function payload(storeId, id, key, amount, options = {}) {
  const supplier = options.supplier === true;
  const cheque = options.cheque === true;
  return {
    auth: { uid: UID, token: { uid: UID } },
    data: {
      storeId,
      payment: {
        id,
        idempotencyKey: key,
        postedAt: DATE,
        partyType: supplier ? 'supplier' : 'customer',
        partyId: supplier ? 'supplier-1' : 'customer-1',
        paymentMethod: cheque ? 'cheque' : 'cash',
        amountMinorUnits: amount,
        currency: 'ILS',
        description: 'Test settlement',
        chequeNumber: cheque ? 'CHK-100' : null,
        bankName: cheque ? 'Test Bank' : null,
        dueDate: cheque ? '2026-10-10T00:00:00.000Z' : null,
      },
      postingAccounts: {
        settlementAccountId: cheque
          ? supplier ? '2210' : '1130'
          : '1110',
        partyAccountId: supplier ? '2110' : '1140',
      },
    },
  };
}

async function seed(storeId) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  batch.set(ref, { name: 'V2 Test', currency: 'ILS' });
  batch.set(ref.collection('members').doc(UID),
    { storeId, userId: UID, role: 'accountant', isActive: true });
  for (const [id, type, controlType] of [
    ['1110', 'asset', 'cashBox'],
    ['1130', 'asset', 'checks'],
    ['2210', 'liability', 'checksPayable'],
    ['1140', 'asset', 'customerReceivable'],
    ['2110', 'liability', 'supplierPayable'],
  ]) {
    batch.set(ref.collection('accounts').doc(id), {
      id, code: id, name: id, storeId, type, controlType,
      currency: 'ILS', isHeader: false, isActive: true,
    });
  }
  for (const type of ['customer', 'supplier']) {
    batch.set(ref.collection('parties').doc(type + '-1'), {
      storeId, partyType: type, isActive: true, name: 'Test ' + type,
    });
  }
  await batch.commit();
  return ref;
}

const post = (input) => functions.postPartyPayment.run(input);
const get = async (store, group, id) =>
  (await store.collection(group).doc(id).get()).data();

describe('customer and supplier party payment accounting', () => {
  after(async () => { await admin.app().delete(); });

  it('posts a customer cash receipt once under concurrent retries', async () => {
    const store = await seed('party-customer-concurrent');
    const req = payload(store.id, 'pay-1', 'pay-key-1', 1250);
    const results = await Promise.all([post(req), post(req)]);
    assert.deepEqual(new Set(results.map((x) => x.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await store.collection('party_payments').get()).size, 1);
    assert.equal((await get(store, 'account_balances', '1110')).balanceMinorUnits, 1250);
    assert.equal((await get(store, 'account_balances', '1140')).balanceMinorUnits, -1250);
    assert.equal((await get(store, 'party_balances', 'customer-customer-1')).balanceMinorUnits, -1250);
    const lines = await store.collection('journal_entries').doc('pay-1-journal')
      .collection('lines').get();
    assert.equal(lines.size, 2);
    assert.equal(lines.docs.every((x) => x.data().currency === 'ILS'), true);
    await db.recursiveDelete(store);
  });

  it('supplier cash payment debits payable and credits cash', async () => {
    const store = await seed('party-supplier-cash');
    const response = await post(payload(store.id, 'pay-2', 'pay-key-2', 720, {
      supplier: true,
    }));
    assert.equal(response.status, 'posted');
    assert.equal((await get(store, 'account_balances', '2110')).balanceMinorUnits, 720);
    assert.equal((await get(store, 'account_balances', '1110')).balanceMinorUnits, -720);
    assert.equal((await get(store, 'party_balances', 'supplier-supplier-1')).balanceMinorUnits, 720);
    assert.equal((await store.collection('party_ledger_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('rejects altered amount under same idempotency marker without changing balances', async () => {
    const store = await seed('party-changed-request');
    await post(payload(store.id, 'pay-3', 'pay-key-3', 150));
    await assert.rejects(
      post(payload(store.id, 'pay-3', 'pay-key-3', 151)),
      (error) => error.code === 'already-exists',
    );
    assert.equal((await get(store, 'party_balances', 'customer-customer-1')).creditMinorUnits, 150);
    assert.equal((await store.collection('party_payments').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('validates pre-fingerprint legacy marker against stored journal lines', async () => {
    const store = await seed('party-legacy-marker');
    const req = payload(store.id, 'pay-4', 'pay-key-4', 700);
    await post(req);
    await store.collection('party_payment_idempotency').doc('pay-key-4').update({
      requestFingerprint: admin.firestore.FieldValue.delete(),
    });
    assert.equal((await post(req)).status, 'already_posted');
    await assert.rejects(
      post(payload(store.id, 'pay-4', 'pay-key-4', 701)),
      (error) => error.code === 'already-exists',
    );
    await db.recursiveDelete(store);
  });

  it('cheque receipt stays pending while balanced journal and party ledger post', async () => {
    const store = await seed('party-cheque-pending');
    const req = payload(store.id, 'pay-5', 'pay-key-5', 300, { cheque: true });
    await post(req);
    assert.equal((await get(store, 'party_payments', 'pay-5')).status, 'pending');
    assert.equal((await get(store, 'account_balances', '1130')).balanceMinorUnits, 300);
    assert.equal((await get(store, 'account_balances', '1140')).balanceMinorUnits, -300);
    assert.equal((await get(store, 'party_balances', 'customer-customer-1')).balanceMinorUnits, -300);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt party projection and preserves all ledger documents', async () => {
    const store = await seed('party-corrupt-projection');
    await store.collection('party_balances').doc('customer-customer-1').set({
      storeId: store.id, partyId: 'customer-1', partyType: 'customer',
      currency: 'ILS', debitMinorUnits: 250, creditMinorUnits: 100,
      balanceMinorUnits: 100,
    });
    await assert.rejects(
      post(payload(store.id, 'pay-6', 'pay-key-6', 50)),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('party_payments').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects GL projection mismatch and never writes partial settlement', async () => {
    const store = await seed('party-corrupt-gl');
    await store.collection('account_balances').doc('1110').set({
      storeId: store.id, accountId: '1110', currency: 'ILS',
      debitMinorUnits: '500', creditMinorUnits: 0, balanceMinorUnits: 0,
    });
    await assert.rejects(
      post(payload(store.id, 'pay-7', 'pay-key-7', 50)),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('party_payments').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('refuses unsafe party balance accumulation without posting', async () => {
    const store = await seed('party-overflow');
    const old = Number.MAX_SAFE_INTEGER - 2;
    await store.collection('party_balances').doc('customer-customer-1').set({
      storeId: store.id, partyId: 'customer-1', partyType: 'customer',
      currency: 'ILS', debitMinorUnits: 0, creditMinorUnits: old,
      balanceMinorUnits: -old,
    });
    await assert.rejects(
      post(payload(store.id, 'pay-8', 'pay-key-8', 10)),
      (error) => error.code === 'invalid-argument',
    );
    assert.equal((await store.collection('party_payments').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects foreign party and inactive membership before writing', async () => {
    const store = await seed('party-forbidden');
    await store.collection('parties').doc('customer-1').update({
      storeId: 'other-store',
    });
    await assert.rejects(
      post(payload(store.id, 'pay-9', 'pay-key-9', 100)),
      (error) => error.code === 'permission-denied',
    );
    await store.collection('parties').doc('customer-1').update({
      storeId: store.id,
    });
    await store.collection('members').doc(UID).update({ isActive: false });
    await assert.rejects(
      post(payload(store.id, 'pay-10', 'pay-key-10', 100)),
      (error) => error.code === 'permission-denied',
    );
    assert.equal((await store.collection('party_payments').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

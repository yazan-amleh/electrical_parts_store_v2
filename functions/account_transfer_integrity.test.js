'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'transfer-accountant-1';
const DATE = '2026-10-01T13:00:00.000Z';

function payload(storeId, id, key, amount, fromAccountId = '1110') {
  return {
    auth: { uid: UID, token: { uid: UID } },
    data: {
      storeId,
      transfer: {
        id,
        idempotencyKey: key,
        postedAt: DATE,
        fromAccountId,
        toAccountId: '1121',
        amountMinorUnits: amount,
        currency: 'ILS',
        description: 'Internal cash-to-bank transfer',
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
    { userId: UID, storeId, isActive: true, role: 'accountant' });
  for (const [id, controlType] of [['1110', 'cashBox'], ['1121', 'bank']]) {
    batch.set(ref.collection('accounts').doc(id), {
      id, code: id, name: id, storeId,
      type: 'asset', controlType, currency: 'ILS',
      isActive: true, isHeader: false,
    });
  }
  await batch.commit();
  return ref;
}

const invoke = (req) => functions.postAccountTransfer.run(req);

describe('account transfer: journal and balance integrity', () => {
  after(async () => { await admin.app().delete(); });

  it('posts once under simultaneous retries with a balanced journal', async () => {
    const storeId = 'acct-transfer-simultaneous';
    const ref = await seed(storeId);
    const req = payload(storeId, 'transfer-1', 'transfer-key-1', 12500);
    const results = await Promise.all([invoke(req), invoke(req)]);
    assert.deepEqual(new Set(results.map((r) => r.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await ref.collection('account_transfers').get()).size, 1);
    const journal = (await ref.collection('journal_entries')
      .doc('transfer-1-journal').get()).data();
    assert.equal(journal.totalDebitMinorUnits, 12500);
    assert.equal(journal.totalCreditMinorUnits, 12500);
    const lines = await ref.collection('journal_entries')
      .doc('transfer-1-journal').collection('lines').get();
    assert.equal(lines.size, 2);
    const cash = (await ref.collection('account_balances').doc('1110').get()).data();
    const bank = (await ref.collection('account_balances').doc('1121').get()).data();
    assert.equal(cash.balanceMinorUnits, -12500);
    assert.equal(bank.balanceMinorUnits, 12500);
    assert.equal(cash.balanceMinorUnits + bank.balanceMinorUnits, 0);
    await db.recursiveDelete(ref);
  });

  it('rejects reused idempotency key and transfer ID with altered amount', async () => {
    const storeId = 'acct-transfer-altered-retry';
    const ref = await seed(storeId);
    await invoke(payload(storeId, 'transfer-2', 'transfer-key-2', 250));
    await assert.rejects(
      invoke(payload(storeId, 'transfer-2', 'transfer-key-2', 350)),
      (err) => err.code === 'already-exists',
    );
    assert.equal((await ref.collection('account_transfers').get()).size, 1);
    assert.equal((await ref.collection('account_balances').doc('1121').get())
      .data().debitMinorUnits, 250);
    await db.recursiveDelete(ref);
  });

  it('verifies legacy transfer marker without a fingerprint', async () => {
    const storeId = 'acct-transfer-legacy-retry';
    const ref = await seed(storeId);
    const req = payload(storeId, 'transfer-3', 'transfer-key-3', 2500);
    await invoke(req);
    await ref.collection('account_transfer_idempotency').doc('transfer-key-3')
      .update({ requestFingerprint: admin.firestore.FieldValue.delete() });
    assert.equal((await invoke(req)).status, 'already_posted');
    await assert.rejects(
      invoke(payload(storeId, 'transfer-3', 'transfer-key-3', 2600)),
      (err) => err.code === 'already-exists',
    );
    await db.recursiveDelete(ref);
  });

  it('refuses corrupt previous account balance and never overwrites it', async () => {
    const storeId = 'acct-transfer-corrupt-balance';
    const ref = await seed(storeId);
    await ref.collection('account_balances').doc('1110').set({
      storeId, accountId: '1110', currency: 'ILS',
      debitMinorUnits: 3000, creditMinorUnits: 1000, balanceMinorUnits: 3000,
    });
    await assert.rejects(
      invoke(payload(storeId, 'transfer-4', 'transfer-key-4', 500)),
      (err) => err.code === 'failed-precondition',
    );
    assert.equal((await ref.collection('account_transfers').get()).empty, true);
    assert.equal((await ref.collection('account_balances').doc('1110').get())
      .data().balanceMinorUnits, 3000);
    await db.recursiveDelete(ref);
  });

  it('refuses cumulative overflow even though transfer amount is valid', async () => {
    const storeId = 'acct-transfer-overflow';
    const ref = await seed(storeId);
    const old = Number.MAX_SAFE_INTEGER - 1;
    await ref.collection('account_balances').doc('1121').set({
      storeId, accountId: '1121', currency: 'ILS',
      debitMinorUnits: old, creditMinorUnits: 0, balanceMinorUnits: old,
    });
    await assert.rejects(
      invoke(payload(storeId, 'transfer-5', 'transfer-key-5', 5)),
      (err) => err.code === 'invalid-argument',
    );
    assert.equal((await ref.collection('journal_entries').get()).empty, true);
    assert.equal((await ref.collection('account_transfers').get()).empty, true);
    await db.recursiveDelete(ref);
  });
});

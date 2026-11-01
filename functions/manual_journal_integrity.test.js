'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'journal-accountant-1';
const POSTED_AT = '2026-10-01T09:00:00.000Z';

function request(storeId, entryId, idempotencyKey, amount, options = {}) {
  return {
    data: {
      storeId,
      entry: {
        id: entryId,
        idempotencyKey,
        postedAt: POSTED_AT,
        sourceType: 'manual',
        description: options.description ?? 'Opening test (no opening seed)',
        currency: 'ILS',
        lines: options.lines ?? [
          { id: 'line-debit', accountId: '1110', debitMinorUnits: amount, creditMinorUnits: 0 },
          { id: 'line-credit', accountId: '3110', debitMinorUnits: 0, creditMinorUnits: amount },
        ],
      },
    },
    auth: { uid: UID, token: { uid: UID } },
  };
}

async function seed(storeId) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  batch.set(ref, { name: 'Accounting test shop', currency: 'ILS', ownerId: UID });
  batch.set(ref.collection('members').doc(UID),
    { userId: UID, storeId, role: 'accountant', isActive: true });
  for (const [id, type] of [['1110', 'asset'], ['3110', 'equity']]) {
    batch.set(ref.collection('accounts').doc(id), {
      id, code: id, storeId, name: id, currency: 'ILS', type,
      isActive: true, isHeader: false,
    });
  }
  await batch.commit();
  return ref;
}

async function invoke(req) { return functions.postJournalEntry.run(req); }

describe('manual journal posting: accounting integrity', () => {
  after(async () => { await admin.app().delete(); });

  it('posts once under concurrent retries and creates balanced ledger rows', async () => {
    const storeId = 'manual-post-retry-test';
    const store = await seed(storeId);
    const payload = request(storeId, 'journal-1', 'manual-key-1', 12500);
    const responses = await Promise.all([invoke(payload), invoke(payload)]);
    assert.deepEqual(new Set(responses.map((x) => x.status)),
      new Set(['posted', 'already_posted']));
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    assert.equal((await store.collection('journal_entries').doc('journal-1')
      .collection('lines').get()).size, 2);
    const debit = (await store.collection('account_balances').doc('1110').get()).data();
    const credit = (await store.collection('account_balances').doc('3110').get()).data();
    assert.equal(debit.debitMinorUnits, 12500);
    assert.equal(debit.creditMinorUnits, 0);
    assert.equal(debit.balanceMinorUnits, 12500);
    assert.equal(credit.debitMinorUnits, 0);
    assert.equal(credit.creditMinorUnits, 12500);
    assert.equal(credit.balanceMinorUnits, -12500);
    assert.equal(debit.balanceMinorUnits + credit.balanceMinorUnits, 0);
    const shards = await store.collection('accounting_posting_epochs').get();
    assert.equal(shards.size, 1);
    assert.equal(shards.docs[0].data().version, 1);
    assert.equal(shards.docs[0].data().sequence, 1);
    // Replays must not advance the posting fence or duplicate any amounts.
    await invoke(payload);
    const sameShard = await shards.docs[0].ref.get();
    assert.equal(sameShard.data().sequence, 1);
    await db.recursiveDelete(store);
  });

  it('rejects reusing a key and entry ID with altered journal data', async () => {
    const storeId = 'manual-replay-mismatch-test';
    const store = await seed(storeId);
    await invoke(request(storeId, 'journal-2', 'manual-key-2', 400));
    await assert.rejects(
      invoke(request(storeId, 'journal-2', 'manual-key-2', 401)),
      (error) => error.code === 'already-exists',
    );
    const balance = (await store.collection('account_balances').doc('1110').get()).data();
    assert.equal(balance.debitMinorUnits, 400);
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('validates old V2 journal lines when fingerprint did not exist', async () => {
    const storeId = 'manual-legacy-retry-test';
    const store = await seed(storeId);
    const req = request(storeId, 'journal-legacy', 'legacy-key', 700);
    await invoke(req);
    await store.collection('idempotency_keys').doc('legacy-key')
      .update({ requestFingerprint: admin.firestore.FieldValue.delete() });
    const same = await invoke(req);
    assert.equal(same.status, 'already_posted');
    const changed = request(storeId, 'journal-legacy', 'legacy-key', 700,
      { description: 'Changed meaning' });
    await assert.rejects(invoke(changed), (error) => error.code === 'already-exists');
    await db.recursiveDelete(store);
  });

  it('rejects unsafe aggregate debit sums before any database write', async () => {
    const storeId = 'manual-unsafe-total-test';
    const store = await seed(storeId);
    const lines = [
      { id: 'debit-a', accountId: '1110', debitMinorUnits: Number.MAX_SAFE_INTEGER, creditMinorUnits: 0 },
      { id: 'debit-b', accountId: '1110', debitMinorUnits: 1, creditMinorUnits: 0 },
      { id: 'credit-a', accountId: '3110', debitMinorUnits: 0, creditMinorUnits: Number.MAX_SAFE_INTEGER },
    ];
    await assert.rejects(
      invoke(request(storeId, 'journal-unsafe', 'key-unsafe', 1, { lines })),
      (error) => error.code === 'invalid-argument',
    );
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('account_balances').get()).empty, true);
    assert.equal((await store.collection('accounting_posting_epochs').get())
      .empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects safe input that would overflow accumulated account balance', async () => {
    const storeId = 'manual-overflow-balance-test';
    const store = await seed(storeId);
    const old = Number.MAX_SAFE_INTEGER - 2;
    await store.collection('account_balances').doc('1110').set({
      storeId, accountId: '1110', currency: 'ILS',
      debitMinorUnits: old, creditMinorUnits: 0, balanceMinorUnits: old,
    });
    await assert.rejects(
      invoke(request(storeId, 'journal-overflow', 'key-overflow', 5)),
      (error) => error.code === 'invalid-argument',
    );
    assert.equal((await store.collection('account_balances').doc('1110').get())
      .data().debitMinorUnits, old);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('rejects corrupt balance projection instead of treating invalid money as zero', async () => {
    const storeId = 'manual-corrupt-balance-test';
    const store = await seed(storeId);
    await store.collection('account_balances').doc('1110').set({
      storeId, accountId: '1110', currency: 'ILS',
      debitMinorUnits: 'invalid', creditMinorUnits: 0, balanceMinorUnits: 0,
    });
    await assert.rejects(
      invoke(request(storeId, 'journal-corrupt', 'key-corrupt', 100)),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('account_balances').doc('1110').get())
      .data().debitMinorUnits, 'invalid');
    await db.recursiveDelete(store);
  });
});

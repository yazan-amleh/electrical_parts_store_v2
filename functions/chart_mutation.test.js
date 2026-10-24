'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const OWNER = 'chart-owner';
const ACCOUNTANT = 'chart-accountant';
const request = (storeId, operation, account, uid = OWNER) => ({
  auth: uid ? {uid, token: {uid}} : null,
  data: {storeId, operation, account},
});
async function seed(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId: id, currency: 'ILS', ownerId: OWNER});
  for (const [uid, role] of [[OWNER, 'owner'], [ACCOUNTANT, 'accountant']]) {
    batch.set(store.collection('members').doc(uid), {
      storeId: id, userId: uid, role, isActive: true,
    });
  }
  batch.set(store.collection('accounts').doc('1000'), {
    storeId: id, id: '1000', code: '1000', name: 'Assets',
    type: 'asset', currency: 'ILS', normalSide: 'debit',
    isHeader: true, isActive: true, parentId: null,
    sortOrder: 1, statementSection: 'balanceSheet', controlType: 'none',
  });
  batch.set(store.collection('accounts').doc('1100'), {
    storeId: id, id: '1100', code: '1100', name: 'Cash',
    type: 'asset', currency: 'ILS', normalSide: 'debit',
    isHeader: false, isActive: true, parentId: '1000',
    sortOrder: 2, statementSection: 'balanceSheet', controlType: 'none',
  });
  await batch.commit();
  return store;
}
function newAccount(id = '1151', parentId = '1000') {
  return {
    id, code: id, name: 'New account', type: 'asset',
    currency: 'ILS', normalSide: 'debit', isHeader: false,
    isActive: true, parentId, sortOrder: 5,
    statementSection: 'balanceSheet', controlType: 'none',
  };
}
async function mutate(storeId, operation, account, uid = OWNER) {
  return functions.mutateChartAccount.run(
    request(storeId, operation, account, uid));
}
async function epoch(store) {
  const ss = await store.collection('accounting_posting_epochs').get();
  return ss.docs.reduce((count, doc) => count + doc.data().sequence, 0);
}
describe('server-only versioned chart mutations', () => {
  after(async () => {await admin.app().delete();});

  it('creates a child without financial writes and increments epoch once', async () => {
    const store = await seed('chart-create-versioned');
    const created = await mutate(store.id, 'create', newAccount());
    assert.equal(created.status, 'created');
    assert.equal(created.accountId, '1151');
    assert.equal((await store.collection('accounts').doc('1151').get())
      .data().parentId, '1000');
    assert.equal(await epoch(store), 1);
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('account_balances').get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('records changed metadata and rejects a no-op retry without double increment', async () => {
    const store = await seed('chart-update-versioned');
    const first = await mutate(store.id, 'update', {
      id: '1100', name: 'Cash in hand',
    });
    assert.equal(first.status, 'updated');
    const again = await mutate(store.id, 'update', {
      id: '1100', name: 'Cash in hand',
    });
    assert.equal(again.status, 'unchanged');
    assert.equal(await epoch(store), 1);
    assert.equal((await store.collection('accounts').doc('1100')
      .get()).data().name, 'Cash in hand');
    await db.recursiveDelete(store);
  });

  it('rejects chart structural tampering, financial field changes and duplicate controls', async () => {
    const store = await seed('chart-reject-unsafe-fields');
    for (const account of [
      {id: '1100', currency: 'USD'},
      {id: '1100', type: 'revenue'},
      {id: '1100', isHeader: true},
      {id: '1100', debitMinorUnits: 100},
    ]) {
      await assert.rejects(mutate(store.id, 'update', account),
        (e) => e.code === 'invalid-argument');
    }
    await assert.rejects(
      mutate(store.id, 'create', {...newAccount('1152'),
        controlType: 'cashBox'}),
      (e) => e.code === 'invalid-argument');
    assert.equal(await epoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('rejects missing, wrong-tenant, invalid parent and invalid role', async () => {
    const store = await seed('chart-invalid-member-parent');
    await assert.rejects(mutate(store.id, 'create', newAccount('1152'),
      ACCOUNTANT), (e) => e.code === 'permission-denied');
    await assert.rejects(mutate(store.id, 'create', newAccount('1152'),
      null), (e) => e.code === 'unauthenticated');
    await assert.rejects(mutate(store.id, 'create', newAccount('1152', 'unknown')),
      (e) => e.code === 'failed-precondition');
    await assert.rejects(mutate(store.id, 'create',
      newAccount('1152', '1100')),
    (e) => e.code === 'failed-precondition');
    await assert.rejects(mutate(store.id, 'update', {
      id: 'missing', name: 'no account',
    }), (e) => e.code === 'not-found');
    assert.equal(await epoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('prevents a cycle in existing header account hierarchy', async () => {
    const store = await seed('chart-cycle-check');
    await store.collection('accounts').doc('1500').set({
      storeId: store.id, id: '1500', code: '1500', name: 'Child group',
      type: 'asset', currency: 'ILS', normalSide: 'debit', isHeader: true,
      isActive: true, parentId: '1000', sortOrder: 3,
      statementSection: 'balanceSheet', controlType: 'none',
    });
    await assert.rejects(
      mutate(store.id, 'update', {id: '1000', parentId: '1500'}),
      (e) => e.code === 'failed-precondition');
    assert.equal((await store.collection('accounts').doc('1000')
      .get()).data().parentId, null);
    assert.equal(await epoch(store), 0);
    await db.recursiveDelete(store);
  });

  it('marks an in-progress GL audit stale when a chart is edited', async () => {
    const store = await seed('chart-changed-audit-evidence');
    const run = await functions.startAccountingLedgerReconciliation.run({
      auth: {uid: OWNER, token: {uid: OWNER}},
      data: {storeId: store.id},
    });
    await mutate(store.id, 'update', {id: '1100', isActive: false});
    const scanned = await functions.advanceAccountingLedgerReconciliation.run({
      auth: {uid: OWNER, token: {uid: OWNER}},
      data: {storeId: store.id, runId: run.runId},
    });
    assert.equal(scanned.status, 'source_changed');
    assert.equal(scanned.certified, false);
    assert.equal((await store.collection('accounts').doc('1100')
      .get()).data().isActive, false);
    await db.recursiveDelete(store);
  });
});

'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'history-auditor-owner';
const request = (data, uid = UID) => ({
  auth: uid ? {uid, token: {uid}} : null,
  data,
});

async function seed(storeId, {accountCount = 0} = {}) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  await store.set({storeId, name: 'Audit test store', currency: 'ILS'});
  await store.collection('members').doc(UID).set({
    storeId, userId: UID, role: 'owner', isActive: true,
  });
  // Each individual batch is comfortably below Firestore's write limit.
  let batch = db.batch();
  let pending = 0;
  for (let i = 0; i < accountCount; i++) {
    batch.set(store.collection('accounts').doc(
      'account-' + String(i).padStart(4, '0'),
    ), {storeId, isHeader: false});
    if (++pending === 200) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }
  if (pending) await batch.commit();
  return store;
}

describe('durable historical document inventory (not financial certification)', () => {
  after(async () => {await admin.app().delete();});

  it('persists cursor, resumes all sources and never certifies financial balances', async () => {
    const store = await seed('history-resume-a', {accountCount: 205});
    const start = await functions.startAccountingHistoryScan.run(
      request({storeId: store.id}),
    );
    assert.equal(start.scope, 'document_inventory_only');
    assert.equal(start.certified, false);
    assert.equal(start.consistency, 'non_atomic');
    assert.equal(start.documentsScanned, 0);

    const first = await functions.advanceAccountingHistoryScan.run(
      request({storeId: store.id, runId: start.runId}),
    );
    assert.equal(first.phase, 'accounts');
    assert.equal(first.documentsScanned, 100);
    assert.equal(first.phaseCounts.accounts, 100);
    const checkpoint = await store.collection('accounting_audit_runs')
      .doc(start.runId).get();
    assert.equal(checkpoint.data().cursor, 'account-0099');

    // Each invocation reloads the durable checkpoint from Firestore.
    let next = first;
    for (let index = 0; index < 18 &&
        next.status !== 'enumeration_complete'; index++) {
      next = await functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: start.runId}),
      );
    }
    assert.equal(next.status, 'enumeration_complete');
    assert.equal(next.phase, null);
    assert.equal(next.documentsScanned, 205);
    assert.equal(next.phaseCounts.accounts, 205);
    assert.equal(next.certified, false);
    assert.equal(next.consistency, 'non_atomic');
    const again = await functions.advanceAccountingHistoryScan.run(
      request({storeId: store.id, runId: start.runId}),
    );
    assert.deepEqual(again, next);
    assert.equal((await store.collection('accounts').get()).size, 205);
    await db.recursiveDelete(store);
  });

  it('serializes concurrent advances instead of counting the same page twice', async () => {
    const store = await seed('history-concurrent-a', {accountCount: 205});
    const started = await functions.startAccountingHistoryScan.run(
      request({storeId: store.id}),
    );
    await Promise.all([
      functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: started.runId}),
      ),
      functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: started.runId}),
      ),
    ]);
    const state = (await store.collection('accounting_audit_runs')
      .doc(started.runId).get()).data();
    assert.equal(state.documentsScanned, 200);
    assert.equal(state.phaseCounts.accounts, 200);
    assert.equal(state.cursor, 'account-0199');
    assert.equal(state.pagesScanned, 2);
    await db.recursiveDelete(store);
  });

  it('denies unauthenticated, inactive and unrelated users and revocation', async () => {
    const store = await seed('history-security-a');
    await assert.rejects(
      functions.startAccountingHistoryScan.run(
        request({storeId: store.id}, null),
      ), (error) => error.code === 'unauthenticated',
    );
    await assert.rejects(
      functions.startAccountingHistoryScan.run(
        request({storeId: store.id}, 'other-user'),
      ), (error) => error.code === 'permission-denied',
    );
    const started = await functions.startAccountingHistoryScan.run(
      request({storeId: store.id}),
    );
    await assert.rejects(
      functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: started.runId}, 'other-user'),
      ), (error) => error.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(
      functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: started.runId}),
      ), (error) => error.code === 'permission-denied',
    );
    const checkpoint = (await store.collection('accounting_audit_runs')
      .doc(started.runId).get()).data();
    assert.equal(checkpoint.pagesScanned, 0);
    await db.recursiveDelete(store);
  });

  it('fails closed on malformed checkpoint and never edits the source', async () => {
    const store = await seed('history-corrupt-a', {accountCount: 1});
    const started = await functions.startAccountingHistoryScan.run(
      request({storeId: store.id}),
    );
    await store.collection('accounting_audit_runs').doc(started.runId)
      .update({phaseIndex: 500});
    await assert.rejects(
      functions.advanceAccountingHistoryScan.run(
        request({storeId: store.id, runId: started.runId}),
      ), (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('accounts').get()).size, 1);
    await db.recursiveDelete(store);
  });
});

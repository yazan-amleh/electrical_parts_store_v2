'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'orphan-path-owner';
function req(data, uid = UID) {
  return {data, auth: uid ? {uid, token: {uid}} : null};
}

async function storeFixture(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId: id});
  batch.set(store.collection('members').doc(UID), {
    storeId: id, userId: UID, role: 'owner', isActive: true,
  });
  batch.set(store.collection('journal_entries').doc('posted'), {
    storeId: id, status: 'posted', currency: 'ILS',
  });
  batch.set(store.collection('journal_entries').doc('posted')
    .collection('lines').doc('valid'), {
    storeId: id, entryId: 'posted', accountId: '1110', currency: 'ILS',
    debitMinorUnits: 100, creditMinorUnits: 0,
  });
  await batch.commit();
  return store;
}

const start = (storeId, uid = UID) =>
  functions.startAccountingOrphanPathScan.run(req({storeId}, uid));
const advance = (storeId, runId, uid = UID) =>
  functions.advanceAccountingOrphanPathScan.run(
    req({storeId, runId}, uid),
  );
async function finish(storeId, runId, max = 15) {
  for (let i = 0; i < max; i++) {
    const result = await advance(storeId, runId);
    if (result.status !== 'running') return result;
  }
  throw new Error('Orphan path scan test exceeded bounded test steps');
}

describe('bounded tenant-path journal orphan census', () => {
  after(async () => {await admin.app().delete();});

  it('discovers nested orphan even when embedded storeId is missing', async () => {
    const store = await storeFixture('orphan-path-missing-id');
    const orphan = store.collection('journal_entries').doc('absent')
      .collection('lines').doc('orphan');
    await orphan.set({
      entryId: 'absent', accountId: '1110', currency: 'ILS',
      debitMinorUnits: 17, creditMinorUnits: 0,
      // Crucially, no embedded storeId.
    });
    assert.equal((await orphan.parent.parent.get()).exists, false);
    const run = await start(store.id);
    assert.equal(run.certified, false);
    const result = await finish(store.id, run.runId);
    assert.equal(result.status, 'enumeration_complete');
    assert.equal(result.orphanLines, 1);
    assert.equal(result.orphansWithoutCorrectStoreId, 1);
    assert.equal(result.journalLinesScanned, 2);
    assert.equal(result.orphanSamples[0].linePath, orphan.path);
    assert.equal(result.orphanSamples[0].embeddedStoreIdMatches, false);
    assert.equal(result.accountingCutoffApplied, false);
    assert.deepEqual(await advance(store.id, run.runId), result);
    assert.equal((await orphan.get()).exists, true);
    await db.recursiveDelete(store);
  });

  it('does not confuse invoice lines, foreign stores or valid journal lines', async () => {
    const store = await storeFixture('orphan-path-tenant');
    const sibling = await storeFixture('orphan-path-tenant2');
    await store.collection('sales').doc('invoice')
      .collection('lines').doc('decoy').set({
        storeId: store.id, accountId: '1110', entryId: 'absent',
      });
    await sibling.collection('journal_entries').doc('absent')
      .collection('lines').doc('foreign').set({
        storeId: store.id, accountId: '1110', entryId: 'absent',
      });
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.status, 'enumeration_complete');
    assert.equal(result.orphanLines, 0);
    assert.equal(result.journalLinesScanned, 1);
    assert.equal(result.groupDocumentsScanned, 2);
    assert.deepEqual(result.orphanSamples, []);
    await db.recursiveDelete(store);
    await db.recursiveDelete(sibling);
  });

  it('handles many pages concurrently without recounting orphans', async () => {
    const store = await storeFixture('orphan-path-pages');
    const batch = db.batch();
    for (let i = 0; i < 95; i++) {
      const orphan = store.collection('journal_entries').doc('absent')
        .collection('lines').doc('orphan-' + String(i).padStart(3, '0'));
      batch.set(orphan, {
        entryId: 'absent', accountId: '1110', currency: 'ILS',
        storeId: i % 2 === 0 ? store.id : 'wrong-store',
      });
    }
    await batch.commit();
    const started = await start(store.id);
    await Promise.all([
      advance(store.id, started.runId),
      advance(store.id, started.runId),
    ]);
    const progress = (await store.collection('accounting_orphan_path_runs')
      .doc(started.runId).get()).data();
    assert.equal(progress.groupDocumentsScanned, 80);
    assert.equal(progress.orphanLines, 80);
    const report = await finish(store.id, started.runId);
    assert.equal(report.groupDocumentsScanned, 96);
    assert.equal(report.journalLinesScanned, 96);
    assert.equal(report.orphanLines, 95);
    assert.equal(report.orphansWithoutCorrectStoreId, 47);
    assert.equal(report.orphanSamples.length, 20);
    assert.equal(report.certified, false);
    await db.recursiveDelete(store);
  });

  it('completes an empty collection group scope without touching finance', async () => {
    const store = db.collection('stores').doc('orphan-path-empty');
    await db.recursiveDelete(store);
    await store.set({storeId: store.id});
    await store.collection('members').doc(UID).set({
      storeId: store.id, userId: UID, role: 'owner', isActive: true,
    });
    const run = await start(store.id);
    const status = await finish(store.id, run.runId);
    assert.equal(status.status, 'enumeration_complete');
    assert.equal(status.groupDocumentsScanned, 0);
    assert.equal(status.orphanLines, 0);
    assert.equal(status.certified, false);
    await db.recursiveDelete(store);
  });

  it('denies missing membership, revoked access and forged cursors', async () => {
    const store = await storeFixture('orphan-path-auth');
    await assert.rejects(
      start(store.id, null), (e) => e.code === 'unauthenticated',
    );
    await assert.rejects(
      start(store.id, 'outsider'), (e) => e.code === 'permission-denied',
    );
    const run = await start(store.id);
    await assert.rejects(
      advance(store.id, run.runId, 'outsider'),
      (e) => e.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(
      advance(store.id, run.runId),
      (e) => e.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: true});
    await store.collection('accounting_orphan_path_runs').doc(run.runId)
      .update({cursorPath: 'stores/another-shop/journal_entries/a/lines/b'});
    await assert.rejects(
      advance(store.id, run.runId),
      (e) => e.code === 'failed-precondition',
    );
    await db.recursiveDelete(store);
  });
});

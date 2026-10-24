'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'journal-reconciliation-owner';
const request = (data, uid = UID) => ({
  data,
  auth: uid ? {uid, token: {uid}} : null,
});

async function seed(storeId) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId, name: 'Reconciliation test', currency: 'ILS'});
  batch.set(store.collection('members').doc(UID), {
    storeId, userId: UID, role: 'accountant', isActive: true,
  });
  batch.set(store.collection('journal_entries').doc('journal-1'), {
    storeId, currency: 'ILS', status: 'posted',
    totalDebitMinorUnits: 200, totalCreditMinorUnits: 200,
  });
  batch.set(store.collection('journal_entries').doc('journal-1')
    .collection('lines').doc('debit'), {
    storeId, entryId: 'journal-1', accountId: '1110', currency: 'ILS',
    debitMinorUnits: 200, creditMinorUnits: 0,
  });
  batch.set(store.collection('journal_entries').doc('journal-1')
    .collection('lines').doc('credit'), {
    storeId, entryId: 'journal-1', accountId: '3110', currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 200,
  });
  await batch.commit();
  return store;
}

const start = (storeId) =>
  functions.startAccountingJournalReconciliation.run(
    request({storeId}),
  );
const advance = (storeId, runId) =>
  functions.advanceAccountingJournalReconciliation.run(
    request({storeId, runId}),
  );
async function finish(storeId, runId, max = 15) {
  let result;
  for (let index = 0; index < max; index++) {
    result = await advance(storeId, runId);
    if (result.status !== 'running') return result;
  }
  throw new Error('Journal test fixture did not finish');
}

describe('checkpointed journal header vs direct line totals', () => {
  after(async () => {await admin.app().delete();});

  it('matches one balanced journal and preserves source financial records', async () => {
    const store = await seed('journal-history-balanced');
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.status, 'reconciliation_complete');
    assert.equal(result.entriesChecked, 1);
    assert.equal(result.linesChecked, 2);
    assert.equal(result.failedEntries, 0);
    assert.equal(result.certified, false);
    assert.equal(result.consistency, 'non_atomic');
    assert.equal(result.accountingCutoffApplied, false);
    const evidence = (await store.collection('accounting_journal_runs')
      .doc(run.runId).collection('entry_results').doc('journal-1')
      .get()).data();
    assert.equal(evidence.matched, true);
    assert.equal(evidence.debitMinorUnits, 200);
    assert.equal(evidence.creditMinorUnits, 200);
    assert.equal(evidence.issueCount, 0);
    assert.deepEqual(await advance(store.id, run.runId), result);
    assert.equal((await store.collection('journal_entries')
      .doc('journal-1').get()).data().totalDebitMinorUnits, 200);
    await db.recursiveDelete(store);
  });

  it('reports debit mismatch separately from credit mismatch', async () => {
    const store = await seed('journal-history-one-sided');
    await store.collection('journal_entries').doc('journal-1').update({
      totalCreditMinorUnits: 180,
    });
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.failedEntries, 1);
    const evidence = (await store.collection('accounting_journal_runs')
      .doc(run.runId).collection('entry_results').doc('journal-1')
      .get()).data();
    assert.equal(evidence.matched, false);
    assert.equal(evidence.issueSamples.some(
      (issue) => issue.code === 'JOURNAL_HEADER_CREDIT_MISMATCH'), true);
    assert.equal(evidence.issueSamples.some(
      (issue) => issue.code === 'JOURNAL_HEADER_DEBIT_MISMATCH'), false);
    await db.recursiveDelete(store);
  });

  it('detects missing embedded tenant identity, wrong currency and money', async () => {
    const store = await seed('journal-history-bad-line');
    await store.collection('journal_entries').doc('journal-1')
      .collection('lines').doc('debit').update({
        storeId: admin.firestore.FieldValue.delete(),
        currency: 'USD', debitMinorUnits: '200',
      });
    const run = await start(store.id);
    const report = await finish(store.id, run.runId);
    assert.equal(report.failedEntries, 1);
    const evidence = (await store.collection('accounting_journal_runs')
      .doc(run.runId).collection('entry_results').doc('journal-1')
      .get()).data();
    assert.equal(evidence.debitMinorUnits, 0);
    const codes = evidence.issueSamples.map((issue) => issue.code);
    assert.equal(codes.includes('JOURNAL_LINE_IDENTITY_INVALID'), true);
    assert.equal(codes.includes('JOURNAL_LINE_CURRENCY_MISMATCH'), true);
    assert.equal(codes.includes('JOURNAL_LINE_MONEY_INVALID'), true);
    assert.equal(codes.includes('JOURNAL_HEADER_DEBIT_MISMATCH'), true);
    await db.recursiveDelete(store);
  });

  it('resumes >40 line entries safely under simultaneous advancing', async () => {
    const store = await seed('journal-history-pages');
    const journal = store.collection('journal_entries').doc('journal-1');
    let batch = db.batch();
    batch.delete(journal.collection('lines').doc('debit'));
    batch.delete(journal.collection('lines').doc('credit'));
    for (let i = 0; i < 92; i++) {
      batch.set(journal.collection('lines').doc(
        'line-' + String(i).padStart(3, '0'),
      ), {
        storeId: store.id, entryId: 'journal-1',
        accountId: i % 2 === 0 ? '1110' : '3110',
        currency: 'ILS',
        debitMinorUnits: i % 2 === 0 ? 2 : 0,
        creditMinorUnits: i % 2 === 1 ? 2 : 0,
      });
    }
    batch.update(journal, {
      totalDebitMinorUnits: 92, totalCreditMinorUnits: 92,
    });
    await batch.commit();
    const run = await start(store.id);
    await Promise.all([advance(store.id, run.runId),
      advance(store.id, run.runId)]);
    const checkpoint = (await store.collection('accounting_journal_runs')
      .doc(run.runId).get()).data();
    assert.equal(checkpoint.activeEntryId, 'journal-1');
    assert.equal(checkpoint.linesChecked, 80);
    assert.equal(checkpoint.lineCursor, 'line-079');
    assert.equal(checkpoint.debit, 80);
    assert.equal(checkpoint.credit, 80);

    const completed = await finish(store.id, run.runId);
    assert.equal(completed.status, 'reconciliation_complete');
    assert.equal(completed.entriesChecked, 1);
    assert.equal(completed.linesChecked, 92);
    assert.equal(completed.failedEntries, 0);
    const evidence = (await store.collection('accounting_journal_runs')
      .doc(run.runId).collection('entry_results').doc('journal-1')
      .get()).data();
    assert.equal(evidence.debitMinorUnits, 92);
    assert.equal(evidence.creditMinorUnits, 92);
    assert.equal(evidence.linesChecked, 92);
    await db.recursiveDelete(store);
  });

  it('aborts rather than certifying a header revised between page reads', async () => {
    const store = await seed('journal-history-source-change');
    const journal = store.collection('journal_entries').doc('journal-1');
    const batch = db.batch();
    for (let i = 0; i < 45; i++) {
      batch.set(journal.collection('lines').doc(
        'added-' + String(i).padStart(3, '0'),
      ), {
        storeId: store.id, entryId: 'journal-1',
        currency: 'ILS', accountId: '1110',
        debitMinorUnits: 1, creditMinorUnits: 0,
      });
    }
    await batch.commit();
    const run = await start(store.id);
    const first = await advance(store.id, run.runId);
    assert.equal(first.status, 'running');
    assert.equal(first.linesChecked, 40);
    await journal.update({description: 'changed during audit'});
    const second = await advance(store.id, run.runId);
    assert.equal(second.status, 'source_changed');
    assert.equal(second.certified, false);
    assert.equal(second.entriesChecked, 0);
    assert.equal((await store.collection('accounting_journal_runs')
      .doc(run.runId).collection('entry_results').get()).empty, true);
    assert.deepEqual(await advance(store.id, run.runId), second);
    await db.recursiveDelete(store);
  });

  it('denies revoked/nonmember users and malformed persisted cursors', async () => {
    const store = await seed('journal-history-auth');
    await assert.rejects(
      functions.startAccountingJournalReconciliation.run(
        request({storeId: store.id}, null),
      ), (error) => error.code === 'unauthenticated',
    );
    await assert.rejects(
      functions.startAccountingJournalReconciliation.run(
        request({storeId: store.id}, 'stranger'),
      ), (error) => error.code === 'permission-denied',
    );
    const run = await start(store.id);
    await assert.rejects(
      functions.advanceAccountingJournalReconciliation.run(
        request({storeId: store.id, runId: run.runId}, 'stranger'),
      ), (error) => error.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(
      advance(store.id, run.runId),
      (error) => error.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: true});
    await store.collection('accounting_journal_runs').doc(run.runId)
      .update({activeEntryId: 'journal-1', lineCursor: 'invalid/id'});
    await assert.rejects(
      advance(store.id, run.runId),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await journalExists(store)), true);
    await db.recursiveDelete(store);
  });
});

async function journalExists(store) {
  return (await store.collection('journal_entries').doc('journal-1')
    .get()).exists;
}

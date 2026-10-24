'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'coverage-audit-accountant';
const req = (data, uid = UID) => ({
  auth: uid ? {uid, token: {uid}} : null,
  data,
});

async function seed(storeId) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId, currency: 'ILS'});
  batch.set(store.collection('members').doc(UID), {
    storeId, role: 'accountant', userId: UID, isActive: true,
  });
  for (const id of ['1110', '3110']) {
    batch.set(store.collection('accounts').doc(id), {
      storeId, id, isHeader: false, currency: 'ILS',
    });
  }
  batch.set(store.collection('journal_entries').doc('journal-1'), {
    storeId, status: 'posted', currency: 'ILS',
    totalDebitMinorUnits: 100, totalCreditMinorUnits: 100,
  });
  batch.set(store.collection('journal_entries').doc('journal-1')
    .collection('lines').doc('debit'), {
    storeId, entryId: 'journal-1', accountId: '1110', currency: 'ILS',
    debitMinorUnits: 100, creditMinorUnits: 0,
  });
  batch.set(store.collection('journal_entries').doc('journal-1')
    .collection('lines').doc('credit'), {
    storeId, entryId: 'journal-1', accountId: '3110', currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 100,
  });
  batch.set(store.collection('account_balances').doc('1110'), {
    storeId, accountId: '1110', currency: 'ILS',
    debitMinorUnits: 100, creditMinorUnits: 0, balanceMinorUnits: 100,
  });
  batch.set(store.collection('account_balances').doc('3110'), {
    storeId, accountId: '3110', currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 100, balanceMinorUnits: -100,
  });
  await batch.commit();
  return store;
}

async function runToEnd(startFn, nextFn, storeId) {
  const started = await startFn.run(req({storeId}));
  let current;
  for (let i = 0; i < 16; i++) {
    current = await nextFn.run(req({storeId, runId: started.runId}));
    if (current.status !== 'running') {
      assert.equal(current.status, 'reconciliation_complete');
      return current;
    }
  }
  throw new Error('Audit fixture did not terminate');
}

const scanLedger = (storeId) => runToEnd(
  functions.startAccountingLedgerReconciliation,
  functions.advanceAccountingLedgerReconciliation, storeId,
);
const scanJournal = (storeId) => runToEnd(
  functions.startAccountingJournalReconciliation,
  functions.advanceAccountingJournalReconciliation, storeId,
);
const compare = (storeId, ledgerRunId, journalRunId, uid = UID) =>
  functions.compareAccountingAuditCoverage.run(
    req({storeId, ledgerRunId, journalRunId}, uid),
  );

describe('cross-run audit coverage is evidence-only and role-checked', () => {
  after(async () => {await admin.app().delete();});

  it('compares equal ILS totals and counts but explicitly never certifies', async () => {
    const store = await seed('coverage-matched-a');
    const ledger = await scanLedger(store.id);
    const journal = await scanJournal(store.id);
    const result = await compare(store.id, ledger.runId, journal.runId);
    assert.equal(result.verdict, 'aggregate_coverage_agrees_non_atomic');
    assert.equal(result.certified, false);
    assert.equal(result.consistency, 'non_atomic');
    assert.equal(result.accountingCutoffApplied, false);
    assert.equal(result.currencies.length, 1);
    assert.deepEqual(result.currencies[0], {
      currency: 'ILS',
      indexedJournalLines: 2,
      directJournalLines: 2,
      indexedDebitMinorUnits: 100,
      directDebitMinorUnits: 100,
      indexedCreditMinorUnits: 100,
      directCreditMinorUnits: 100,
      linesAgree: true, debitAgrees: true, creditAgrees: true,
    });
    assert.equal(result.directJournalLines, 2);
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('exposes a journal line omitted by the tenant-keyed index', async () => {
    const store = await seed('coverage-missing-tenant-key');
    await store.collection('journal_entries').doc('journal-1')
      .collection('lines').doc('debit').update({
        storeId: admin.firestore.FieldValue.delete(),
      });
    const ledger = await scanLedger(store.id);
    const journal = await scanJournal(store.id);
    assert.equal(journal.potentiallyUnindexedLines > 0, true);
    const report = await compare(store.id, ledger.runId, journal.runId);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.currencies[0].linesAgree, false);
    assert.equal(report.currencies[0].debitAgrees, false);
    assert.equal(report.currencies[0].indexedJournalLines, 1);
    assert.equal(report.currencies[0].directJournalLines, 2);
    assert.equal(report.certified, false);
    await db.recursiveDelete(store);
  });

  it('detects a journal line for an account missing from the chart', async () => {
    const store = await seed('coverage-unknown-account');
    await store.collection('journal_entries').doc('journal-1')
      .collection('lines').doc('debit').update({accountId: 'nonexistent'});
    const ledger = await scanLedger(store.id);
    const journal = await scanJournal(store.id);
    assert.equal(journal.invalidAccountReferenceLines > 0, true);
    const report = await compare(store.id, ledger.runId, journal.runId);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.currencies[0].linesAgree, false);
    await db.recursiveDelete(store);
  });

  it('sees indexed orphan lines absent from existing journal headers', async () => {
    const store = await seed('coverage-deleted-header');
    await store.collection('journal_entries').doc('missing-parent')
      .collection('lines').doc('orphan').set({
        storeId: store.id, entryId: 'missing-parent', accountId: '1110',
        currency: 'ILS', debitMinorUnits: 11, creditMinorUnits: 0,
      });
    const ledger = await scanLedger(store.id);
    const journal = await scanJournal(store.id);
    const report = await compare(store.id, ledger.runId, journal.runId);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.currencies[0].linesAgree, false);
    assert.equal(report.currencies[0].indexedJournalLines, 3);
    assert.equal(report.currencies[0].directJournalLines, 2);
    await db.recursiveDelete(store);
  });

  it('returns incomplete without claiming no discrepancy when audits are unfinished', async () => {
    const store = await seed('coverage-incomplete');
    const ledger = await functions.startAccountingLedgerReconciliation
      .run(req({storeId: store.id}));
    const journal = await functions.startAccountingJournalReconciliation
      .run(req({storeId: store.id}));
    const report = await compare(store.id, ledger.runId, journal.runId);
    assert.equal(report.verdict, 'incomplete');
    assert.equal(report.certified, false);
    assert.equal(report.currencies.length, 0);
    await db.recursiveDelete(store);
  });

  it('denies other users and revoked memberships even for known IDs', async () => {
    const store = await seed('coverage-auth-denied');
    const ledger = await functions.startAccountingLedgerReconciliation
      .run(req({storeId: store.id}));
    const journal = await functions.startAccountingJournalReconciliation
      .run(req({storeId: store.id}));
    await assert.rejects(
      compare(store.id, ledger.runId, journal.runId, 'other-user'),
      (e) => e.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(
      compare(store.id, ledger.runId, journal.runId),
      (e) => e.code === 'permission-denied',
    );
    await db.recursiveDelete(store);
  });
});

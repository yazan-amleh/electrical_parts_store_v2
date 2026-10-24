'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'unified-audit-owner';
const req = (data, uid = UID) => ({
  data, auth: uid ? {uid, token: {uid}} : null,
});

async function fixture(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId: id, currency: 'ILS'});
  batch.set(store.collection('members').doc(UID), {
    storeId: id, userId: UID, role: 'owner', isActive: true,
  });
  for (const accountId of ['1110', '3110']) {
    batch.set(store.collection('accounts').doc(accountId), {
      storeId: id, id: accountId, currency: 'ILS', isHeader: false,
    });
  }
  batch.set(store.collection('journal_entries').doc('posted'), {
    storeId: id, status: 'posted', currency: 'ILS',
    totalDebitMinorUnits: 77, totalCreditMinorUnits: 77,
  });
  for (const [lineId, accountId, debit, credit] of [
    ['debit', '1110', 77, 0], ['credit', '3110', 0, 77],
  ]) {
    batch.set(store.collection('journal_entries').doc('posted')
      .collection('lines').doc(lineId), {
      storeId: id, entryId: 'posted', accountId, currency: 'ILS',
      debitMinorUnits: debit, creditMinorUnits: credit,
    });
    batch.set(store.collection('account_balances').doc(accountId), {
      storeId: id, accountId, currency: 'ILS',
      debitMinorUnits: debit, creditMinorUnits: credit,
      balanceMinorUnits: debit - credit,
    });
  }
  await batch.commit();
  return store;
}

async function scan(storeId, startFn, advanceFn, doneStatus) {
  const started = await startFn.run(req({storeId}));
  for (let i = 0; i < 12; i++) {
    const next = await advanceFn.run(
      req({storeId, runId: started.runId}),
    );
    if (next.status !== 'running') {
      assert.equal(next.status, doneStatus);
      return next;
    }
  }
  throw new Error('Test fixture scan exceeded permitted steps');
}
async function allRuns(storeId) {
  const ledger = await scan(storeId,
    functions.startAccountingLedgerReconciliation,
    functions.advanceAccountingLedgerReconciliation,
    'reconciliation_complete');
  const journal = await scan(storeId,
    functions.startAccountingJournalReconciliation,
    functions.advanceAccountingJournalReconciliation,
    'reconciliation_complete');
  const orphan = await scan(storeId,
    functions.startAccountingOrphanPathScan,
    functions.advanceAccountingOrphanPathScan,
    'enumeration_complete');
  return {ledgerRunId: ledger.runId, journalRunId: journal.runId,
    orphanRunId: orphan.runId};
}
const getReport = (storeId, runs, uid = UID) =>
  functions.getUnifiedAccountingAuditReport.run(
    req({storeId, ...runs}, uid),
  );

describe('read-only consolidated accounting audit evidence', () => {
  after(async () => {await admin.app().delete();});

  it('combines three complete scans and reports balanced evidence only', async () => {
    const store = await fixture('unified-audit-matched');
    const runs = await allRuns(store.id);
    const result = await getReport(store.id, runs);
    assert.equal(result.verdict, 'observed_aggregates_agree_non_atomic');
    assert.equal(result.complete, true);
    assert.equal(result.certified, false);
    assert.equal(result.consistency, 'non_atomic');
    assert.equal(result.accountingCutoffApplied, false);
    assert.equal(result.sourceSnapshotGuaranteed, false);
    assert.equal(result.checks.ledger.mismatchedAccounts, 0);
    assert.equal(result.checks.journal.failedEntries, 0);
    assert.equal(result.checks.orphanPaths.orphanLines, 0);
    assert.equal(result.checks.directPathCoverage.agrees, true);
    assert.equal(result.checks.directPathCoverage.knownParentPathLines, 2);
    assert.equal(result.checks.crossRun.currencies[0].linesAgree, true);
    assert.equal(result.checks.ledger.trialBalance.currencies[0]
      .closingBalanced, true);
    assert.deepEqual(result.findings, [{
      code: 'NO_IMMUTABLE_ACCOUNTING_CUTOFF', count: null,
    }]);
    assert.deepEqual(await getReport(store.id, runs), result);
    assert.equal((await store.collection('account_balances').doc('1110')
      .get()).data().balanceMinorUnits, 77);
    await db.recursiveDelete(store);
  });

  it('surfaces an orphan lacking embedded storeId even if GL totals balance', async () => {
    const store = await fixture('unified-audit-missing-id');
    const orphanRef = store.collection('journal_entries').doc('deleted')
      .collection('lines').doc('orphan');
    await orphanRef.set({
      entryId: 'deleted', accountId: '1110',
      currency: 'ILS', debitMinorUnits: 19, creditMinorUnits: 0,
    });
    const runs = await allRuns(store.id);
    const report = await getReport(store.id, runs);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.complete, true);
    assert.equal(report.checks.orphanPaths.orphanLines, 1);
    assert.equal(report.checks.orphanPaths
      .orphansWithoutCorrectStoreId, 1);
    assert.equal(report.checks.directPathCoverage.agrees, true);
    assert.equal(report.findings.some(
      (f) => f.code === 'ORPHAN_JOURNAL_LINES' &&
        f.count === 1), true);
    assert.equal(report.certified, false);
    assert.equal((await orphanRef.get()).exists, true);
    await db.recursiveDelete(store);
  });

  it('never calls pending partial audit evidence a clean result', async () => {
    const store = await fixture('unified-audit-pending');
    const ledger = await functions.startAccountingLedgerReconciliation
      .run(req({storeId: store.id}));
    const journal = await functions.startAccountingJournalReconciliation
      .run(req({storeId: store.id}));
    const orphan = await functions.startAccountingOrphanPathScan
      .run(req({storeId: store.id}));
    const runs = {
      ledgerRunId: ledger.runId,
      journalRunId: journal.runId,
      orphanRunId: orphan.runId,
    };
    const result = await getReport(store.id, runs);
    assert.equal(result.verdict, 'incomplete');
    assert.equal(result.complete, false);
    assert.equal(result.checks.directPathCoverage.agrees, null);
    assert.equal(result.findings.some(
      (f) => f.code === 'ORPHAN_SCAN_NOT_COMPLETE'), true);
    await db.recursiveDelete(store);
  });

  it('treats scan budget exhaustion as incomplete, not certified', async () => {
    const store = await fixture('unified-audit-budget');
    const runs = await allRuns(store.id);
    await store.collection('accounting_orphan_path_runs')
      .doc(runs.orphanRunId).update({status: 'budget_exhausted'});
    const result = await getReport(store.id, runs);
    assert.equal(result.verdict, 'incomplete');
    assert.equal(result.complete, false);
    assert.equal(result.checks.directPathCoverage.agrees, null);
    assert.equal(result.findings.some(
      (f) => f.code === 'ORPHAN_SCAN_BUDGET_EXHAUSTED'), true);
    await db.recursiveDelete(store);
  });

  it('denies missing auth, revoked membership and foreign store ownership', async () => {
    const store = await fixture('unified-audit-secure');
    const foreign = await fixture('unified-audit-foreign');
    const runs = await allRuns(store.id);
    const otherRuns = await allRuns(foreign.id);
    await assert.rejects(getReport(store.id, runs, null),
      (e) => e.code === 'unauthenticated');
    await assert.rejects(getReport(store.id, runs, 'outsider'),
      (e) => e.code === 'permission-denied');
    await assert.rejects(
      getReport(store.id, {...runs, orphanRunId: otherRuns.orphanRunId}),
      (e) => e.code === 'not-found',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(getReport(store.id, runs),
      (e) => e.code === 'permission-denied');
    await db.recursiveDelete(store);
    await db.recursiveDelete(foreign);
  });

  it('rejects corrupted checkpoint metadata without modifying the source', async () => {
    const store = await fixture('unified-audit-corrupt');
    const runs = await allRuns(store.id);
    await store.collection('accounting_orphan_path_runs')
      .doc(runs.orphanRunId).update({
        groupDocumentsScanned: -1,
      });
    await assert.rejects(getReport(store.id, runs),
      (e) => e.code === 'failed-precondition');
    assert.equal((await store.collection('account_balances').doc('3110')
      .get()).data().balanceMinorUnits, -77);
    await db.recursiveDelete(store);
  });
});

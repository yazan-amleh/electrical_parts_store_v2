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
  const balance = await scan(storeId,
    functions.startAccountingBalanceProjectionScan,
    functions.advanceAccountingBalanceProjectionScan,
    'enumeration_complete');
  return {ledgerRunId: ledger.runId, journalRunId: journal.runId,
    orphanRunId: orphan.runId, balanceRunId: balance.runId};
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
    assert.equal(result.postingEpochGuardApplied, true);
    assert.equal(result.checks.postingEpoch.acrossRunsMatch, true);
    assert.equal(result.checks.postingEpoch.currentMatchesRuns, true);
    assert.equal(result.checks.postingEpoch.postingChangesObserved, false);
    assert.equal(result.checks.ledger.mismatchedAccounts, 0);
    assert.equal(result.checks.journal.failedEntries, 0);
    assert.equal(result.checks.orphanPaths.orphanLines, 0);
    assert.equal(result.checks.storedBalances.invalidBalanceDocuments, 0);
    assert.equal(result.checks.storedBalances.balancesChecked, 2);
    assert.equal(result.checks.storedBalanceAgreement.comparable, true);
    assert.equal(result.checks.storedBalanceAgreement.allAgree, true);
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
    const balance = await functions.startAccountingBalanceProjectionScan
      .run(req({storeId: store.id}));
    const runs = {
      ledgerRunId: ledger.runId,
      journalRunId: journal.runId,
      orphanRunId: orphan.runId,
      balanceRunId: balance.runId,
    };
    const result = await getReport(store.id, runs);
    assert.equal(result.verdict, 'incomplete');
    assert.equal(result.complete, false);
    assert.equal(result.checks.directPathCoverage.agrees, null);
    assert.equal(result.checks.storedBalanceAgreement.comparable, false);
    assert.equal(result.checks.storedBalanceAgreement.allAgree, null);
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

  it('marks changed source as stale without a false clean verdict', async () => {
    const store = await fixture('unified-audit-source-changed');
    const runs = await allRuns(store.id);
    await store.collection('accounting_journal_runs')
      .doc(runs.journalRunId).update({status: 'source_changed'});
    const result = await getReport(store.id, runs);
    assert.equal(result.verdict, 'source_changed');
    assert.equal(result.complete, false);
    assert.equal(result.certified, false);
    assert.equal(result.findings.some(
      (f) => f.code === 'JOURNAL_SCAN_NOT_COMPLETE'), true);
    await db.recursiveDelete(store);
  });

  it('flags differing historical scans even when ledger and journal agree', async () => {
    const store = await fixture('unified-audit-cross-time-drift');
    const ledger = await scan(store.id,
      functions.startAccountingLedgerReconciliation,
      functions.advanceAccountingLedgerReconciliation,
      'reconciliation_complete');
    const journal = await scan(store.id,
      functions.startAccountingJournalReconciliation,
      functions.advanceAccountingJournalReconciliation,
      'reconciliation_complete');
    // New source line arrives between historical scans. Only the final
    // tenant-path scan sees it; the independent sources are not atomic.
    await store.collection('journal_entries').doc('posted')
      .collection('lines').doc('late-line').set({
        storeId: store.id, entryId: 'posted', accountId: '1110',
        currency: 'ILS', debitMinorUnits: 1, creditMinorUnits: 0,
      });
    const orphan = await scan(store.id,
      functions.startAccountingOrphanPathScan,
      functions.advanceAccountingOrphanPathScan,
      'enumeration_complete');
    const balance = await scan(store.id,
      functions.startAccountingBalanceProjectionScan,
      functions.advanceAccountingBalanceProjectionScan,
      'enumeration_complete');
    const report = await getReport(store.id, {
      ledgerRunId: ledger.runId,
      journalRunId: journal.runId,
      orphanRunId: orphan.runId,
      balanceRunId: balance.runId,
    });
    assert.equal(report.checks.crossRun.currencies[0].linesAgree, true);
    assert.equal(report.checks.directPathCoverage.agrees, false);
    assert.equal(report.checks.directPathCoverage.directHeaderLines, 2);
    assert.equal(report.checks.directPathCoverage.knownParentPathLines, 3);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.findings.some(
      (f) => f.code === 'DIRECT_JOURNAL_PATH_COUNT_DIFFERENCE'), true);
    await db.recursiveDelete(store);
  });

  it('detects an orphan stored balance even when all three older scans agree', async () => {
    const store = await fixture('unified-unmapped-account-balance');
    await store.collection('account_balances').doc('9999').set({
      storeId: store.id, accountId: '9999', currency: 'ILS',
      debitMinorUnits: 10, creditMinorUnits: 0, balanceMinorUnits: 10,
    });
    const runs = await allRuns(store.id);
    const report = await getReport(store.id, runs);
    assert.equal(report.complete, true);
    assert.equal(report.verdict, 'issues_found');
    assert.equal(report.certified, false);
    assert.equal(report.checks.ledger.mismatchedAccounts, 0);
    assert.equal(report.checks.storedBalances.balancesChecked, 3);
    assert.equal(report.checks.storedBalances.missingChartAccounts, 1);
    assert.equal(report.findings.some((finding) =>
      finding.code === 'BALANCES_WITHOUT_CHART_ACCOUNTS' &&
      finding.count === 1), true);
    assert.equal((await store.collection('account_balances')
      .doc('9999').get()).data().balanceMinorUnits, 10);
    await db.recursiveDelete(store);
  });

  it('does not report complete before mandatory reverse balance census ends', async () => {
    const store = await fixture('unified-reverse-balance-pending');
    const runs = await allRuns(store.id);
    await store.collection('accounting_balance_path_runs')
      .doc(runs.balanceRunId).update({status: 'running'});
    const report = await getReport(store.id, runs);
    assert.equal(report.complete, false);
    assert.equal(report.verdict, 'incomplete');
    assert.equal(report.findings.some((finding) =>
      finding.code === 'REVERSE_BALANCE_SCAN_NOT_COMPLETE'), true);
    await db.recursiveDelete(store);
  });


  it('flags internally valid balances changed after the ledger was scanned', async () => {
    const store = await fixture('unified-valid-money-cross-scan-drift');
    const ledger = await scan(store.id,
      functions.startAccountingLedgerReconciliation,
      functions.advanceAccountingLedgerReconciliation,
      'reconciliation_complete');
    const journal = await scan(store.id,
      functions.startAccountingJournalReconciliation,
      functions.advanceAccountingJournalReconciliation,
      'reconciliation_complete');
    const orphan = await scan(store.id,
      functions.startAccountingOrphanPathScan,
      functions.advanceAccountingOrphanPathScan,
      'enumeration_complete');
    // Balanced internally, but disagrees with the earlier ledger scan.
    await store.collection('account_balances').doc('1110').update({
      debitMinorUnits: 78, balanceMinorUnits: 78,
    });
    const balance = await scan(store.id,
      functions.startAccountingBalanceProjectionScan,
      functions.advanceAccountingBalanceProjectionScan,
      'enumeration_complete');
    const result = await getReport(store.id, {
      ledgerRunId: ledger.runId, journalRunId: journal.runId,
      orphanRunId: orphan.runId, balanceRunId: balance.runId,
    });
    assert.equal(result.complete, true);
    assert.equal(result.checks.ledger.mismatchedAccounts, 0);
    assert.equal(result.checks.storedBalances.invalidBalanceDocuments, 0);
    assert.equal(result.checks.crossRun.currencies[0].debitAgrees, true);
    assert.equal(result.checks.storedBalanceAgreement.allAgree, false);
    const [ils] = result.checks.storedBalanceAgreement.currencies;
    assert.equal(ils.indexed.debitTurnoverMinorUnits, 77);
    assert.equal(ils.stored.debitTurnoverMinorUnits, 78);
    assert.equal(ils.debitAgrees, false);
    assert.equal(result.verdict, 'issues_found');
    assert.equal(result.certified, false);
    assert.equal(result.findings.some((f) =>
      f.code === 'STORED_BALANCE_TOTALS_DIFFER_FROM_LEDGER'), true);
    assert.equal((await store.collection('account_balances')
      .doc('1110').get()).data().balanceMinorUnits, 78);
    await db.recursiveDelete(store);
  });

  it('compares ILS and USD without aggregating different currencies', async () => {
    const store = await fixture('unified-independent-currency-totals');
    for (const [id, debit, credit] of [
      ['1111', 22, 0], ['3111', 0, 22],
    ]) {
      await store.collection('accounts').doc(id).set({
        storeId: store.id, id, isHeader: false, currency: 'USD',
      });
      await store.collection('account_balances').doc(id).set({
        storeId: store.id, accountId: id, currency: 'USD',
        debitMinorUnits: debit, creditMinorUnits: credit,
        balanceMinorUnits: debit - credit,
      });
      await store.collection('journal_entries').doc('usd-posted')
        .collection('lines').doc(id).set({
          storeId: store.id, entryId: 'usd-posted', accountId: id,
          currency: 'USD', debitMinorUnits: debit,
          creditMinorUnits: credit,
        });
    }
    await store.collection('journal_entries').doc('usd-posted').set({
      storeId: store.id, status: 'posted', currency: 'USD',
      totalDebitMinorUnits: 22, totalCreditMinorUnits: 22,
    });
    const runs = await allRuns(store.id);
    const result = await getReport(store.id, runs);
    const rows = result.checks.storedBalanceAgreement.currencies;
    assert.deepEqual(rows.map((r) => r.currency), ['ILS', 'USD']);
    assert.equal(result.checks.storedBalanceAgreement.allAgree, true);
    assert.equal(rows[0].stored.debitTurnoverMinorUnits, 77);
    assert.equal(rows[1].stored.debitTurnoverMinorUnits, 22);
    assert.equal(result.verdict, 'observed_aggregates_agree_non_atomic');
    await db.recursiveDelete(store);
  });


  it('marks all running audit sources stale after a real journal posting', async () => {
    const store = await fixture('unified-posting-epoch-running');
    for (const [id, type] of [['1110', 'asset'], ['3110', 'equity']]) {
      await store.collection('accounts').doc(id).update({
        code: id, name: id, type, isActive: true,
      });
    }
    const scans = [
      [functions.startAccountingLedgerReconciliation,
        functions.advanceAccountingLedgerReconciliation],
      [functions.startAccountingJournalReconciliation,
        functions.advanceAccountingJournalReconciliation],
      [functions.startAccountingOrphanPathScan,
        functions.advanceAccountingOrphanPathScan],
      [functions.startAccountingBalanceProjectionScan,
        functions.advanceAccountingBalanceProjectionScan],
    ];
    const started = [];
    for (const [startFn] of scans) {
      started.push(await startFn.run(req({storeId: store.id})));
    }
    const posting = await functions.postJournalEntry.run(req({
      storeId: store.id,
      entry: {
        id: 'later-journal',
        idempotencyKey: 'later-journal-key',
        sourceType: 'manual',
        postedAt: '2026-10-24T09:00:00.000Z',
        description: 'Interleaved posting marker test',
        currency: 'ILS',
        lines: [
          {id: 'new-debit', accountId: '1110',
            debitMinorUnits: 3, creditMinorUnits: 0},
          {id: 'new-credit', accountId: '3110',
            debitMinorUnits: 0, creditMinorUnits: 3},
        ],
      },
    }));
    assert.equal(posting.status, 'posted');
    for (let i = 0; i < scans.length; i++) {
      const result = await scans[i][1].run(req({
        storeId: store.id, runId: started[i].runId,
      }));
      assert.equal(result.status, 'source_changed');
      assert.equal(result.certified, false);
    }
    const report = await getReport(store.id, {
      ledgerRunId: started[0].runId,
      journalRunId: started[1].runId,
      orphanRunId: started[2].runId,
      balanceRunId: started[3].runId,
    });
    assert.equal(report.verdict, 'source_changed');
    assert.equal(report.complete, false);
    assert.equal(report.certified, false);
    assert.equal(report.checks.postingEpoch.currentMatchesRuns, false);
    assert.equal(report.checks.postingEpoch.postingChangesObserved, true);
    assert.equal(report.findings.some((f) =>
      f.code === 'BACKEND_FINANCIAL_POSTING_EPOCH_CHANGED'), true);
    assert.equal((await store.collection('account_balances').doc('1110')
      .get()).data().balanceMinorUnits, 80);
    await db.recursiveDelete(store);
  });

  it('does not accept an old ledger scan mixed with a newer journal epoch', async () => {
    const store = await fixture('unified-posting-epoch-mixed-runs');
    for (const [id, type] of [['1110', 'asset'], ['3110', 'equity']]) {
      await store.collection('accounts').doc(id).update({
        code: id, name: id, type, isActive: true,
      });
    }
    const ledger = await scan(store.id,
      functions.startAccountingLedgerReconciliation,
      functions.advanceAccountingLedgerReconciliation,
      'reconciliation_complete');
    await functions.postJournalEntry.run(req({
      storeId: store.id,
      entry: {
        id: 'epoch-after-ledger', idempotencyKey: 'epoch-after-ledger-key',
        sourceType: 'manual', postedAt: '2026-10-24T10:00:00.000Z',
        currency: 'ILS', description: 'Posting between audit runs',
        lines: [
          {id: 'd', accountId: '1110',
            debitMinorUnits: 2, creditMinorUnits: 0},
          {id: 'c', accountId: '3110',
            debitMinorUnits: 0, creditMinorUnits: 2},
        ],
      },
    }));
    const journal = await scan(store.id,
      functions.startAccountingJournalReconciliation,
      functions.advanceAccountingJournalReconciliation,
      'reconciliation_complete');
    const orphan = await scan(store.id,
      functions.startAccountingOrphanPathScan,
      functions.advanceAccountingOrphanPathScan,
      'enumeration_complete');
    const balance = await scan(store.id,
      functions.startAccountingBalanceProjectionScan,
      functions.advanceAccountingBalanceProjectionScan,
      'enumeration_complete');
    const result = await getReport(store.id, {
      ledgerRunId: ledger.runId, journalRunId: journal.runId,
      orphanRunId: orphan.runId, balanceRunId: balance.runId,
    });
    assert.equal(result.checks.postingEpoch.acrossRunsMatch, false);
    assert.equal(result.checks.postingEpoch.currentMatchesRuns, false);
    assert.equal(result.verdict, 'source_changed');
    assert.equal(result.complete, false); // scans finished at incompatible eras
    assert.equal(result.certified, false);
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
    await assert.rejects(
      getReport(store.id, {...runs, balanceRunId: otherRuns.balanceRunId}),
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

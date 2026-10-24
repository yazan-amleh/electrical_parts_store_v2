'use strict';

// A single bounded, read-only readout of existing audit checkpoints.
// It is NOT a snapshot of the original accounting documents; each source
// audit was accumulated independently across many Firestore transactions.

const {
  checkComparable,
  comparison,
} = require('./audit_coverage');
const {trialBalanceSummary} = require('./trial_balance');
const {validatePathRun} = require('./orphan_path_scan');
const {validateBalanceProjectionRun} = require('./balance_projection_scan');
const {
  compareLedgerAndStoredBalances,
} = require('./balance_currency_coverage');

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function safeAdd(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Unified accounting audit counter overflow.');
  }
  return a + b;
}

function verifyOrphanRun(state, storeId, uid, HttpsError) {
  if (!state || state.storeId !== storeId || state.createdBy !== uid) {
    throw new HttpsError('permission-denied',
      'The orphan audit run belongs to another user or store.');
  }
  validatePathRun(state, storeId, uid, HttpsError);
  if (state.certified !== false ||
      state.accountingCutoffApplied !== false ||
      state.consistency !== 'non_atomic') {
    fail(HttpsError, 'Orphan census cannot be represented as certified.');
  }
}

function verifyBalanceRun(state, storeId, uid, HttpsError) {
  if (!state || state.storeId !== storeId || state.createdBy !== uid) {
    throw new HttpsError('permission-denied',
      'The reverse balance scan belongs to another user or store.');
  }
  validateBalanceProjectionRun(state, storeId, uid, HttpsError);
}

function buildUnifiedAuditReport({
  storeId, ledgerRunId, journalRunId, orphanRunId, balanceRunId,
  ledger, journal, orphan, balance,
}, HttpsError) {
  // All three sources must be fully validated before computing the verdict.
  // This function is exported for deterministic unit-test scenarios only.
  const trialBalance = trialBalanceSummary(ledger);
  const crossRun = comparison(ledger, journal);
  const storedBalanceAgreement = compareLedgerAndStoredBalances(
    ledger, balance);
  const directHeaderLines = journal.linesChecked;
  const knownParentPathLines =
    orphan.journalLinesScanned - orphan.orphanLines;
  if (!Number.isSafeInteger(knownParentPathLines) ||
      knownParentPathLines < 0) {
    fail(HttpsError, 'Orphan scan line counts are inconsistent.');
  }

  const finish = ledger.status === 'reconciliation_complete' &&
    journal.status === 'reconciliation_complete' &&
    orphan.status === 'enumeration_complete' &&
    balance.status === 'enumeration_complete';
  const sourceChanged = ledger.status === 'source_changed' ||
    journal.status === 'source_changed';
  // Compare ONLY after both independent scans have completed. A partial
  // count can coincidentally equal another partial or complete count.
  const directPathLinesAgree = finish
    ? knownParentPathLines === directHeaderLines : null;

  const findings = [];
  const addFinding = (code, count = null) => {
    findings.push({code, count});
  };
  if (ledger.status !== 'reconciliation_complete') {
    addFinding('LEDGER_SCAN_NOT_COMPLETE');
  }
  if (journal.status !== 'reconciliation_complete') {
    addFinding('JOURNAL_SCAN_NOT_COMPLETE');
  }
  if (orphan.status === 'budget_exhausted') {
    addFinding('ORPHAN_SCAN_BUDGET_EXHAUSTED');
  } else if (orphan.status !== 'enumeration_complete') {
    addFinding('ORPHAN_SCAN_NOT_COMPLETE');
  }
  if (ledger.mismatchCount > 0) {
    addFinding('ACCOUNT_BALANCE_MISMATCHES', ledger.mismatchCount);
  }
  if (ledger.unclassifiedPostingAccounts > 0) {
    addFinding('UNCLASSIFIED_POSTING_ACCOUNTS',
      ledger.unclassifiedPostingAccounts);
  }
  if (journal.failedEntries > 0) {
    addFinding('JOURNAL_ENTRY_ISSUES', journal.failedEntries);
  }
  if (journal.invalidAccountReferenceLines > 0) {
    addFinding('JOURNAL_INVALID_ACCOUNT_REFERENCES',
      journal.invalidAccountReferenceLines);
  }
  if (journal.potentiallyUnindexedLines > 0) {
    addFinding('JOURNAL_POTENTIALLY_UNINDEXED_LINES',
      journal.potentiallyUnindexedLines);
  }
  if (journal.unclassifiedJournalEntries > 0) {
    addFinding('UNCLASSIFIED_JOURNAL_ENTRIES',
      journal.unclassifiedJournalEntries);
  }
  if (balance.status !== 'enumeration_complete') {
    addFinding('REVERSE_BALANCE_SCAN_NOT_COMPLETE');
  }
  if (balance.invalidBalanceDocuments > 0) {
    addFinding('INVALID_STORED_ACCOUNT_BALANCES',
      balance.invalidBalanceDocuments);
  }
  if (balance.missingChartAccounts > 0) {
    addFinding('BALANCES_WITHOUT_CHART_ACCOUNTS',
      balance.missingChartAccounts);
  }
  if (balance.headerAccountsWithBalance > 0) {
    addFinding('NON_POSTING_HEADERS_WITH_BALANCE',
      balance.headerAccountsWithBalance);
  }
  if (balance.currencyMismatchBalances > 0) {
    addFinding('BALANCE_CURRENCY_MISMATCHES',
      balance.currencyMismatchBalances);
  }
  if (balance.invalidMoneyBalances > 0) {
    addFinding('INVALID_BALANCE_MONEY',
      balance.invalidMoneyBalances);
  }
  if (orphan.orphanLines > 0) {
    addFinding('ORPHAN_JOURNAL_LINES', orphan.orphanLines);
  }
  if (crossRun.currencies.some((row) =>
    !row.linesAgree || !row.debitAgrees || !row.creditAgrees)) {
    addFinding('INDEXED_DIRECT_CURRENCY_DIFFERENCES');
  }
  if (directPathLinesAgree === false) {
    addFinding('DIRECT_JOURNAL_PATH_COUNT_DIFFERENCE');
  }
  if (storedBalanceAgreement.allAgree === false) {
    addFinding('STORED_BALANCE_TOTALS_DIFFER_FROM_LEDGER');
  }
  if (trialBalance.verdict === 'out_of_balance') {
    addFinding('TRIAL_BALANCE_OUT_OF_BALANCE');
  }
  // This is an ALWAYS-ON non-certification finding, not a transient failure.
  addFinding('NO_IMMUTABLE_ACCOUNTING_CUTOFF');

  let verdict;
  if (sourceChanged) {
    verdict = 'source_changed';
  } else if (!finish) {
    verdict = 'incomplete';
  } else if (findings.some((finding) =>
    finding.code !== 'NO_IMMUTABLE_ACCOUNTING_CUTOFF')) {
    verdict = 'issues_found';
  } else if (ledger.postingAccountsCompared === 0 &&
      journal.entriesChecked === 0 && orphan.journalLinesScanned === 0) {
    verdict = 'empty_scope';
  } else {
    verdict = 'observed_aggregates_agree_non_atomic';
  }

  return {
    schemaVersion: 3,
    storeId,
    runIds: {ledgerRunId, journalRunId, orphanRunId, balanceRunId},
    verdict,
    complete: finish,
    certified: false,
    accountingCutoffApplied: false,
    consistency: 'non_atomic',
    sourceSnapshotGuaranteed: false,
    checks: {
      ledger: {
        status: ledger.status,
        accountsCompared: ledger.accountsCompared,
        mismatchedAccounts: ledger.mismatchCount,
        trialBalance,
      },
      journal: {
        status: journal.status,
        entriesChecked: journal.entriesChecked,
        directLinesChecked: journal.linesChecked,
        failedEntries: journal.failedEntries,
        invalidAccountReferenceLines:
          journal.invalidAccountReferenceLines,
        potentiallyUnindexedLines: journal.potentiallyUnindexedLines,
        unclassifiedJournalEntries: journal.unclassifiedJournalEntries,
      },
      storedBalances: {
        status: balance.status,
        balancesChecked: balance.balancesChecked,
        invalidBalanceDocuments: balance.invalidBalanceDocuments,
        missingChartAccounts: balance.missingChartAccounts,
        headerAccountsWithBalance: balance.headerAccountsWithBalance,
        currencyMismatchBalances: balance.currencyMismatchBalances,
        invalidMoneyBalances: balance.invalidMoneyBalances,
        issueSamples: [...balance.issueSamples],
      },
      orphanPaths: {
        status: orphan.status,
        groupDocumentsScanned: orphan.groupDocumentsScanned,
        journalLinesScanned: orphan.journalLinesScanned,
        orphanLines: orphan.orphanLines,
        orphansWithoutCorrectStoreId:
          orphan.orphansWithoutCorrectStoreId,
        orphanSamples: [...orphan.orphanSamples],
      },
      crossRun,
      storedBalanceAgreement,
      directPathCoverage: {
        complete: finish,
        directHeaderLines,
        knownParentPathLines,
        agrees: directPathLinesAgree,
      },
    },
    findings,
  };
}

async function getUnifiedAuditReport({
  db, HttpsError, storeId, uid,
  ledgerRunId, journalRunId, orphanRunId, balanceRunId, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  // This Firestore transaction ensures checkpoint reads are simultaneous.
  // It cannot retroactively snapshot the source documents scanned earlier.
  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(uid));
    assertAccess(member, storeId);

    const refs = [
      store.collection('accounting_ledger_runs').doc(ledgerRunId),
      store.collection('accounting_journal_runs').doc(journalRunId),
      store.collection('accounting_orphan_path_runs').doc(orphanRunId),
      store.collection('accounting_balance_path_runs').doc(balanceRunId),
    ];
    const [ledgerSnap, journalSnap, orphanSnap, balanceSnap] = await Promise.all(
      refs.map((ref) => tx.get(ref)),
    );
    if (!ledgerSnap.exists || !journalSnap.exists ||
        !orphanSnap.exists || !balanceSnap.exists) {
      throw new HttpsError('not-found',
        'All four existing audit runs must be supplied.');
    }
    const ledger = ledgerSnap.data();
    const journal = journalSnap.data();
    const orphan = orphanSnap.data();
    const balance = balanceSnap.data();
    checkComparable(ledger, journal, storeId, uid, HttpsError);
    verifyOrphanRun(orphan, storeId, uid, HttpsError);
    verifyBalanceRun(balance, storeId, uid, HttpsError);

    // Keep the checkpoint metadata bound to its own read-only scan; the
    // server never changes accounting postings, projections or audit runs.
    return buildUnifiedAuditReport({
      storeId, ledgerRunId, journalRunId, orphanRunId, balanceRunId,
      ledger, journal, orphan, balance,
    }, HttpsError);
  });
}

module.exports = {
  safeAdd,
  verifyOrphanRun,
  verifyBalanceRun,
  buildUnifiedAuditReport,
  getUnifiedAuditReport,
};

'use strict';

// Cross-check two independently accumulated, non-atomic audit views.
// This is a consistency signal, NEVER point-in-time audit certification.
const MAX_CURRENCIES = 16;
const VALID_CURRENCY = /^[A-Z]{3}$/;
const {
  readPostingEpoch,
  validateEpoch,
  epochsMatch,
} = require('./posting_epoch');

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function add(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Audit coverage counter exceeds safe integer range.');
  }
  return a + b;
}

function emptyJournalCurrency() {
  return {
    entries: 0,
    failedEntries: 0,
    directJournalLines: 0,
    debitMinorUnits: 0,
    creditMinorUnits: 0,
  };
}

function validateJournalCoverage(state, HttpsError) {
  if (!state || !state.journalCurrencyTotals ||
      typeof state.journalCurrencyTotals !== 'object' ||
      Array.isArray(state.journalCurrencyTotals) ||
      !Number.isSafeInteger(state.unclassifiedJournalEntries) ||
      state.unclassifiedJournalEntries < 0 ||
      !Number.isSafeInteger(state.entriesChecked) ||
      state.entriesChecked < 0 ||
      !Number.isSafeInteger(state.failedEntries) ||
      state.failedEntries < 0 ||
      !Number.isSafeInteger(state.linesChecked) ||
      state.linesChecked < 0) {
    fail(HttpsError, 'Invalid journal coverage metadata.');
  }
  const groups = Object.entries(state.journalCurrencyTotals);
  if (groups.length > MAX_CURRENCIES) {
    fail(HttpsError, 'Journal coverage exceeds currency limit.');
  }
  let countedEntries = state.unclassifiedJournalEntries;
  let groupedFailures = 0;
  let groupedLines = 0;
  for (const [currency, values] of groups) {
    if (!VALID_CURRENCY.test(currency) || !values ||
        typeof values !== 'object' || Array.isArray(values)) {
      fail(HttpsError, 'Invalid journal coverage currency.');
    }
    for (const key of Object.keys(emptyJournalCurrency())) {
      if (!Number.isSafeInteger(values[key]) || values[key] < 0) {
        fail(HttpsError, 'Invalid journal coverage totals.');
      }
    }
    if (values.failedEntries > values.entries) {
      fail(HttpsError, 'Invalid journal coverage failure counts.');
    }
    countedEntries = add(countedEntries, values.entries, HttpsError);
    groupedFailures = add(groupedFailures, values.failedEntries, HttpsError);
    groupedLines = add(groupedLines, values.directJournalLines, HttpsError);
  }
  if (countedEntries !== state.entriesChecked ||
      groupedFailures > state.failedEntries ||
      groupedLines > state.linesChecked) {
    fail(HttpsError, 'Journal coverage totals conflict with checkpoint.');
  }
}

function appendJournalCoverage(
  state, {currency, lineCount, debit, credit, matched}, HttpsError,
) {
  validateJournalCoverage(state, HttpsError);
  for (const value of [lineCount, debit, credit]) {
    if (!Number.isSafeInteger(value) || value < 0) {
      fail(HttpsError, 'Invalid journal amounts used for coverage.');
    }
  }
  const result = {
    unclassifiedJournalEntries: state.unclassifiedJournalEntries,
    journalCurrencyTotals: {...state.journalCurrencyTotals},
  };
  if (typeof currency !== 'string' || !VALID_CURRENCY.test(currency)) {
    result.unclassifiedJournalEntries = add(
      result.unclassifiedJournalEntries, 1, HttpsError,
    );
    return result;
  }
  const present = Object.prototype.hasOwnProperty.call(
    result.journalCurrencyTotals, currency,
  );
  if (!present && Object.keys(result.journalCurrencyTotals).length >=
      MAX_CURRENCIES) {
    fail(HttpsError, 'Journal coverage currency limit exceeded.');
  }
  const previous = present
    ? result.journalCurrencyTotals[currency] : emptyJournalCurrency();
  result.journalCurrencyTotals[currency] = {
    entries: add(previous.entries, 1, HttpsError),
    failedEntries: add(previous.failedEntries, matched ? 0 : 1, HttpsError),
    directJournalLines: add(
      previous.directJournalLines, lineCount, HttpsError,
    ),
    debitMinorUnits: add(previous.debitMinorUnits, debit, HttpsError),
    creditMinorUnits: add(previous.creditMinorUnits, credit, HttpsError),
  };
  return result;
}

function comparison(ledger, journal) {
  // Do not use the term "verified" or "certified" for a historical
  // calculation spanning multiple Firestore transactions.
  const currencies = [...new Set([
    ...Object.keys(ledger.trialBalanceByCurrency),
    ...Object.keys(journal.journalCurrencyTotals),
  ])].sort().map((currency) => {
    const l = ledger.trialBalanceByCurrency[currency];
    const j = journal.journalCurrencyTotals[currency];
    const indexedJournalLines = l ? l.indexedJournalLines : 0;
    const directJournalLines = j ? j.directJournalLines : 0;
    const indexedDebitMinorUnits = l ? l.debitTurnoverMinorUnits : 0;
    const indexedCreditMinorUnits = l ? l.creditTurnoverMinorUnits : 0;
    const directDebitMinorUnits = j ? j.debitMinorUnits : 0;
    const directCreditMinorUnits = j ? j.creditMinorUnits : 0;
    return {
      currency,
      indexedJournalLines,
      directJournalLines,
      indexedDebitMinorUnits,
      directDebitMinorUnits,
      indexedCreditMinorUnits,
      directCreditMinorUnits,
      linesAgree: indexedJournalLines === directJournalLines,
      debitAgrees: indexedDebitMinorUnits === directDebitMinorUnits,
      creditAgrees: indexedCreditMinorUnits === directCreditMinorUnits,
    };
  });
  const allAmountsAgree = currencies.every((c) =>
    c.linesAgree && c.debitAgrees && c.creditAgrees);
  let verdict;
  if (ledger.status === 'source_changed' ||
      journal.status === 'source_changed') {
    verdict = 'source_changed';
  } else if (ledger.status !== 'reconciliation_complete' ||
      journal.status !== 'reconciliation_complete') {
    verdict = 'incomplete';
  } else if (ledger.mismatchCount > 0 || journal.failedEntries > 0 ||
      ledger.unclassifiedPostingAccounts > 0 ||
      journal.unclassifiedJournalEntries > 0) {
    verdict = 'issues_found';
  } else if (!allAmountsAgree) {
    verdict = 'cross_run_difference';
  } else if (ledger.postingAccountsCompared === 0 &&
      journal.entriesChecked === 0) {
    verdict = 'empty_scope';
  } else {
    verdict = 'aggregate_coverage_agrees_non_atomic';
  }
  return {
    verdict,
    certified: false,
    accountingCutoffApplied: false,
    consistency: 'non_atomic',
    scope: 'cross_run_aggregate_ledger_vs_direct_journal_lines',
    ledgerRunStatus: ledger.status,
    journalRunStatus: journal.status,
    accountsCompared: ledger.accountsCompared,
    entriesChecked: journal.entriesChecked,
    // By-currency counters are kept separate to avoid unsafe overflow
    // when large tenants have many currencies.
    directJournalLines: journal.linesChecked,
    currencies,
  };
}

function checkComparable(ledger, journal, storeId, uid, HttpsError) {
  if (!ledger || !journal ||
      ledger.storeId !== storeId || journal.storeId !== storeId ||
      ledger.createdBy !== uid || journal.createdBy !== uid) {
    throw new HttpsError('permission-denied',
      'Audit runs must belong to the current store and requester.');
  }
  if (ledger.schemaVersion !== 4 || journal.schemaVersion !== 4) {
    fail(HttpsError, 'Audits must use compatible evidence schema versions.');
  }
  if (!['running', 'reconciliation_complete', 'source_changed']
    .includes(ledger.status) ||
      !['running', 'reconciliation_complete', 'source_changed']
        .includes(journal.status) ||
      ledger.certified !== false || journal.certified !== false ||
      ledger.accountingCutoffApplied !== false ||
      journal.accountingCutoffApplied !== false ||
      !Number.isSafeInteger(ledger.accountsCompared) ||
      !Number.isSafeInteger(ledger.mismatchCount) ||
      ledger.mismatchCount < 0 ||
      ledger.mismatchCount > ledger.accountsCompared ||
      !Number.isSafeInteger(ledger.unclassifiedPostingAccounts) ||
      ledger.unclassifiedPostingAccounts < 0 ||
      !Number.isSafeInteger(ledger.postingAccountsCompared)) {
    fail(HttpsError, 'Audit checkpoints are not comparable.');
  }
  const {validateTrialBalance} = require('./trial_balance');
  validateTrialBalance(ledger, HttpsError);
  validateJournalCoverage(journal, HttpsError);
  validateEpoch(ledger.postingEpoch, HttpsError);
  validateEpoch(journal.postingEpoch, HttpsError);
}

async function compareAuditRunCoverage({
  db, HttpsError, storeId, uid, ledgerRunId, journalRunId, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  // Transaction establishes consistency for these two *checkpoint docs*;
  // it does not impose a snapshot on any source histories already scanned.
  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(uid));
    assertAccess(member, storeId);
    const [ledgerSnapshot, journalSnapshot] = await Promise.all([
      tx.get(store.collection('accounting_ledger_runs').doc(ledgerRunId)),
      tx.get(store.collection('accounting_journal_runs').doc(journalRunId)),
    ]);
    if (!ledgerSnapshot.exists || !journalSnapshot.exists) {
      throw new HttpsError('not-found', 'Audit checkpoint not found.');
    }
    const ledger = ledgerSnapshot.data();
    const journal = journalSnapshot.data();
    checkComparable(ledger, journal, storeId, uid, HttpsError);
    const currentEpoch = await readPostingEpoch(tx, store, HttpsError);
    const epochAgrees = epochsMatch(ledger.postingEpoch, journal.postingEpoch) &&
      epochsMatch(currentEpoch, ledger.postingEpoch);
    const result = comparison(ledger, journal);
    return {
      storeId,
      ledgerRunId,
      journalRunId,
      ...result,
      verdict: epochAgrees ? result.verdict : 'source_changed',
      postingEpochGuardApplied: true,
      postingChangesObserved: !epochAgrees,
      certified: false,
    };
  });
}

module.exports = {
  emptyJournalCurrency,
  validateJournalCoverage,
  appendJournalCoverage,
  comparison,
  checkComparable,
  compareAuditRunCoverage,
};

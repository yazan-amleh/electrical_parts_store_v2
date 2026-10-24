'use strict';

// Derived, non-certifying trial-balance evidence from per-account indexed
// journal scans. Never net different currencies or infer FX conversions.
const MAX_CURRENCIES = 16;
const VALID_CURRENCY = /^[A-Z]{3}$/;

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function safeAdd(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Trial balance integer overflow.');
  }
  return a + b;
}

function emptyCurrency() {
  return {
    postingAccounts: 0,
    mismatchedAccounts: 0,
    indexedJournalLines: 0,
    debitTurnoverMinorUnits: 0,
    creditTurnoverMinorUnits: 0,
    debitClosingMinorUnits: 0,
    creditClosingMinorUnits: 0,
  };
}

function validateTrialBalance(state, HttpsError) {
  if (!Number.isSafeInteger(state.postingAccountsCompared) ||
      state.postingAccountsCompared < 0 ||
      !Number.isSafeInteger(state.unclassifiedPostingAccounts) ||
      state.unclassifiedPostingAccounts < 0 ||
      !state.trialBalanceByCurrency ||
      typeof state.trialBalanceByCurrency !== 'object' ||
      Array.isArray(state.trialBalanceByCurrency)) {
    fail(HttpsError, 'Trial balance checkpoint metadata is invalid.');
  }
  const entries = Object.entries(state.trialBalanceByCurrency);
  if (entries.length > MAX_CURRENCIES) {
    fail(HttpsError, 'Too many currencies in trial balance checkpoint.');
  }
  let accounted = state.unclassifiedPostingAccounts;
  for (const [currency, value] of entries) {
    if (!VALID_CURRENCY.test(currency) || !value ||
        typeof value !== 'object' || Array.isArray(value)) {
      fail(HttpsError, 'Trial balance currency metadata is invalid.');
    }
    for (const key of Object.keys(emptyCurrency())) {
      if (!Number.isSafeInteger(value[key]) || value[key] < 0) {
        fail(HttpsError, 'Trial balance totals are invalid.');
      }
    }
    if (value.mismatchedAccounts > value.postingAccounts) {
      fail(HttpsError, 'Trial balance counts are inconsistent.');
    }
    accounted = safeAdd(accounted, value.postingAccounts, HttpsError);
  }
  if (accounted !== state.postingAccountsCompared) {
    fail(HttpsError, 'Trial balance account count does not match checkpoint.');
  }
}

function appendAccountToTrialBalance(
  state, {storeId, account, debit, credit, matched,
    acceptedLines = 0}, HttpsError,
) {
  validateTrialBalance(state, HttpsError);
  if (!Number.isSafeInteger(acceptedLines) || acceptedLines < 0) {
    fail(HttpsError, 'Invalid indexed journal line count.');
  }
  if (account.isHeader === true) {
    return {
      postingAccountsCompared: state.postingAccountsCompared,
      unclassifiedPostingAccounts: state.unclassifiedPostingAccounts,
      trialBalanceByCurrency: state.trialBalanceByCurrency,
    };
  }

  const postingAccountsCompared = safeAdd(
    state.postingAccountsCompared, 1, HttpsError,
  );
  const currency = account.currency;
  if (account.storeId !== storeId ||
      typeof currency !== 'string' ||
      !VALID_CURRENCY.test(currency)) {
    return {
      postingAccountsCompared,
      unclassifiedPostingAccounts: safeAdd(
        state.unclassifiedPostingAccounts, 1, HttpsError,
      ),
      trialBalanceByCurrency: state.trialBalanceByCurrency,
    };
  }

  const values = {...state.trialBalanceByCurrency};
  const old = Object.prototype.hasOwnProperty.call(values, currency)
    ? values[currency] : emptyCurrency();
  if (!Object.prototype.hasOwnProperty.call(values, currency) &&
      Object.keys(values).length >= MAX_CURRENCIES) {
    fail(HttpsError, 'Trial balance currency limit exceeded.');
  }
  const net = safeAdd(debit, -credit, HttpsError);
  values[currency] = {
    postingAccounts: safeAdd(old.postingAccounts, 1, HttpsError),
    indexedJournalLines: safeAdd(
      old.indexedJournalLines, acceptedLines, HttpsError,
    ),
    mismatchedAccounts: safeAdd(
      old.mismatchedAccounts, matched ? 0 : 1, HttpsError,
    ),
    debitTurnoverMinorUnits: safeAdd(
      old.debitTurnoverMinorUnits, debit, HttpsError,
    ),
    creditTurnoverMinorUnits: safeAdd(
      old.creditTurnoverMinorUnits, credit, HttpsError,
    ),
    debitClosingMinorUnits: safeAdd(
      old.debitClosingMinorUnits, Math.max(0, net), HttpsError,
    ),
    creditClosingMinorUnits: safeAdd(
      old.creditClosingMinorUnits, Math.max(0, -net), HttpsError,
    ),
  };
  return {
    postingAccountsCompared,
    unclassifiedPostingAccounts: state.unclassifiedPostingAccounts,
    trialBalanceByCurrency: values,
  };
}

function trialBalanceSummary(state) {
  const currencies = Object.entries(state.trialBalanceByCurrency)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([currency, values]) => ({
      currency, ...values,
      turnoverBalanced: values.debitTurnoverMinorUnits ===
        values.creditTurnoverMinorUnits,
      closingBalanced: values.debitClosingMinorUnits ===
        values.creditClosingMinorUnits,
    }));
  let verdict = state.status === 'source_changed'
    ? 'source_changed' : 'incomplete';
  if (state.status === 'reconciliation_complete') {
    if (state.mismatchCount > 0 ||
        state.unclassifiedPostingAccounts > 0) {
      verdict = 'issues_found';
    } else if (currencies.some((row) =>
      !row.turnoverBalanced || !row.closingBalanced)) {
      verdict = 'out_of_balance';
    } else if (state.postingAccountsCompared === 0) {
      verdict = 'no_posting_accounts';
    } else {
      verdict = 'balanced_indexed_evidence_only';
    }
  }
  return {
    verdict,
    complete: state.status === 'reconciliation_complete',
    certified: false,
    accountingCutoffApplied: false,
    consistency: 'non_atomic',
    source: 'indexed_posted_journal_lines_for_known_chart_accounts',
    postingAccountsCompared: state.postingAccountsCompared,
    unclassifiedPostingAccounts: state.unclassifiedPostingAccounts,
    currencies,
  };
}

module.exports = {
  MAX_CURRENCIES,
  emptyCurrency,
  validateTrialBalance,
  appendAccountToTrialBalance,
  trialBalanceSummary,
};

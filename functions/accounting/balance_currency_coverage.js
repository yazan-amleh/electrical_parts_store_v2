'use strict';

// Independent per-currency aggregation of *valid stored GL projections*.
// Used to compare a later reverse scan with an earlier indexed-ledger scan.
// Neither scan guarantees a source snapshot across pages or between runs.

const MAX_CURRENCIES = 16;
const VALID_CURRENCY = /^[A-Z]{3}$/;

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}
function safeAdd(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Stored balance aggregate exceeds safe integer range.');
  }
  return a + b;
}
function emptyCurrency() {
  return {
    balanceDocuments: 0,
    debitTurnoverMinorUnits: 0,
    creditTurnoverMinorUnits: 0,
    debitClosingMinorUnits: 0,
    creditClosingMinorUnits: 0,
  };
}
function validateBalanceTotals(state, HttpsError) {
  if (!state || !state.balanceTotalsByCurrency ||
      typeof state.balanceTotalsByCurrency !== 'object' ||
      Array.isArray(state.balanceTotalsByCurrency) ||
      !Number.isSafeInteger(state.balancesChecked) ||
      state.balancesChecked < 0 ||
      !Number.isSafeInteger(state.invalidBalanceDocuments) ||
      state.invalidBalanceDocuments < 0) {
    fail(HttpsError, 'Missing stored-balance aggregate checkpoint.');
  }
  const rows = Object.entries(state.balanceTotalsByCurrency);
  if (rows.length > MAX_CURRENCIES) {
    fail(HttpsError, 'Stored-balance currency-group limit exceeded.');
  }
  let validDocuments = 0;
  for (const [currency, values] of rows) {
    if (!VALID_CURRENCY.test(currency) || !values ||
        typeof values !== 'object' || Array.isArray(values)) {
      fail(HttpsError, 'Invalid stored-balance currency group.');
    }
    for (const field of Object.keys(emptyCurrency())) {
      if (!Number.isSafeInteger(values[field]) || values[field] < 0) {
        fail(HttpsError, 'Invalid stored-balance aggregate amount.');
      }
    }
    validDocuments = safeAdd(validDocuments, values.balanceDocuments,
      HttpsError);
  }
  if (safeAdd(validDocuments, state.invalidBalanceDocuments, HttpsError) !==
      state.balancesChecked) {
    fail(HttpsError, 'Stored-balance totals do not cover scanned documents.');
  }
}

function addStoredBalance(totals, balance, HttpsError) {
  const currency = balance.currency;
  const next = {...totals};
  if (!VALID_CURRENCY.test(currency)) {
    fail(HttpsError, 'Cannot aggregate an invalid stored balance currency.');
  }
  if (!Object.prototype.hasOwnProperty.call(next, currency) &&
      Object.keys(next).length >= MAX_CURRENCIES) {
    fail(HttpsError, 'Stored-balance currency-group limit exceeded.');
  }
  const old = Object.prototype.hasOwnProperty.call(next, currency)
    ? next[currency] : emptyCurrency();
  const net = balance.balanceMinorUnits;
  next[currency] = {
    balanceDocuments: safeAdd(old.balanceDocuments, 1, HttpsError),
    debitTurnoverMinorUnits: safeAdd(old.debitTurnoverMinorUnits,
      balance.debitMinorUnits, HttpsError),
    creditTurnoverMinorUnits: safeAdd(old.creditTurnoverMinorUnits,
      balance.creditMinorUnits, HttpsError),
    debitClosingMinorUnits: safeAdd(old.debitClosingMinorUnits,
      Math.max(net, 0), HttpsError),
    creditClosingMinorUnits: safeAdd(old.creditClosingMinorUnits,
      Math.max(-net, 0), HttpsError),
  };
  return next;
}

function compareLedgerAndStoredBalances(ledger, balance) {
  const comparable = ledger.status === 'reconciliation_complete' &&
    balance.status === 'enumeration_complete';
  if (!comparable) {
    return {comparable: false, allAgree: null, currencies: [],
      consistency: 'non_atomic', certified: false};
  }
  const codes = new Set([...Object.keys(ledger.trialBalanceByCurrency),
    ...Object.keys(balance.balanceTotalsByCurrency)]);
  const currencies = [...codes].sort().map((currency) => {
    const indexed = ledger.trialBalanceByCurrency[currency] || emptyCurrency();
    const stored = balance.balanceTotalsByCurrency[currency] ||
      emptyCurrency();
    return {
      currency,
      indexed: {
        debitTurnoverMinorUnits: indexed.debitTurnoverMinorUnits,
        creditTurnoverMinorUnits: indexed.creditTurnoverMinorUnits,
        debitClosingMinorUnits: indexed.debitClosingMinorUnits,
        creditClosingMinorUnits: indexed.creditClosingMinorUnits,
      },
      stored: {
        debitTurnoverMinorUnits: stored.debitTurnoverMinorUnits,
        creditTurnoverMinorUnits: stored.creditTurnoverMinorUnits,
        debitClosingMinorUnits: stored.debitClosingMinorUnits,
        creditClosingMinorUnits: stored.creditClosingMinorUnits,
      },
      debitAgrees: indexed.debitTurnoverMinorUnits ===
        stored.debitTurnoverMinorUnits,
      creditAgrees: indexed.creditTurnoverMinorUnits ===
        stored.creditTurnoverMinorUnits,
      debitClosingAgrees: indexed.debitClosingMinorUnits ===
        stored.debitClosingMinorUnits,
      creditClosingAgrees: indexed.creditClosingMinorUnits ===
        stored.creditClosingMinorUnits,
    };
  });
  return {
    comparable: true,
    allAgree: currencies.every((row) =>
      row.debitAgrees && row.creditAgrees &&
      row.debitClosingAgrees && row.creditClosingAgrees),
    currencies,
    consistency: 'non_atomic',
    certified: false,
  };
}

module.exports = {
  MAX_CURRENCIES,
  emptyCurrency,
  validateBalanceTotals,
  addStoredBalance,
  compareLedgerAndStoredBalances,
};

'use strict';

const assert = require('node:assert/strict');
const {describe, it} = require('node:test');
const {
  MAX_CURRENCIES,
  emptyCurrency,
  validateBalanceTotals,
  addStoredBalance,
  compareLedgerAndStoredBalances,
} = require('./accounting/balance_currency_coverage');

class Preconditions extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}
const baseline = () => ({
  balancesChecked: 0,
  invalidBalanceDocuments: 0,
  balanceTotalsByCurrency: {},
});
const row = (currency, debit, credit) => ({
  currency,
  debitMinorUnits: debit,
  creditMinorUnits: credit,
  balanceMinorUnits: debit - credit,
});

describe('independent stored-balance currency totals', () => {
  it('accumulates both turnover and net-closing sides separately by currency', () => {
    let totals = {};
    totals = addStoredBalance(totals, row('ILS', 27, 0), Preconditions);
    totals = addStoredBalance(totals, row('ILS', 0, 27), Preconditions);
    totals = addStoredBalance(totals, row('USD', 9, 4), Preconditions);
    const state = {balancesChecked: 3, invalidBalanceDocuments: 0,
      balanceTotalsByCurrency: totals};
    validateBalanceTotals(state, Preconditions);
    assert.deepEqual(totals.ILS, {
      balanceDocuments: 2,
      debitTurnoverMinorUnits: 27,
      creditTurnoverMinorUnits: 27,
      debitClosingMinorUnits: 27,
      creditClosingMinorUnits: 27,
    });
    assert.equal(totals.USD.debitClosingMinorUnits, 5);
    assert.equal(totals.USD.creditClosingMinorUnits, 0);
  });

  it('forbids checkpoint totals whose included documents do not reconcile', () => {
    const state = baseline();
    state.balancesChecked = 2;
    state.balanceTotalsByCurrency.ILS = {...emptyCurrency(),
      balanceDocuments: 1};
    assert.throws(() => validateBalanceTotals(state, Preconditions),
      (e) => e.code === 'failed-precondition');
  });

  it('does not mutate existing totals when a safe-integer overflow occurs', () => {
    const totals = {ILS: {
      ...emptyCurrency(),
      balanceDocuments: 1,
      debitTurnoverMinorUnits: Number.MAX_SAFE_INTEGER,
    }};
    assert.throws(() => addStoredBalance(totals,
      row('ILS', 1, 0), Preconditions),
    (e) => e.code === 'failed-precondition');
    assert.equal(totals.ILS.debitTurnoverMinorUnits, Number.MAX_SAFE_INTEGER);
    assert.equal(totals.ILS.balanceDocuments, 1);
  });

  it('fails when adding a seventeenth currency grouping', () => {
    const totals = {};
    for (let i = 0; i < MAX_CURRENCIES; i++) {
      const code = 'X' + String.fromCharCode(65 + i) + 'X';
      totals[code] = {...emptyCurrency(), balanceDocuments: 1};
    }
    assert.throws(() => addStoredBalance(totals,
      row('YYY', 1, 0), Preconditions),
    (e) => e.code === 'failed-precondition');
    assert.equal(Object.keys(totals).length, MAX_CURRENCIES);
  });

  it('does not claim cross-run agreement while either audit is incomplete', () => {
    const left = {status: 'running', trialBalanceByCurrency: {}};
    const right = {status: 'enumeration_complete',
      balanceTotalsByCurrency: {}};
    assert.deepEqual(compareLedgerAndStoredBalances(left, right), {
      comparable: false, allAgree: null, currencies: [],
      consistency: 'non_atomic', certified: false,
    });
  });

  it('finds a mismatch in one currency despite matching total across currencies', () => {
    const ledger = {status: 'reconciliation_complete',
      trialBalanceByCurrency: {
        ILS: {...emptyCurrency(), debitTurnoverMinorUnits: 100},
        USD: {...emptyCurrency(), debitTurnoverMinorUnits: 80},
      }};
    const balance = {status: 'enumeration_complete',
      balanceTotalsByCurrency: {
        ILS: {...emptyCurrency(), debitTurnoverMinorUnits: 99},
        USD: {...emptyCurrency(), debitTurnoverMinorUnits: 81},
      }};
    const result = compareLedgerAndStoredBalances(ledger, balance);
    assert.equal(result.allAgree, false);
    assert.deepEqual(result.currencies.map((r) => r.currency),
      ['ILS', 'USD']);
    assert.equal(result.currencies[0].debitAgrees, false);
    assert.equal(result.currencies[1].debitAgrees, false);
    assert.equal(result.certified, false);
  });
});

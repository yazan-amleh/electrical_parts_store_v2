'use strict';

const assert = require('node:assert/strict');
const {describe, it} = require('node:test');
const {
  MAX_CURRENCIES,
  emptyCurrency,
  validateTrialBalance,
  appendAccountToTrialBalance,
  trialBalanceSummary,
} = require('./accounting/trial_balance');

class AuditFailure extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function state() {
  return {
    status: 'running',
    mismatchCount: 0,
    postingAccountsCompared: 0,
    unclassifiedPostingAccounts: 0,
    trialBalanceByCurrency: {},
  };
}
function account(currency, isHeader = false) {
  return {storeId: 'shop-a', currency, isHeader};
}

describe('trial balance safe grouped accounting', () => {
  it('groups debit and credit turnovers, and closing sides per currency', () => {
    let current = state();
    current = {...current, ...appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('ILS'), debit: 125, credit: 0,
      matched: true,
    }, AuditFailure)};
    current = {...current, ...appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('ILS'), debit: 0, credit: 125,
      matched: true,
    }, AuditFailure)};
    current = {...current, ...appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('USD'), debit: 21, credit: 0,
      matched: true,
    }, AuditFailure)};
    current.status = 'reconciliation_complete';
    const summary = trialBalanceSummary(current);
    assert.equal(summary.verdict, 'out_of_balance');
    assert.deepEqual(summary.currencies.map((row) => row.currency),
      ['ILS', 'USD']);
    assert.equal(summary.currencies[0].turnoverBalanced, true);
    assert.equal(summary.currencies[1].closingBalanced, false);
    assert.equal(summary.certified, false);
    assert.equal(summary.accountingCutoffApplied, false);
  });

  it('omits non-posting chart headers even if currency is valid', () => {
    const current = state();
    const next = appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('ILS', true),
      debit: 0, credit: 0, matched: true,
    }, AuditFailure);
    assert.equal(next.postingAccountsCompared, 0);
    assert.deepEqual(next.trialBalanceByCurrency, {});
  });

  it('fails closed on unsafe cumulative totals with no checkpoint mutation', () => {
    const current = state();
    current.postingAccountsCompared = 1;
    current.trialBalanceByCurrency.ILS = {
      ...emptyCurrency(),
      postingAccounts: 1,
      debitTurnoverMinorUnits: Number.MAX_SAFE_INTEGER,
    };
    assert.throws(() => appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('ILS'),
      debit: 1, credit: 0, matched: true,
    }, AuditFailure), (error) => error.code === 'failed-precondition');
    assert.equal(current.trialBalanceByCurrency.ILS.debitTurnoverMinorUnits,
      Number.MAX_SAFE_INTEGER);
    assert.equal(current.postingAccountsCompared, 1);
  });

  it('rejects malformed persisted groups rather than treating them as zero', () => {
    const current = state();
    current.trialBalanceByCurrency.USD = {
      ...emptyCurrency(), postingAccounts: -1,
    };
    assert.throws(
      () => validateTrialBalance(current, AuditFailure),
      (error) => error.code === 'failed-precondition',
    );
  });

  it('bounds the number of currency groups in a checkpoint', () => {
    const current = state();
    let count = 0;
    for (let a = 65; a <= 90 && count < MAX_CURRENCIES; a++) {
      const currency = 'X' + String.fromCharCode(a) + 'X';
      current.trialBalanceByCurrency[currency] = {
        ...emptyCurrency(), postingAccounts: 1,
      };
      count++;
    }
    current.postingAccountsCompared = count;
    assert.throws(() => appendAccountToTrialBalance(current, {
      storeId: 'shop-a', account: account('YYY'), debit: 5,
      credit: 0, matched: true,
    }, AuditFailure), (error) => error.code === 'failed-precondition');
  });

  it('reports changed financial source without a balanced verdict', () => {
    const current = state();
    current.status = 'source_changed';
    const summary = trialBalanceSummary(current);
    assert.equal(summary.verdict, 'source_changed');
    assert.equal(summary.complete, false);
    assert.equal(summary.certified, false);
  });
});

'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');
const {
  MAX_AUDIT_DOCS_PER_COLLECTION,
  isJournalLinePath,
  auditInteger,
  auditSum,
} = require('./accounting/audit_integrity');

describe('accounting audit safe parsing and data selection', () => {
  it('selects only the true nested journal_lines path of this store', () => {
    const ref = (path) => ({path});
    assert.equal(isJournalLinePath(
      ref('stores/shop-a/journal_entries/journal-1/lines/line-1'), 'shop-a',
    ), true);
    for (const path of [
      'stores/shop-a/sales/sale-1/lines/line-1',
      'stores/shop-a/purchases/purchase-1/lines/line-1',
      'stores/shop-b/journal_entries/journal-1/lines/line-1',
      'stores/shop-a/journal_entries/journal-1/lines/line-1/subitems/extra',
      'journal_entries/journal-1/lines/line-1',
    ]) {
      assert.equal(isJournalLinePath(ref(path), 'shop-a'), false, path);
    }
  });

  it('flags strings, fractions, missing values and unsafe integers', () => {
    const problems = [];
    for (const value of ['100', 1.5, null, undefined,
      Number.MAX_SAFE_INTEGER + 1, -1]) {
      assert.equal(auditInteger(
        value, {scope: 'accountBalance', referenceId: '1110'},
        (problem) => problems.push(problem),
      ), 0);
    }
    assert.equal(problems.length, 6);
    assert.equal(problems.every((p) => p.code === 'AUDIT_INVALID_INTEGER'), true);
    assert.equal(auditInteger(-25, {scope: 'inventory', referenceId: 'stock-a'},
      () => { throw Error('Negative stock adjustment should be permitted'); },
      {allowNegative: true}), -25);
  });

  it('flags arithmetic overflow rather than comparing imprecise sums', () => {
    const problems = [];
    assert.equal(auditSum(
      Number.MAX_SAFE_INTEGER, 1,
      {scope: 'journal', referenceId: 'journal-a'},
      (p) => problems.push(p),
    ), 0);
    assert.equal(problems[0].code, 'AUDIT_INTEGER_OVERFLOW');
    assert.equal(auditSum(500, -200, {scope: 'inventory', referenceId: 'A'},
      () => { throw Error('Should not fail'); }), 300);
  });

  it('limits each audited collection to an explicit finite bound', () => {
    assert.equal(Number.isSafeInteger(MAX_AUDIT_DOCS_PER_COLLECTION), true);
    assert.equal(MAX_AUDIT_DOCS_PER_COLLECTION > 0, true);
    assert.equal(MAX_AUDIT_DOCS_PER_COLLECTION <= 10000, true);
  });
});

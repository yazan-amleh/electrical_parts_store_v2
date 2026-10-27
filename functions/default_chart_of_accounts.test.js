'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { getDefaultChart, validateDefaultChart, buildDefaultChartDocuments } =
  require('./default_chart_of_accounts');

const sectionType = {
  currentAsset: 'asset',
  nonCurrentAsset: 'asset',
  currentLiability: 'liability',
  nonCurrentLiability: 'liability',
  equity: 'equity',
  revenue: 'revenue',
  otherIncome: 'revenue',
  costOfSales: 'expense',
  operatingExpense: 'expense',
  otherExpense: 'expense',
};

// Gate against drifting away from the source V2 Flutter default chart.
// The parser is scoped to its explicit _header/_posting declarations.
function readFlutterChart() {
  const dart = fs.readFileSync(path.join(
    __dirname, '..', 'lib', 'features', 'accounting', 'domain',
    'services', 'default_chart_of_accounts.dart',
  ), 'utf8');
  const entries = [];
  const declarations = /      (_header|_posting)\(\n([\s\S]*?)\n      \),/g;
  for (const match of dart.matchAll(declarations)) {
    const [, kind, block] = match;
    const str = (key) =>
      block.match(new RegExp('\\b' + key + ":\\s*'([^']*)'"))?.[1] ?? null;
    const enumName = (key) =>
      block.match(new RegExp('\\b' + key + ':\\s*(?:\\w+\\.)?(\\w+),'))?.[1] ?? null;
    const section = enumName('section');
    const type = sectionType[section];
    if (!type) throw new Error('Unknown Dart statement section ' + section);
    entries.push({
      id: str('id'),
      code: str('code'),
      name: str('name'),
      type,
      normalSide: enumName('normalSide') || (type === 'asset' || type === 'expense' ? 'debit' : 'credit'),
      controlType: enumName('controlType') || 'none',
      statementSection: section,
      parentId: str('parentId'),
      currency: 'ILS',
      isHeader: kind === '_header',
      sortOrder: Number(block.match(/\bsortOrder:\s*(\d+)/)?.[1]),
      isActive: true,
    });
  }
  return entries;
}

describe('V2 default chart contract', () => {
  it('matches the canonical Flutter chart account-for-account', () => {
    const chart = getDefaultChart();
    assert.equal(chart.version, 2);
    assert.equal(chart.accounts.length, 27);
    assert.deepEqual(chart.accounts, readFlutterChart());
  });

  it('generates the same tenant-scoped, non-posted chart with no balances', () => {
    const accounts = buildDefaultChartDocuments('store-a');
    assert.equal(accounts.length, 27);
    assert.equal(accounts.every((a) => a.storeId === 'store-a'), true);
    assert.equal(accounts.every((a) => a.currency === 'ILS'), true);
    assert.equal(accounts.some((a) => 'balanceMinorUnits' in a), false);
    assert.equal(accounts.some((a) => a.id === '1110' && a.controlType === 'cashBox'), true);
    assert.equal(accounts.some((a) => a.id === '1150' && a.controlType === 'inventory'), true);
    assert.equal(accounts.some((a) => a.id === '1140' && a.controlType === 'customerReceivable'), true);
    assert.equal(accounts.some((a) => a.id === '2110' && a.controlType === 'supplierPayable'), true);
    assert.equal(accounts.some((a) => a.id === '3400' &&
      a.type === 'equity' && a.normalSide === 'credit'), true);
    assert.equal(accounts.some((a) => a.id === '4200' &&
      a.type === 'revenue' && a.normalSide === 'debit'), true);
  });

  it('fails closed for duplicates, dangling parents and mismatched currencies', () => {
    const chart = getDefaultChart();
    assert.throws(
      () => validateDefaultChart({ ...chart, accounts: [...chart.accounts, chart.accounts[0]] }),
      /Duplicate/,
    );
    const brokenParent = chart.accounts.map((a) => ({ ...a }));
    brokenParent[1].parentId = 'missing';
    assert.throws(() => validateDefaultChart({ ...chart, accounts: brokenParent }), /Invalid parent/);
    const brokenCurrency = chart.accounts.map((a) => ({ ...a }));
    brokenCurrency[1].currency = 'USD';
    assert.throws(() => validateDefaultChart({ ...chart, accounts: brokenCurrency }), /Invalid default/);
  });
});

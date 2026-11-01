'use strict';

const chart = require('./default_chart_of_accounts.json');

/**
 * Chart template is reviewed against the Flutter DefaultChartOfAccounts by
 * default_chart_of_accounts.test.js. No ledger, opening journal or balance
 * mutation is allowed during store provisioning.
 */
function getDefaultChart() {
  validateDefaultChart(chart);
  return chart;
}

function validateDefaultChart(manifest) {
  if (!manifest || manifest.version !== 3 || manifest.baseCurrency !== 'ILS' ||
      !Array.isArray(manifest.accounts) || manifest.accounts.length === 0) {
    throw new Error('Invalid default accounting chart manifest.');
  }

  const ids = new Set();
  const codes = new Set();
  const controls = new Set();
  for (const account of manifest.accounts) {
    if (!account || !/^[0-9]{4}$/.test(account.id) ||
        account.code !== account.id || !account.name ||
        !Number.isInteger(account.sortOrder) ||
        !['asset', 'liability', 'equity', 'revenue', 'expense'].includes(account.type) ||
        !['debit', 'credit'].includes(account.normalSide) ||
        !account.statementSection || !account.controlType ||
        account.currency !== manifest.baseCurrency ||
        typeof account.isHeader !== 'boolean' || account.isActive !== true) {
      throw new Error('Invalid default accounting chart account.');
    }
    if (ids.has(account.id) || codes.has(account.code)) {
      throw new Error('Duplicate chart account ID or code.');
    }
    ids.add(account.id);
    codes.add(account.code);
    if (account.isHeader && account.controlType !== 'none') {
      throw new Error('Header account cannot be a control account.');
    }
    if (account.controlType !== 'none') {
      if (controls.has(account.controlType)) {
        throw new Error('Duplicate chart control type: ' + account.controlType);
      }
      controls.add(account.controlType);
    }
  }

  for (const account of manifest.accounts) {
    if (account.parentId !== null) {
      const parent = manifest.accounts.find((item) => item.id === account.parentId);
      if (!parent || !parent.isHeader || parent.id === account.id) {
        throw new Error('Invalid parent in default chart: ' + account.id);
      }
      if (parent.type !== account.type) {
        throw new Error('Account and parent type mismatch: ' + account.id);
      }
    }
  }
}

function buildDefaultChartDocuments(storeId) {
  if (typeof storeId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(storeId)) {
    throw new Error('Invalid store ID when seeding chart.');
  }
  return getDefaultChart().accounts.map((account) => ({
    ...account,
    storeId,
  }));
}

module.exports = {
  buildDefaultChartDocuments,
  getDefaultChart,
  validateDefaultChart,
};

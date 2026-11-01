'use strict';

const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const {describe, it} = require('node:test');

const index = readFileSync(join(__dirname, 'index.js'), 'utf8');
const chart = readFileSync(
  join(__dirname, 'accounting/chart_mutation.js'), 'utf8');

const guardedFinancialPaths = [
  'postInventoryMovementInTransaction',
  'postJournalEntryInTransaction',
  'postAccountTransferInTransaction',
  'postExpenseInTransaction',
  'postPartyPaymentInTransaction',
  'postPurchaseInTransaction',
  'postSaleInTransaction',
  'settleChequeInTransaction',
  'deliverRepairInTransaction',
  'postRepairAdvanceInTransaction',
  'postRepairPaymentInTransaction',
  'receivePurchaseOrderInTransaction',
  'createRepairInTransaction',
  'updateRepairInTransaction',
];

function bodyOfFunction(text, name) {
  const header = 'async function ' + name + '(';
  const start = text.indexOf(header);
  assert.notEqual(start, -1, 'Missing guarded source path: ' + name);
  const end = text.indexOf('\nasync function ', start + header.length);
  return text.slice(start, end === -1 ? undefined : end);
}

describe('accounting source-mutation close contract', () => {
  it('requires all instrumented journal and inventory writers to check the lock', () => {
    for (const name of guardedFinancialPaths) {
      const body = bodyOfFunction(index, name);
      const guard = body.indexOf('await assertAccountingWritesOpen(');
      assert.notEqual(guard, -1, 'Missing freeze guard in ' + name);
      const firstWrite = body.search(/\btransaction\.(set|update|create|delete)\(/);
      assert.ok(firstWrite < 0 || guard < firstWrite,
        'Financial write precedes freeze guard in ' + name);
    }
    assert.ok(chart.includes('await assertAccountingWritesOpen(tx, store, HttpsError)'),
      'Chart mutation must be protected by the same close control');
  });

  it('prevents removing UTC business-date guards on posted transactions', () => {
    const dated = [
      'postInventoryMovementInTransaction',
      'postJournalEntryInTransaction',
      'postAccountTransferInTransaction',
      'postExpenseInTransaction',
      'postPartyPaymentInTransaction',
      'postPurchaseInTransaction',
      'postSaleInTransaction',
      'settleChequeInTransaction',
      'deliverRepairInTransaction',
      'postRepairAdvanceInTransaction',
      'postRepairPaymentInTransaction',
      'receivePurchaseOrderInTransaction',
    ];
    for (const name of dated) {
      const body = bodyOfFunction(index, name);
      const firstGuard = body.indexOf('await assertAccountingWritesOpen(');
      assert.ok(firstGuard > -1 &&
        body.slice(firstGuard, firstGuard + 240)
          .includes('postedAt') ||
        firstGuard > -1 &&
        body.slice(firstGuard, firstGuard + 240)
          .includes('occurredAt'),
      'Missing business date in close check: ' + name);
    }
  });

  it('does not let the rules expose financial closing documents to clients', () => {
    const rules = readFileSync(join(__dirname, '../firestore.rules'), 'utf8');
    for (const collection of [
      'accounting_period_control',
      'accounting_close_events',
      'accounting_posting_epochs',
    ]) {
      assert.match(rules, new RegExp(
        'match /' + collection +
        '/\\{[a-zA-Z]+\\} \\{[\\s\\S]*?allow read, write: if false;',
      ));
    }
  });
});

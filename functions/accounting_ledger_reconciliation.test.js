'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'reconciliation-owner';
const request = (data, uid = UID) => ({
  data,
  auth: uid ? {uid, token: {uid}} : null,
});

async function seed(storeId) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId, currency: 'ILS'});
  batch.set(store.collection('members').doc(UID), {
    storeId, userId: UID, role: 'owner', isActive: true,
  });
  for (const id of ['1110', '3110']) {
    batch.set(store.collection('accounts').doc(id), {
      storeId, id, isHeader: false, currency: 'ILS',
    });
  }
  batch.set(store.collection('journal_entries').doc('manual-1'), {
    storeId, status: 'posted', currency: 'ILS',
    totalDebitMinorUnits: 200, totalCreditMinorUnits: 200,
  });
  batch.set(store.collection('journal_entries').doc('manual-1')
    .collection('lines').doc('debit'), {
    storeId, entryId: 'manual-1', currency: 'ILS',
    accountId: '1110', debitMinorUnits: 200, creditMinorUnits: 0,
  });
  batch.set(store.collection('journal_entries').doc('manual-1')
    .collection('lines').doc('credit'), {
    storeId, entryId: 'manual-1', currency: 'ILS',
    accountId: '3110', debitMinorUnits: 0, creditMinorUnits: 200,
  });
  batch.set(store.collection('account_balances').doc('1110'), {
    storeId, accountId: '1110', currency: 'ILS',
    debitMinorUnits: 200, creditMinorUnits: 0, balanceMinorUnits: 200,
  });
  batch.set(store.collection('account_balances').doc('3110'), {
    storeId, accountId: '3110', currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 200, balanceMinorUnits: -200,
  });
  await batch.commit();
  return store;
}

async function start(storeId) {
  return functions.startAccountingLedgerReconciliation.run(
    request({storeId}),
  );
}
async function advance(storeId, runId) {
  return functions.advanceAccountingLedgerReconciliation.run(
    request({storeId, runId}),
  );
}
async function finish(storeId, runId, max = 15) {
  let result;
  for (let i = 0; i < max; i++) {
    result = await advance(storeId, runId);
    if (result.status === 'reconciliation_complete') return result;
  }
  throw new Error('Audit did not complete within the fixture limit');
}

describe('ledger reconciliation checkpointed per account', () => {
  after(async () => {await admin.app().delete();});

  it('reconciles balanced journal lines to both GL balance projections', async () => {
    const store = await seed('ledger-match-a');
    const run = await start(store.id);
    assert.equal(run.certified, false);
    assert.equal(run.scope, 'known_chart_accounts_indexed_ledger_lines');
    const result = await finish(store.id, run.runId);
    assert.equal(result.accountsCompared, 2);
    assert.equal(result.mismatchedAccounts, 0);
    assert.equal(result.consistency, 'non_atomic');
    assert.equal(result.certified, false);
    assert.equal(result.accountingCutoffApplied, false);
    const accountResult = (await store.collection('accounting_ledger_runs')
      .doc(run.runId).collection('account_results').doc('1110').get()).data();
    assert.equal(accountResult.matched, true);
    assert.equal(accountResult.debitMinorUnits, 200);
    assert.equal(accountResult.creditMinorUnits, 0);
    assert.equal(accountResult.issueCount, 0);
    const again = await advance(store.id, run.runId);
    assert.deepEqual(again, result);
    await db.recursiveDelete(store);
  });

  it('reports stored debit or net mismatches even with valid journal lines', async () => {
    const store = await seed('ledger-projection-tamper');
    await store.collection('account_balances').doc('1110')
      .update({balanceMinorUnits: 199});
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.mismatchedAccounts, 1);
    const document = (await store.collection('accounting_ledger_runs')
      .doc(run.runId).collection('account_results').doc('1110').get()).data();
    assert.equal(document.matched, false);
    assert.equal(document.issueSamples.some(
      (i) => i.code === 'LEDGER_PROJECTION_TOTAL_MISMATCH'), true);
    assert.equal((await store.collection('account_balances').doc('1110')
      .get()).data().balanceMinorUnits, 199);
    await db.recursiveDelete(store);
  });

  it('does not count invoice lines and detects invalid ledger money and currency', async () => {
    const store = await seed('ledger-invoice-decoy');
    await store.collection('sales').doc('invoice-1')
      .collection('lines').doc('line-1').set({
        storeId: store.id, accountId: '1110', currency: 'ILS',
        debitMinorUnits: 999999, creditMinorUnits: 0,
      });
    await store.collection('journal_entries').doc('manual-1')
      .collection('lines').doc('debit').update({
        debitMinorUnits: '200', currency: 'USD',
      });
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.mismatchedAccounts, 1);
    assert.equal(result.indexedDocumentsScanned, 3);
    const evidence = (await store.collection('accounting_ledger_runs')
      .doc(run.runId).collection('account_results').doc('1110').get()).data();
    assert.equal(evidence.debitMinorUnits, 0);
    assert.equal(evidence.issueSamples.some(
      (i) => i.code === 'LEDGER_LINE_CURRENCY_MISMATCH'), true);
    assert.equal(evidence.issueSamples.some(
      (i) => i.code === 'LEDGER_LINE_MONEY_INVALID'), true);
    await db.recursiveDelete(store);
  });

  it('resumes one account over multiple pages with concurrent advances', async () => {
    const store = await seed('ledger-paginated-a');
    const balance = store.collection('account_balances').doc('1110');
    const first = store.collection('journal_entries').doc('manual-1')
      .collection('lines').doc('debit');
    await first.delete();
    let batch = db.batch();
    for (let i = 0; i < 95; i++) {
      batch.set(store.collection('journal_entries').doc('manual-1')
        .collection('lines').doc('part-' + String(i).padStart(3, '0')), {
        storeId: store.id, entryId: 'manual-1', accountId: '1110',
        currency: 'ILS', debitMinorUnits: 2, creditMinorUnits: 0,
      });
    }
    batch.update(balance, {
      debitMinorUnits: 190, balanceMinorUnits: 190,
    });
    await batch.commit();
    const started = await start(store.id);
    const [a, b] = await Promise.all([
      advance(store.id, started.runId),
      advance(store.id, started.runId),
    ]);
    assert.equal(a.certified, false);
    assert.equal(b.certified, false);
    const checkpoint = (await store.collection('accounting_ledger_runs')
      .doc(started.runId).get()).data();
    assert.equal(checkpoint.linesScanned, 80);
    assert.equal(checkpoint.activeAccountId, '1110');
    assert.equal(checkpoint.runningDebit, 160);
    const finished = await finish(store.id, started.runId);
    assert.equal(finished.accountsCompared, 2);
    assert.equal(finished.mismatchedAccounts, 0);
    const evidence = (await store.collection('accounting_ledger_runs')
      .doc(started.runId).collection('account_results').doc('1110').get()).data();
    assert.equal(evidence.indexedDocumentsScanned, 95);
    assert.equal(evidence.debitMinorUnits, 190);
    await db.recursiveDelete(store);
  });

  it('rejects missing membership, revoked access and forged checkpoint state', async () => {
    const store = await seed('ledger-auth-a');
    await assert.rejects(
      functions.startAccountingLedgerReconciliation.run(
        request({storeId: store.id}, null),
      ), (error) => error.code === 'unauthenticated',
    );
    await assert.rejects(
      functions.startAccountingLedgerReconciliation.run(
        request({storeId: store.id}, 'stranger'),
      ), (error) => error.code === 'permission-denied',
    );
    const run = await start(store.id);
    await assert.rejects(
      functions.advanceAccountingLedgerReconciliation.run(
        request({storeId: store.id, runId: run.runId}, 'stranger'),
      ), (error) => error.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(
      advance(store.id, run.runId),
      (error) => error.code === 'permission-denied',
    );
    await store.collection('members').doc(UID).update({isActive: true});
    await store.collection('accounting_ledger_runs').doc(run.runId)
      .update({activeAccountId: '1110', lineCursorPath: 'bad-cursor'});
    await assert.rejects(
      advance(store.id, run.runId),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('account_balances').doc('1110')
      .get()).data().balanceMinorUnits, 200);
    await db.recursiveDelete(store);
  });
});

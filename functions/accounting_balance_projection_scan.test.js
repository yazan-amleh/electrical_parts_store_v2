'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'reverse-balance-auditor';
const req = (storeId, runId = null, uid = UID) => ({
  auth: uid ? {uid, token: {uid}} : null,
  data: runId ? {storeId, runId} : {storeId},
});

async function seed(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId: id, currency: 'ILS'});
  batch.set(store.collection('members').doc(UID), {
    storeId: id, userId: UID, role: 'accountant', isActive: true,
  });
  for (const accountId of ['1110', '3110']) {
    batch.set(store.collection('accounts').doc(accountId), {
      id: accountId, storeId: id, isHeader: false, currency: 'ILS',
    });
  }
  batch.set(store.collection('account_balances').doc('1110'), {
    accountId: '1110', storeId: id, currency: 'ILS',
    debitMinorUnits: 100, creditMinorUnits: 0, balanceMinorUnits: 100,
  });
  batch.set(store.collection('account_balances').doc('3110'), {
    accountId: '3110', storeId: id, currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 100, balanceMinorUnits: -100,
  });
  await batch.commit();
  return store;
}
const start = (storeId, uid = UID) =>
  functions.startAccountingBalanceProjectionScan.run(req(storeId, null, uid));
const advance = (storeId, runId, uid = UID) =>
  functions.advanceAccountingBalanceProjectionScan.run(
    req(storeId, runId, uid),
  );
async function finish(storeId, runId, max = 20) {
  let next;
  for (let i = 0; i < max; i++) {
    next = await advance(storeId, runId);
    if (next.status !== 'running') return next;
  }
  throw new Error('Reverse balance scan exceeded test step limit');
}

describe('reverse GL account balance census', () => {
  after(async () => {await admin.app().delete();});

  it('accepts valid projections, never changes financial records', async () => {
    const store = await seed('reverse-valid-projections');
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.status, 'enumeration_complete');
    assert.equal(result.certified, false);
    assert.equal(result.consistency, 'non_atomic');
    assert.equal(result.accountingCutoffApplied, false);
    assert.equal(result.balancesChecked, 2);
    assert.equal(result.invalidBalanceDocuments, 0);
    assert.equal(result.missingChartAccounts, 0);
    assert.deepEqual(result.balanceTotalsByCurrency.ILS, {
      balanceDocuments: 2,
      debitTurnoverMinorUnits: 100,
      creditTurnoverMinorUnits: 100,
      debitClosingMinorUnits: 100,
      creditClosingMinorUnits: 100,
    });
    assert.deepEqual(await advance(store.id, run.runId), result);
    assert.equal((await store.collection('account_balances').doc('1110')
      .get()).data().balanceMinorUnits, 100);
    await db.recursiveDelete(store);
  });

  it('discovers orphan balance with no corresponding account in chart', async () => {
    const store = await seed('reverse-missing-chart-account');
    await store.collection('account_balances').doc('9999').set({
      accountId: '9999', storeId: store.id, currency: 'ILS',
      debitMinorUnits: 55, creditMinorUnits: 0, balanceMinorUnits: 55,
    });
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.balancesChecked, 3);
    assert.equal(result.missingChartAccounts, 1);
    assert.equal(result.invalidBalanceDocuments, 1);
    assert.equal(result.balanceTotalsByCurrency.ILS.balanceDocuments, 2);
    assert.equal(result.balanceTotalsByCurrency.ILS.debitTurnoverMinorUnits, 100);
    assert.equal(result.issueSamples.some(
      (i) => i.code === 'BALANCE_CHART_ACCOUNT_MISSING' &&
        i.referenceId.endsWith('/account_balances/9999')), true);
    await db.recursiveDelete(store);
  });

  it('flags non-posting headers, invalid money, and wrong identity/currency', async () => {
    const store = await seed('reverse-bad-projections');
    await store.collection('accounts').doc('1000').set({
      id: '1000', storeId: store.id, currency: 'ILS', isHeader: true,
    });
    await store.collection('account_balances').doc('1000').set({
      accountId: '1000', storeId: store.id, currency: 'ILS',
      debitMinorUnits: 0, creditMinorUnits: 0, balanceMinorUnits: 0,
    });
    await store.collection('account_balances').doc('1110').update({
      currency: 'USD', balanceMinorUnits: 99, accountId: '3110',
    });
    await store.collection('account_balances').doc('3110').update({
      debitMinorUnits: 'broken',
    });
    const run = await start(store.id);
    const result = await finish(store.id, run.runId);
    assert.equal(result.invalidBalanceDocuments, 3);
    assert.equal(result.headerAccountsWithBalance, 1);
    assert.equal(result.currencyMismatchBalances, 1);
    assert.equal(result.invalidMoneyBalances, 2);
    assert.deepEqual(result.balanceTotalsByCurrency, {});
    const codes = result.issueSamples.map((i) => i.code);
    assert.equal(codes.includes('BALANCE_ON_NON_POSTING_HEADER'), true);
    assert.equal(codes.includes('BALANCE_MONEY_OR_NET_INVALID'), true);
    assert.equal(codes.includes('BALANCE_EMBEDDED_IDENTITY_INVALID'), true);
    await db.recursiveDelete(store);
  });

  it('paginates 95 balances safely even with concurrent advances', async () => {
    const store = await seed('reverse-balance-pagination');
    const batch = db.batch();
    for (let i = 0; i < 95; i++) {
      const id = 'extra-' + String(i).padStart(3, '0');
      batch.set(store.collection('accounts').doc(id), {
        storeId: store.id, id, currency: 'ILS', isHeader: false,
      });
      batch.set(store.collection('account_balances').doc(id), {
        storeId: store.id, accountId: id, currency: 'ILS',
        debitMinorUnits: 0, creditMinorUnits: 0, balanceMinorUnits: 0,
      });
    }
    await batch.commit();
    const run = await start(store.id);
    await Promise.all([
      advance(store.id, run.runId), advance(store.id, run.runId),
    ]);
    const mid = (await store.collection('accounting_balance_path_runs')
      .doc(run.runId).get()).data();
    assert.equal(mid.balancesChecked, 80);
    const end = await finish(store.id, run.runId);
    assert.equal(end.balancesChecked, 97);
    assert.equal(end.invalidBalanceDocuments, 0);
    assert.equal(end.pagesChecked, 3);
    assert.equal(end.balanceTotalsByCurrency.ILS.balanceDocuments, 97);
    assert.equal(end.balanceTotalsByCurrency.ILS.debitTurnoverMinorUnits, 100);
    await db.recursiveDelete(store);
  });


  it('aggregates USD independently and never adds it to ILS totals', async () => {
    const store = await seed('reverse-balance-separated-currency');
    await store.collection('accounts').doc('1111').set({
      storeId: store.id, id: '1111', currency: 'USD', isHeader: false,
    });
    await store.collection('account_balances').doc('1111').set({
      storeId: store.id, accountId: '1111', currency: 'USD',
      debitMinorUnits: 9, creditMinorUnits: 4, balanceMinorUnits: 5,
    });
    const run = await start(store.id);
    const completed = await finish(store.id, run.runId);
    assert.equal(completed.invalidBalanceDocuments, 0);
    assert.deepEqual(Object.keys(completed.balanceTotalsByCurrency).sort(),
      ['ILS', 'USD']);
    assert.equal(completed.balanceTotalsByCurrency.USD.debitTurnoverMinorUnits, 9);
    assert.equal(completed.balanceTotalsByCurrency.USD.creditTurnoverMinorUnits, 4);
    assert.equal(completed.balanceTotalsByCurrency.USD.debitClosingMinorUnits, 5);
    assert.equal(completed.balanceTotalsByCurrency.ILS.debitTurnoverMinorUnits, 100);
    await db.recursiveDelete(store);
  });

  it('rejects tampered persisted currency totals, not silent zero aggregation', async () => {
    const store = await seed('reverse-balance-corrupt-totals');
    const run = await start(store.id);
    await store.collection('accounting_balance_path_runs').doc(run.runId)
      .update({balanceTotalsByCurrency: {ILS: {
        balanceDocuments: 1, debitTurnoverMinorUnits: 50,
      }}});
    await assert.rejects(advance(store.id, run.runId),
      (error) => error.code === 'failed-precondition');
    assert.equal((await store.collection('account_balances')
      .doc('1110').get()).data().balanceMinorUnits, 100);
    await db.recursiveDelete(store);
  });

  it('fails closed on invalid checkpoint and revoked or foreign access', async () => {
    const store = await seed('reverse-balance-security');
    await assert.rejects(start(store.id, null),
      (e) => e.code === 'unauthenticated');
    await assert.rejects(start(store.id, 'outsider'),
      (e) => e.code === 'permission-denied');
    const run = await start(store.id);
    await assert.rejects(advance(store.id, run.runId, 'outsider'),
      (e) => e.code === 'permission-denied');
    await store.collection('members').doc(UID).update({isActive: false});
    await assert.rejects(advance(store.id, run.runId),
      (e) => e.code === 'permission-denied');
    await store.collection('members').doc(UID).update({isActive: true});
    await store.collection('accounting_balance_path_runs')
      .doc(run.runId).update({cursorId: 'bad/path'});
    await assert.rejects(advance(store.id, run.runId),
      (e) => e.code === 'failed-precondition');
    assert.equal((await store.collection('account_balances')
      .doc('1110').get()).data().balanceMinorUnits, 100);
    await db.recursiveDelete(store);
  });
});

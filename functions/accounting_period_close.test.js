'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const api = require('./index');

const db = admin.firestore();
const OWNER = 'close-owner';
const CLERK = 'close-accountant';
const call = (fn, data, uid = OWNER) => fn.run({
  data, auth: uid ? {uid, token: {uid}} : null,
});
async function fixture(id) {
  const store = db.collection('stores').doc(id);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {storeId: id, currency: 'ILS', ownerId: OWNER});
  for (const [uid, role] of [[OWNER, 'owner'], [CLERK, 'accountant']]) {
    batch.set(store.collection('members').doc(uid), {
      storeId: id, userId: uid, role, isActive: true,
    });
  }
  for (const [accountId, type, debit, credit] of [
    ['1110', 'asset', 77, 0],
    ['3110', 'equity', 0, 77],
  ]) {
    batch.set(store.collection('accounts').doc(accountId), {
      storeId: id, id: accountId, code: accountId, name: accountId,
      currency: 'ILS', isHeader: false, isActive: true,
      type, normalSide: type === 'asset' ? 'debit' : 'credit',
    });
    batch.set(store.collection('account_balances').doc(accountId), {
      storeId: id, accountId, currency: 'ILS', debitMinorUnits: debit,
      creditMinorUnits: credit, balanceMinorUnits: debit - credit,
    });
  }
  batch.set(store.collection('journal_entries').doc('original'), {
    storeId: id, status: 'posted', currency: 'ILS',
    totalDebitMinorUnits: 77, totalCreditMinorUnits: 77,
  });
  for (const [lineId, accountId, debit, credit] of [
    ['debit', '1110', 77, 0],
    ['credit', '3110', 0, 77],
  ]) {
    batch.set(store.collection('journal_entries').doc('original')
      .collection('lines').doc(lineId), {
      storeId: id, entryId: 'original', accountId,
      currency: 'ILS', debitMinorUnits: debit, creditMinorUnits: credit,
    });
  }
  batch.set(store.collection('products').doc('stock'), {
    storeId: id, id: 'stock', isService: false, currency: 'ILS',
    quantityOnHandMilliUnits: 0, inventoryValueMinorUnits: 0,
    purchasePriceMinorUnits: 15,
  });
  await batch.commit();
  return store;
}
function manual(storeId, id = 'new-after-close') {
  return {
    storeId, entry: {
      id, idempotencyKey: id+'-key', sourceType: 'manual',
      postedAt: '2026-10-24T10:00:00.000Z', currency: 'ILS',
      description: 'Close protection test',
      lines: [
        {id: 'd', accountId: '1110',
          debitMinorUnits: 3, creditMinorUnits: 0},
        {id: 'c', accountId: '3110',
          debitMinorUnits: 0, creditMinorUnits: 3},
      ],
    },
  };
}
function inventory(storeId, id = 'stock-change-1') {
  return {storeId, movement: {
    id, idempotencyKey: id+'-key', productId: 'stock',
    type: 'openingBalance', currency: 'ILS',
    quantityDeltaMilliUnits: 1000, unitCostMinorUnits: 15,
    totalCostMinorUnits: 15, occurredAt: '2026-10-24T10:00:00.000Z',
    sourceType: 'manual',
  }};
}
async function run(start, advance, storeId, doneStatus) {
  const started = await call(start, {storeId});
  for (let i = 0; i < 10; i++) {
    const result = await call(advance, {storeId, runId: started.runId});
    if (result.status !== 'running') {
      assert.equal(result.status, doneStatus);
      return result.runId;
    }
  }
  throw new Error('Failed to complete close fixture audit');
}
async function audits(storeId) {
  const ledgerRunId = await run(
    api.startAccountingLedgerReconciliation,
    api.advanceAccountingLedgerReconciliation,
    storeId, 'reconciliation_complete');
  const journalRunId = await run(
    api.startAccountingJournalReconciliation,
    api.advanceAccountingJournalReconciliation,
    storeId, 'reconciliation_complete');
  const orphanRunId = await run(
    api.startAccountingOrphanPathScan,
    api.advanceAccountingOrphanPathScan,
    storeId, 'enumeration_complete');
  const balanceRunId = await run(
    api.startAccountingBalanceProjectionScan,
    api.advanceAccountingBalanceProjectionScan,
    storeId, 'enumeration_complete');
  return {ledgerRunId, journalRunId, orphanRunId, balanceRunId};
}
describe('controlled accounting freeze is not a historical certification', () => {
  after(async () => {await admin.app().delete();});
  it('blocks journal, inventory and chart writes immediately upon freeze', async () => {
    const store = await fixture('period-freeze-blocks-writes');
    const begun = await call(api.beginAccountingClose, {storeId: store.id, throughDate: '2026-10-23'});
    assert.equal(begun.status, 'locked');
    assert.equal(begun.certified, false);
    await assert.rejects(
      call(api.postJournalEntry, manual(store.id)),
      (e) => e.code === 'failed-precondition');
    await assert.rejects(
      call(api.postInventoryMovement, inventory(store.id)),
      (e) => e.code === 'failed-precondition');
    await assert.rejects(
      call(api.mutateChartAccount, {
        storeId: store.id, operation: 'update',
        account: {id: '1110', name: 'Not allowed while locked'},
      }),
      (e) => e.code === 'failed-precondition');
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    assert.equal((await store.collection('inventory_movements').get()).size, 0);
    assert.equal((await store.collection('account_balances')
      .doc('1110').get()).data().balanceMinorUnits, 77);
    const reopened = await call(api.reopenAccountingClose, {
      storeId: store.id, reason: 'Review completed and entries may continue.',
    });
    assert.equal(reopened.status, 'open');
    const posted = await call(api.postJournalEntry,
      manual(store.id, 'posted-after-unfreeze'));
    assert.equal(posted.status, 'posted');
    await db.recursiveDelete(store);
  });

  it('finalizes only clean four-scan evidence gathered after freeze', async () => {
    const store = await fixture('period-freeze-finalization');
    await call(api.beginAccountingClose, {storeId: store.id, throughDate: '2026-10-23'});
    const runs = await audits(store.id);
    const closed = await call(api.finalizeAccountingClose,
      {storeId: store.id, ...runs});
    assert.equal(closed.status, 'closed');
    assert.equal(closed.certified, false);
    assert.equal(closed.immutableHistoricalSnapshot, false);
    const report = await call(api.getUnifiedAccountingAuditReport,
      {storeId: store.id, ...runs});
    assert.equal(report.verdict, 'observed_aggregates_agree_non_atomic');
    await assert.rejects(
      call(api.postJournalEntry, manual(store.id)),
      (e) => e.code === 'failed-precondition');
    await assert.rejects(
      call(api.beginAccountingClose, {storeId: store.id, throughDate: '2026-10-23'}),
      (e) => e.code === 'failed-precondition');
    const control = (await store.collection('accounting_period_control')
      .doc('current').get()).data();
    assert.equal(control.status, 'closed');
    assert.equal(control.evidence.ledgerRunId, runs.ledgerRunId);
    await db.recursiveDelete(store);
  });

  it('rejects finalization with incomplete or changed evidence', async () => {
    const store = await fixture('period-close-no-false-completion');
    await call(api.beginAccountingClose, {storeId: store.id, throughDate: '2026-10-23'});
    const result = await call(api.startAccountingLedgerReconciliation,
      {storeId: store.id});
    await assert.rejects(call(api.finalizeAccountingClose, {
      storeId: store.id, ledgerRunId: result.runId,
      journalRunId: 'missing', orphanRunId: 'missing',
      balanceRunId: 'missing',
    }), (e) => e.code === 'not-found');
    assert.equal((await store.collection('accounting_period_control')
      .doc('current').get()).data().status, 'locked');
    await db.recursiveDelete(store);
  });


  it('preserves the closed-through date after reopen and rejects backdated journals', async () => {
    const store = await fixture('period-close-immutable-business-date');
    await call(api.beginAccountingClose, {
      storeId: store.id, throughDate: '2026-10-23',
    });
    const runs = await audits(store.id);
    const closed = await call(api.finalizeAccountingClose,
      {storeId: store.id, ...runs});
    assert.equal(closed.closedThroughDate, '2026-10-23');
    const reopened = await call(api.reopenAccountingClose, {
      storeId: store.id,
      reason: 'Prior period approved; future period operations resume.',
    });
    assert.equal(reopened.closedThroughDate, '2026-10-23');
    const backdated = manual(store.id, 'backdated-not-allowed');
    backdated.entry.postedAt = '2026-10-23T23:59:59.000Z';
    await assert.rejects(call(api.postJournalEntry, backdated),
      (e) => e.code === 'failed-precondition');
    const after = await call(api.postJournalEntry,
      manual(store.id, 'future-period-allowed'));
    assert.equal(after.status, 'posted');
    const control = (await store.collection('accounting_period_control')
      .doc('current').get()).data();
    assert.equal(control.closedThroughDate, '2026-10-23');
    await assert.rejects(call(api.beginAccountingClose, {
      storeId: store.id, throughDate: '2026-10-22',
    }), (e) => e.code === 'failed-precondition');
    await db.recursiveDelete(store);
  });

  it('rejects malformed Gregorian close dates before writing lock state', async () => {
    const store = await fixture('period-close-invalid-calendar-date');
    await assert.rejects(call(api.beginAccountingClose, {
      storeId: store.id, throughDate: '2026-02-30',
    }), (e) => e.code === 'invalid-argument');
    assert.equal((await store.collection('accounting_period_control')
      .get()).empty, true);
    await db.recursiveDelete(store);
  });

  it('requires owner/admin privileges and a detailed reopen reason', async () => {
    const store = await fixture('period-close-role-reopen');
    await assert.rejects(
      call(api.beginAccountingClose, {storeId: store.id}, CLERK),
      (e) => e.code === 'permission-denied');
    await assert.rejects(
      call(api.beginAccountingClose, {storeId: store.id}, null),
      (e) => e.code === 'unauthenticated');
    await call(api.beginAccountingClose, {storeId: store.id, throughDate: '2026-10-23'});
    await assert.rejects(
      call(api.reopenAccountingClose, {
        storeId: store.id, reason: 'short',
      }), (e) => e.code === 'invalid-argument');
    await assert.rejects(
      call(api.reopenAccountingClose, {
        storeId: store.id, reason: 'Unauthorized clerk cannot reopen accounting.',
      }, CLERK), (e) => e.code === 'permission-denied');
    assert.equal((await store.collection('accounting_period_control')
      .doc('current').get()).data().status, 'locked');
    await db.recursiveDelete(store);
  });
});

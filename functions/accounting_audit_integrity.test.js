'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'audit-integrity-accountant';

async function seed(storeId) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  batch.set(ref, {storeId, currency: 'ILS'});
  batch.set(ref.collection('members').doc(UID), {
    storeId, userId: UID, isActive: true, role: 'accountant',
  });
  for (const accountId of ['1110', '3110']) {
    batch.set(ref.collection('accounts').doc(accountId), {
      storeId, id: accountId, currency: 'ILS', name: accountId,
      isHeader: false, isActive: true,
    });
  }
  batch.set(ref.collection('journal_entries').doc('journal-a'), {
    storeId, status: 'posted', sourceType: 'manual', currency: 'ILS',
    totalDebitMinorUnits: 500, totalCreditMinorUnits: 500,
  });
  batch.set(ref.collection('journal_entries').doc('journal-a')
    .collection('lines').doc('debit'), {
    storeId, entryId: 'journal-a', currency: 'ILS',
    accountId: '1110', debitMinorUnits: 500, creditMinorUnits: 0,
  });
  batch.set(ref.collection('journal_entries').doc('journal-a')
    .collection('lines').doc('credit'), {
    storeId, entryId: 'journal-a', currency: 'ILS',
    accountId: '3110', debitMinorUnits: 0, creditMinorUnits: 500,
  });
  batch.set(ref.collection('account_balances').doc('1110'), {
    storeId, accountId: '1110', currency: 'ILS',
    debitMinorUnits: 500, creditMinorUnits: 0, balanceMinorUnits: 500,
  });
  batch.set(ref.collection('account_balances').doc('3110'), {
    storeId, accountId: '3110', currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 500, balanceMinorUnits: -500,
  });
  await batch.commit();
  return ref;
}
async function audit(storeId) {
  return functions.auditAccountingIntegrity.run({
    auth: {uid: UID, token: {uid: UID}},
    data: {storeId},
  });
}

describe('accounting integrity audit reads ledger without mutation', () => {
  after(async () => { await admin.app().delete(); });

  it('ignores invoice lines with the same entry ID and reports true ledger count', async () => {
    const store = await seed('audit-journal-only');
    // A collection group query matches this document too, but it is NOT a GL line.
    await store.collection('sales').doc('invoice-1').collection('lines')
      .doc('line-1').set({
        storeId: store.id, entryId: 'journal-a', currency: 'ILS',
        accountId: '1110', debitMinorUnits: 90000, creditMinorUnits: 0,
      });
    const report = await audit(store.id);
    assert.equal(report.status, 'healthy');
    assert.equal(report.complete, true);
    assert.equal(report.consistency, 'non_atomic');
    assert.equal(report.checked.journalLines, 2);
    assert.equal(report.issueCount, 0);
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    assert.equal((await store.collection('account_balances').doc('1110').get())
      .data().debitMinorUnits, 500);
    await db.recursiveDelete(store);
  });

  it('reports malformed existing journal money instead of masking as zero', async () => {
    const store = await seed('audit-malformed-journal');
    await store.collection('journal_entries').doc('journal-a')
      .collection('lines').doc('debit')
      .update({debitMinorUnits: '500'});
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.complete, true);
    assert.equal(report.issues.some((i) => i.code === 'AUDIT_INVALID_INTEGER'), true);
    await db.recursiveDelete(store);
  });

  it('reports invalid stored GL projection even when expected amounts happen to be zero', async () => {
    const store = await seed('audit-invalid-projection');
    await store.collection('account_balances').doc('1110')
      .update({debitMinorUnits: '500'});
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((i) => i.code === 'AUDIT_INVALID_INTEGER'), true);
    await db.recursiveDelete(store);
  });

  it('identifies tampered party net balance even when debit/credit ledger totals agree', async () => {
    const store = await seed('audit-party-net');
    const batch = db.batch();
    batch.set(store.collection('parties').doc('customer-1'), {
      storeId: store.id, partyType: 'customer', name: 'Customer',
    });
    batch.set(store.collection('party_ledger_entries').doc('movement-a'), {
      storeId: store.id, partyType: 'customer', partyId: 'customer-1',
      currency: 'ILS', debitMinorUnits: 700, creditMinorUnits: 0,
    });
    batch.set(store.collection('party_balances').doc('customer-customer-1'), {
      storeId: store.id, partyType: 'customer', partyId: 'customer-1',
      currency: 'ILS', debitMinorUnits: 700, creditMinorUnits: 0,
      balanceMinorUnits: 600,
    });
    await batch.commit();
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((i) =>
      i.code === 'PARTY_BALANCE_MISMATCH'), true);
    await db.recursiveDelete(store);
  });
});

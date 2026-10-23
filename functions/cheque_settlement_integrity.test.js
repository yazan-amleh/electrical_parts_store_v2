'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const UID = 'cheque-guard-accountant';
const DATE = '2026-10-11T08:00:00.000Z';
const AMOUNT = 4200;

async function seed(storeId, isSupplier = false) {
  const ref = db.collection('stores').doc(storeId);
  await db.recursiveDelete(ref);
  const batch = db.batch();
  const partyType = isSupplier ? 'supplier' : 'customer';
  const partyId = partyType + '-1';
  batch.set(ref, { storeId, currency: 'ILS' });
  batch.set(ref.collection('members').doc(UID), {
    storeId, userId: UID, isActive: true, role: 'accountant',
  });
  for (const [id, type, controlType] of [
    ['1130', 'asset', 'checks'],
    ['2210', 'liability', 'checksPayable'],
    ['1140', 'asset', 'customerReceivable'],
    ['2110', 'liability', 'supplierPayable'],
    ['1121', 'asset', 'bank'],
  ]) {
    batch.set(ref.collection('accounts').doc(id), {
      id, code: id, name: id, storeId, currency: 'ILS', type,
      controlType, isHeader: false, isActive: true,
    });
  }
  const held = isSupplier ? '2210' : '1130';
  batch.set(ref.collection('account_balances').doc(held), {
    storeId, accountId: held, currency: 'ILS',
    debitMinorUnits: isSupplier ? 0 : AMOUNT,
    creditMinorUnits: isSupplier ? AMOUNT : 0,
    balanceMinorUnits: isSupplier ? -AMOUNT : AMOUNT,
  });
  batch.set(ref.collection('party_balances').doc(partyType + '-' + partyId), {
    storeId, partyId, partyType, currency: 'ILS',
    debitMinorUnits: 0, creditMinorUnits: 0, balanceMinorUnits: 0,
  });
  batch.set(ref.collection('party_payments').doc('cheque-1'), {
    storeId, partyId, partyType, paymentMethod: 'cheque',
    amountMinorUnits: AMOUNT, currency: 'ILS', status: 'pending',
    description: 'Cheque pending settlement',
  });
  await batch.commit();
  return ref;
}

function command(storeId, action, date = DATE) {
  return {
    auth: { uid: UID, token: { uid: UID } },
    data: {
      storeId,
      chequeId: 'cheque-1',
      action,
      postedAt: date,
      idempotencyKey: 'settlement-key',
      accounts: {
        checksAccountId: '1130',
        issuedChecksAccountId: '2210',
        customerReceivableAccountId: '1140',
        supplierPayableAccountId: '2110',
        bankAccountId: action === 'clear' ? '1121' : null,
      },
    },
  };
}
const settle = (input) => functions.settleCheque.run(input);

describe('cheque settlement guarded transaction', () => {
  after(async () => { await admin.app().delete(); });

  it('clears once with balanced bank/held-cheque ledger under concurrent requests', async () => {
    const store = await seed('cheque-guard-clear');
    const req = command(store.id, 'clear');
    const results = await Promise.all([settle(req), settle(req)]);
    assert.equal(results.every((x) => x.status === 'cleared'), true);
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    const held = (await store.collection('account_balances').doc('1130').get()).data();
    const bank = (await store.collection('account_balances').doc('1121').get()).data();
    assert.equal(held.balanceMinorUnits, 0);
    assert.equal(bank.balanceMinorUnits, AMOUNT);
    assert.equal(held.balanceMinorUnits + bank.balanceMinorUnits, AMOUNT);
    assert.equal((await store.collection('party_payments').doc('cheque-1').get()).data().status, 'cleared');
    await db.recursiveDelete(store);
  });

  it('rejects replay with a changed settlement date, without a second journal', async () => {
    const store = await seed('cheque-guard-changed');
    await settle(command(store.id, 'bounce'));
    await assert.rejects(
      settle(command(store.id, 'bounce', '2026-10-12T08:00:00.000Z')),
      (error) => error.code === 'already-exists',
    );
    assert.equal((await store.collection('journal_entries').get()).size, 1);
    await db.recursiveDelete(store);
  });

  it('checks full old settlement journal after removing modern fingerprint', async () => {
    const store = await seed('cheque-guard-legacy');
    const req = command(store.id, 'bounce');
    await settle(req);
    await store.collection('cheque_settlement_idempotency').doc('settlement-key').update({
      requestFingerprint: admin.firestore.FieldValue.delete(),
    });
    assert.equal((await settle(req)).status, 'bounced');
    await assert.rejects(
      settle(command(store.id, 'bounce', '2026-10-13T08:00:00.000Z')),
      (error) => error.code === 'already-exists',
    );
    await db.recursiveDelete(store);
  });

  it('refuses corrupt bounced customer party balance before any settlement', async () => {
    const store = await seed('cheque-guard-corrupt-party');
    await store.collection('party_balances').doc('customer-customer-1').update({
      debitMinorUnits: 500, creditMinorUnits: 0, balanceMinorUnits: 0,
    });
    await assert.rejects(
      settle(command(store.id, 'bounce')),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('party_payments').doc('cheque-1').get()).data().status, 'pending');
    await db.recursiveDelete(store);
  });

  it('refuses corrupt held account balance rather than resetting to zero', async () => {
    const store = await seed('cheque-guard-corrupt-gl');
    await store.collection('account_balances').doc('1130').update({
      debitMinorUnits: 'invalid',
    });
    await assert.rejects(
      settle(command(store.id, 'bounce')),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    await db.recursiveDelete(store);
  });
});

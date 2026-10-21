'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');

const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const CURRENCY = 'ILS';
const ACCOUNTANT_ID = 'accountant-1';
const POSTED_AT = '2026-01-15T10:00:00.000Z';
const AMOUNT = 12500;

function account(storeId, id, type, controlType) {
  return {
    storeId,
    id,
    code: id,
    name: id,
    currency: CURRENCY,
    type,
    controlType,
    isActive: true,
    isHeader: false,
  };
}

function balance(storeId, accountId, debitMinorUnits, creditMinorUnits) {
  return {
    storeId,
    accountId,
    currency: CURRENCY,
    debitMinorUnits,
    creditMinorUnits,
    balanceMinorUnits: debitMinorUnits - creditMinorUnits,
  };
}

async function seedCheque({
  storeId,
  chequeId,
  partyType,
  partyId,
}) {
  const storeRef = db.collection('stores').doc(storeId);
  await db.recursiveDelete(storeRef);

  const batch = db.batch();
  batch.set(storeRef, {
    storeId,
    name: storeId,
    currency: CURRENCY,
  });
  batch.set(storeRef.collection('members').doc(ACCOUNTANT_ID), {
    storeId,
    role: 'accountant',
    isActive: true,
  });

  batch.set(
    storeRef.collection('accounts').doc('1130'),
    account(storeId, '1130', 'asset', 'checks'),
  );
  batch.set(
    storeRef.collection('accounts').doc('1140'),
    account(storeId, '1140', 'asset', 'customerReceivable'),
  );
  batch.set(
    storeRef.collection('accounts').doc('2210'),
    account(storeId, '2210', 'liability', 'checksPayable'),
  );
  batch.set(
    storeRef.collection('accounts').doc('2110'),
    account(storeId, '2110', 'liability', 'supplierPayable'),
  );

  const isCustomer = partyType === 'customer';
  const heldAccountId = isCustomer ? '1130' : '2210';
  const counterpartyAccountId = isCustomer ? '1140' : '2110';
  const initialDebit = isCustomer ? 1000 : 0;
  const initialCredit = isCustomer ? 0 : 1000;

  batch.set(
    storeRef.collection('account_balances').doc(heldAccountId),
    balance(
      storeId,
      heldAccountId,
      isCustomer ? AMOUNT : 0,
      isCustomer ? 0 : AMOUNT,
    ),
  );
  batch.set(
    storeRef.collection('account_balances').doc(counterpartyAccountId),
    balance(
      storeId,
      counterpartyAccountId,
      initialDebit,
      initialCredit,
    ),
  );
  batch.set(
    storeRef.collection('party_balances').doc(partyType + '-' + partyId),
    {
      storeId,
      partyType,
      partyId,
      currency: CURRENCY,
      debitMinorUnits: initialDebit,
      creditMinorUnits: initialCredit,
      balanceMinorUnits: initialDebit - initialCredit,
    },
  );
  batch.set(
    storeRef.collection('party_payments').doc(chequeId),
    {
      storeId,
      paymentMethod: 'cheque',
      partyType,
      partyId,
      amountMinorUnits: AMOUNT,
      currency: CURRENCY,
      status: 'pending',
      chequeNumber: chequeId,
      bankName: 'Main Bank',
      receivedAt: admin.firestore.Timestamp.fromDate(new Date(POSTED_AT)),
      description: 'Test cheque',
    },
  );

  await batch.commit();
}

function command({
  storeId,
  chequeId,
  partyType,
  action = 'bounce',
  idempotencyKey = 'cheque-settlement-1',
}) {
  return {
    storeId,
    chequeId,
    action,
    idempotencyKey,
    postedAt: POSTED_AT,
    accounts: {
      checksAccountId: '1130',
      issuedChecksAccountId: '2210',
      customerReceivableAccountId: '1140',
      supplierPayableAccountId: '2110',
      bankAccountId: null,
    },
    partyType,
  };
}

async function invoke(data) {
  return functions.settleCheque.run({
    data,
    auth: {
      uid: ACCOUNTANT_ID,
      token: {uid: ACCOUNTANT_ID},
    },
  });
}

async function getBalance(storeId, accountId) {
  const snapshot = await db
    .collection('stores')
    .doc(storeId)
    .collection('account_balances')
    .doc(accountId)
    .get();
  assert.equal(snapshot.exists, true);
  return snapshot.data();
}

describe('settleCheque accounting scenarios', function () {
  this.timeout(60000);

  after(async () => {
    await admin.app().delete();
  });

  it('bounces a customer cheque once under concurrent retries', async () => {
    const storeId = 'settle-cheque-customer-test';
    const chequeId = 'customer-cheque-1';
    await seedCheque({
      storeId,
      chequeId,
      partyType: 'customer',
      partyId: 'customer-1',
    });

    const payload = command({
      storeId,
      chequeId,
      partyType: 'customer',
    });
    const results = await Promise.all([invoke(payload), invoke(payload)]);

    assert.equal(results[0].status, 'bounced');
    assert.deepEqual(results[1], results[0]);

    const retry = await invoke(payload);
    assert.deepEqual(retry, results[0]);

    const storeRef = db.collection('stores').doc(storeId);
    const cheque = await storeRef.collection('party_payments').doc(chequeId).get();
    assert.equal(cheque.data().status, 'bounced');
    assert.equal(
      cheque.data().settlementJournalEntryId,
      results[0].journalEntryId,
    );

    const journal = await storeRef
      .collection('journal_entries')
      .doc(results[0].journalEntryId)
      .get();
    assert.equal(journal.data().sourceType, 'chequeBounce');
    assert.equal(journal.data().totalDebitMinorUnits, AMOUNT);
    assert.equal(journal.data().totalCreditMinorUnits, AMOUNT);

    const lines = await storeRef
      .collection('journal_entries')
      .doc(results[0].journalEntryId)
      .collection('lines')
      .get();
    assert.equal(lines.size, 2);

    const heldBalance = await getBalance(storeId, '1130');
    assert.equal(heldBalance.debitMinorUnits, AMOUNT);
    assert.equal(heldBalance.creditMinorUnits, AMOUNT);
    assert.equal(heldBalance.balanceMinorUnits, 0);

    const receivableBalance = await getBalance(storeId, '1140');
    assert.equal(receivableBalance.debitMinorUnits, AMOUNT + 1000);
    assert.equal(receivableBalance.creditMinorUnits, 0);
    assert.equal(receivableBalance.balanceMinorUnits, AMOUNT + 1000);

    const partyBalance = await storeRef
      .collection('party_balances')
      .doc('customer-customer-1')
      .get();
    assert.equal(partyBalance.data().debitMinorUnits, AMOUNT + 1000);
    assert.equal(partyBalance.data().balanceMinorUnits, AMOUNT + 1000);

    const bounceLedger = await storeRef
      .collection('party_ledger_entries')
      .doc(chequeId + '-bounce')
      .get();
    assert.equal(bounceLedger.data().debitMinorUnits, AMOUNT);
    assert.equal(bounceLedger.data().creditMinorUnits, 0);

    const idempotency = await storeRef
      .collection('cheque_settlement_idempotency')
      .get();
    assert.equal(idempotency.size, 1);
  });

  it('bounces a supplier cheque back to supplier payable', async () => {
    const storeId = 'settle-cheque-supplier-test';
    const chequeId = 'supplier-cheque-1';
    await seedCheque({
      storeId,
      chequeId,
      partyType: 'supplier',
      partyId: 'supplier-1',
    });

    const result = await invoke(command({
      storeId,
      chequeId,
      partyType: 'supplier',
      idempotencyKey: 'supplier-cheque-settlement-1',
    }));

    assert.equal(result.status, 'bounced');

    const heldBalance = await getBalance(storeId, '2210');
    assert.equal(heldBalance.debitMinorUnits, AMOUNT);
    assert.equal(heldBalance.creditMinorUnits, AMOUNT);
    assert.equal(heldBalance.balanceMinorUnits, 0);

    const payableBalance = await getBalance(storeId, '2110');
    assert.equal(payableBalance.debitMinorUnits, 0);
    assert.equal(payableBalance.creditMinorUnits, AMOUNT + 1000);
    assert.equal(payableBalance.balanceMinorUnits, -(AMOUNT + 1000));

    const storeRef = db.collection('stores').doc(storeId);
    const partyBalance = await storeRef
      .collection('party_balances')
      .doc('supplier-supplier-1')
      .get();
    assert.equal(partyBalance.data().creditMinorUnits, AMOUNT + 1000);
    assert.equal(partyBalance.data().balanceMinorUnits, -(AMOUNT + 1000));

    const bounceLedger = await storeRef
      .collection('party_ledger_entries')
      .doc(chequeId + '-bounce')
      .get();
    assert.equal(bounceLedger.data().debitMinorUnits, 0);
    assert.equal(bounceLedger.data().creditMinorUnits, AMOUNT);
  });
});

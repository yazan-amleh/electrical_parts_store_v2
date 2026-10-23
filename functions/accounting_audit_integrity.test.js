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

  it('detects wrong or missing storeId on nested journal lines', async () => {
    const store = await seed('audit-wrong-journal-tenant');
    await store.collection('journal_entries').doc('journal-a')
      .collection('lines').doc('debit')
      .update({storeId: 'another-shop'});
    const report = await audit(store.id);
    assert.equal(report.complete, true);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.checked.journalLines, 2);
    assert.equal(report.issues.some(
      (issue) => issue.code === 'JOURNAL_LINE_STORE_MISMATCH',
    ), true);
    await db.recursiveDelete(store);
  });

  it('detects a journal line booked against a differently denominated account', async () => {
    const store = await seed('audit-account-line-currency');
    await store.collection('accounts').doc('1110').update({
      currency: 'USD',
    });
    const report = await audit(store.id);
    assert.equal(report.complete, true);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'JOURNAL_LINE_ACCOUNT_CURRENCY_MISMATCH'), true);
    await db.recursiveDelete(store);
  });

  it('reports a credit-only header mismatch without inventing a debit mismatch', async () => {
    const store = await seed('audit-header-credit-only');
    await store.collection('journal_entries').doc('journal-a').update({
      totalCreditMinorUnits: 400,
    });
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'JOURNAL_HEADER_CREDIT_MISMATCH'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'JOURNAL_HEADER_TOTAL_MISMATCH'), false);
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

  async function seedInventory(store, {withMovement = true} = {}) {
    const batch = db.batch();
    for (const [id, type, controlType] of [
      ['1150', 'asset', 'inventory'],
      ['2110', 'liability', 'supplierPayable'],
    ]) {
      batch.set(store.collection('accounts').doc(id), {
        storeId: store.id, id, currency: 'ILS', type, controlType,
        isActive: true, isHeader: false,
      });
    }
    batch.set(store.collection('account_balances').doc('1150'), {
      storeId: store.id, accountId: '1150', currency: 'ILS',
      debitMinorUnits: 700, creditMinorUnits: 0, balanceMinorUnits: 700,
    });
    batch.set(store.collection('account_balances').doc('2110'), {
      storeId: store.id, accountId: '2110', currency: 'ILS',
      debitMinorUnits: 0, creditMinorUnits: 700, balanceMinorUnits: -700,
    });
    batch.set(store.collection('journal_entries').doc('stock-receipt'), {
      storeId: store.id, status: 'posted', sourceType: 'purchase',
      currency: 'ILS', totalDebitMinorUnits: 700, totalCreditMinorUnits: 700,
    });
    batch.set(store.collection('journal_entries').doc('stock-receipt')
      .collection('lines').doc('inventory'), {
      storeId: store.id, entryId: 'stock-receipt',
      accountId: '1150', currency: 'ILS',
      debitMinorUnits: 700, creditMinorUnits: 0,
    });
    batch.set(store.collection('journal_entries').doc('stock-receipt')
      .collection('lines').doc('supplier'), {
      storeId: store.id, entryId: 'stock-receipt',
      accountId: '2110', currency: 'ILS',
      debitMinorUnits: 0, creditMinorUnits: 700,
    });
    batch.set(store.collection('products').doc('component-1'), {
      storeId: store.id, isService: false, currency: 'ILS',
      quantityOnHandMilliUnits: 1000, inventoryValueMinorUnits: 700,
    });
    if (withMovement) {
      batch.set(store.collection('inventory_movements').doc('stock-in'), {
        storeId: store.id, productId: 'component-1', currency: 'ILS',
        quantityDeltaMilliUnits: 1000, totalCostMinorUnits: 700,
      });
    }
    await batch.commit();
  }

  it('reconciles product value, inventory movement, and GL inventory net', async () => {
    const store = await seed('audit-inventory-reconciles');
    await seedInventory(store);
    const report = await audit(store.id);
    assert.equal(report.status, 'healthy');
    assert.equal(report.complete, true);
    assert.equal(report.issues.length, 0);
    await db.recursiveDelete(store);
  });

  it('reports a product valuation change against movement and GL', async () => {
    const store = await seed('audit-inventory-gl-difference');
    await seedInventory(store);
    await store.collection('products').doc('component-1').update({
      inventoryValueMinorUnits: 699,
    });
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_VALUE_MISMATCH'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_GL_VALUATION_MISMATCH'), true);
    await db.recursiveDelete(store);
  });

  it('does not certify product stock without original movement/opening evidence', async () => {
    const store = await seed('audit-inventory-unverified-opening');
    await seedInventory(store, {withMovement: false});
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_OPENING_SOURCE_UNVERIFIED'), true);
    await db.recursiveDelete(store);
  });

  it('finds a currency conflict even when stock quantity, value and GL match', async () => {
    const store = await seed('audit-stock-wrong-currency');
    await seedInventory(store);
    await store.collection('inventory_movements').doc('stock-in')
      .update({currency: 'USD'});
    const report = await audit(store.id);
    assert.equal(report.complete, true);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_PRODUCT_CURRENCY_MISMATCH'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_QUANTITY_MISMATCH' ||
      issue.code === 'INVENTORY_VALUE_MISMATCH' ||
      issue.code === 'INVENTORY_GL_VALUATION_MISMATCH'), false);
    await db.recursiveDelete(store);
  });

  it('rejects mixed-currency movements whose totals still reconcile', async () => {
    const store = await seed('audit-stock-mixed-currency');
    await seedInventory(store);
    await store.collection('inventory_movements').doc('stock-in').update({
      quantityDeltaMilliUnits: 500, totalCostMinorUnits: 350,
    });
    await store.collection('inventory_movements').doc('stock-in-2').set({
      storeId: store.id, productId: 'component-1', currency: 'USD',
      quantityDeltaMilliUnits: 500, totalCostMinorUnits: 350,
    });
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_MULTI_CURRENCY'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_PRODUCT_CURRENCY_MISMATCH'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_VALUE_MISMATCH' ||
      issue.code === 'INVENTORY_GL_VALUATION_MISMATCH'), false);
    await db.recursiveDelete(store);
  });

  it('supports legacy movements with an omitted currency', async () => {
    const store = await seed('audit-stock-legacy-currency');
    await seedInventory(store);
    await store.collection('inventory_movements').doc('stock-in').update({
      currency: admin.firestore.FieldValue.delete(),
    });
    const report = await audit(store.id);
    assert.equal(report.status, 'healthy');
    assert.equal(report.complete, true);
    assert.equal(report.issueCount, 0);
    await db.recursiveDelete(store);
  });

  it('does not infer mixed currencies from an unknown legacy currency', async () => {
    const store = await seed('audit-stock-legacy-mixed-unknown');
    await seedInventory(store);
    await store.collection('inventory_movements').doc('stock-in').update({
      currency: admin.firestore.FieldValue.delete(),
      quantityDeltaMilliUnits: 500,
      totalCostMinorUnits: 350,
    });
    await store.collection('inventory_movements').doc('stock-in-2').set({
      storeId: store.id, productId: 'component-1', currency: 'USD',
      quantityDeltaMilliUnits: 500, totalCostMinorUnits: 350,
    });
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_PRODUCT_CURRENCY_MISMATCH'), true);
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_MULTI_CURRENCY'), false);
    await db.recursiveDelete(store);
  });

  it('flags an explicitly malformed stock movement currency', async () => {
    const store = await seed('audit-stock-invalid-currency');
    await seedInventory(store);
    await store.collection('inventory_movements').doc('stock-in')
      .update({currency: ' '});
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.some((issue) =>
      issue.code === 'INVENTORY_MOVEMENT_CURRENCY_INVALID'), true);
    await db.recursiveDelete(store);
  });

  it('counts errors beyond the first 200 displayed issues', async () => {
    const store = await seed('audit-many-errors');
    const batch = db.batch();
    for (let index = 0; index < 205; index++) {
      batch.set(store.collection('party_ledger_entries')
        .doc('invalid-' + index), {
        storeId: store.id,
        partyType: 'customer',
        partyId: 'unknown-' + index,
        currency: 'ILS',
        debitMinorUnits: 'not-an-integer',
        creditMinorUnits: 0,
      });
    }
    await batch.commit();
    const report = await audit(store.id);
    assert.equal(report.status, 'issues_found');
    assert.equal(report.issues.length, 200);
    assert.equal(report.issuesTruncated, true);
    assert.equal(report.issueCount > 200, true);
    assert.equal(report.errorCount > 200, true);
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

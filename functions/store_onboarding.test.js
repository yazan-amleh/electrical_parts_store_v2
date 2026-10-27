'use strict';

const assert = require('node:assert/strict');
const { after, describe, it } = require('node:test');
const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();

function request(data, uid = 'bootstrap-owner-1') {
  return {
    data,
    auth: uid ? { uid, token: { uid, email: 'owner@example.com' } } : null,
  };
}

describe('store onboarding emulator: server authority and atomic creation', () => {
  after(async () => {
    await admin.app().delete();
  });

  it('creates exactly one owner store and membership under concurrent retries', async () => {
    const uid = 'bootstrap-owner-1';
    const prefRef = db.collection('user_store_preferences').doc(uid);
    await prefRef.delete();
    const [first, second] = await Promise.all([
      functions.createStore.run(request({ name: 'Electrical Shop' }, uid)),
      functions.createStore.run(request({ name: 'Electrical Shop' }, uid)),
    ]);
    assert.equal(first.storeId, second.storeId);
    assert.equal(first.alreadyCreated !== second.alreadyCreated, true);
    const storeRef = db.collection('stores').doc(first.storeId);
    const [store, member, pref] = await Promise.all([
      storeRef.get(),
      storeRef.collection('members').doc(uid).get(),
      prefRef.get(),
    ]);
    assert.equal(store.exists, true);
    assert.equal(store.data().ownerId, uid);
    assert.equal(store.data().currency, 'ILS');
    assert.equal(store.data().initialChartVersion, 2);
    assert.equal(store.data().initialChartAccountCount, 27);
    assert.equal(store.data().accountingChartVersion, 2);
    const accounts = await storeRef.collection('accounts').get();
    assert.equal(accounts.size, 27);
    const cash = accounts.docs.find((doc) => doc.id === '1110');
    assert.equal(cash.data().storeId, first.storeId);
    assert.equal(cash.data().currency, 'ILS');
    assert.equal(cash.data().controlType, 'cashBox');
    assert.equal(cash.data().isHeader, false);
    const openingEquity = accounts.docs.find((doc) => doc.id === '3400');
    const salesReturns = accounts.docs.find((doc) => doc.id === '4200');
    assert.equal(openingEquity.data().normalSide, 'credit');
    assert.equal(salesReturns.data().normalSide, 'debit');
    assert.equal((await storeRef.collection('journal_entries').get()).empty, true);
    assert.equal((await storeRef.collection('account_balances').get()).empty, true);
    assert.equal(member.data().role, 'owner');
    assert.equal(member.data().isActive, true);
    assert.equal(member.data().storeId, first.storeId);
    assert.equal(pref.data().selectedStoreId, first.storeId);
    assert.equal(pref.data().createdStoreId, first.storeId);
    const again = await functions.createStore.run(request({ name: 'Electrical Shop' }, uid));
    assert.equal(again.storeId, first.storeId);
    assert.equal(again.alreadyCreated, true);
    assert.equal((await storeRef.collection('accounts').get()).size, 27);
    await db.recursiveDelete(storeRef);
    await prefRef.delete();
  });

  it('does not allow unauthenticated creation or malformed store names', async () => {
    await assert.rejects(
      functions.createStore.run(request({ name: 'No Access' }, null)),
      (error) => error.code === 'unauthenticated',
    );
    await assert.rejects(
      functions.createStore.run(request({ name: 'x' }, 'user-invalid-name')),
      (error) => error.code === 'invalid-argument',
    );
  });

  it('upgrades an existing chart atomically and is idempotent', async () => {
    const uid = 'bootstrap-upgrade-owner';
    const store = db.collection('stores').doc('bootstrap-upgrade-v1');
    await db.recursiveDelete(store);
    const batch = db.batch();
    batch.set(store, {
      ownerId: uid,
      name: 'Old V2 Store',
      currency: 'ILS',
      initialChartVersion: 1,
      initialChartAccountCount: 25,
    });
    batch.set(store.collection('members').doc(uid), {
      storeId: store.id,
      userId: uid,
      role: 'owner',
      isActive: true,
    });
    batch.set(store.collection('accounts').doc('3100'), {
      storeId: store.id,
      id: '3100',
      code: '3100',
      name: 'حقوق الملكية',
      type: 'equity',
      normalSide: 'credit',
      controlType: 'none',
      statementSection: 'equity',
      parentId: null,
      currency: 'ILS',
      isHeader: true,
      sortOrder: 400,
      isActive: true,
    });
    await batch.commit();

    const first = await functions.upgradeDefaultChart.run({
      auth: {uid, token: {uid}},
      data: {storeId: store.id},
    });
    assert.equal(first.status, 'upgraded');
    assert.equal(first.version, 2);
    assert.deepEqual(first.addedAccountIds.sort(), ['3400', '4200']);
    assert.equal((await store.get()).data().accountingChartVersion, 2);
    assert.equal((await store.collection('accounts').doc('3400').get())
      .data().normalSide, 'credit');
    assert.equal((await store.collection('accounts').doc('4200').get())
      .data().normalSide, 'debit');
    assert.equal((await store.collection('journal_entries').get()).empty, true);
    assert.equal((await store.collection('account_balances').get()).empty, true);
    const epochAfterFirst = (await store.collection('accounting_posting_epochs')
      .get()).docs.reduce((sum, doc) => sum + doc.data().sequence, 0);
    assert.equal(epochAfterFirst, 1);

    const second = await functions.upgradeDefaultChart.run({
      auth: {uid, token: {uid}},
      data: {storeId: store.id},
    });
    assert.equal(second.status, 'unchanged');
    assert.deepEqual(second.addedAccountIds, []);
    const epochAfterSecond = (await store.collection('accounting_posting_epochs')
      .get()).docs.reduce((sum, doc) => sum + doc.data().sequence, 0);
    assert.equal(epochAfterSecond, 1);
    await db.recursiveDelete(store);
  });

  it('rejects a conflicting chart without partially creating prerequisites', async () => {
    const uid = 'bootstrap-upgrade-conflict-owner';
    const store = db.collection('stores').doc('bootstrap-upgrade-conflict');
    await db.recursiveDelete(store);
    const batch = db.batch();
    batch.set(store, {
      ownerId: uid,
      name: 'Conflicting Store',
      currency: 'ILS',
      initialChartVersion: 1,
      initialChartAccountCount: 25,
    });
    batch.set(store.collection('members').doc(uid), {
      storeId: store.id,
      userId: uid,
      role: 'owner',
      isActive: true,
    });
    batch.set(store.collection('accounts').doc('3100'), {
      storeId: store.id,
      id: '3100',
      code: '3100',
      name: 'حقوق الملكية',
      type: 'equity',
      normalSide: 'credit',
      controlType: 'none',
      statementSection: 'equity',
      parentId: null,
      currency: 'ILS',
      isHeader: true,
      sortOrder: 400,
      isActive: true,
    });
    batch.set(store.collection('accounts').doc('4200'), {
      storeId: store.id,
      id: '4200',
      code: '4200',
      name: 'Wrong Sales Returns',
      type: 'revenue',
      normalSide: 'credit',
      controlType: 'none',
      statementSection: 'revenue',
      parentId: null,
      currency: 'ILS',
      isHeader: false,
      sortOrder: 520,
      isActive: true,
    });
    await batch.commit();

    await assert.rejects(
      functions.upgradeDefaultChart.run({
        auth: {uid, token: {uid}},
        data: {storeId: store.id},
      }),
      (error) => error.code === 'failed-precondition',
    );
    assert.equal((await store.collection('accounts').doc('3400').get()).exists,
      false);
    assert.equal((await store.get()).data().accountingChartVersion, undefined);
    assert.equal((await store.collection('accounting_posting_epochs').get())
      .empty, true);
    await db.recursiveDelete(store);
  });

  it('allows only an active owner/admin to upgrade the default chart', async () => {
    const owner = 'bootstrap-upgrade-role-owner';
    const accountant = 'bootstrap-upgrade-role-accountant';
    const store = db.collection('stores').doc('bootstrap-upgrade-role');
    await db.recursiveDelete(store);
    const batch = db.batch();
    batch.set(store, {ownerId: owner, name: 'Role Store', currency: 'ILS'});
    batch.set(store.collection('members').doc(owner), {
      storeId: store.id, userId: owner, role: 'owner', isActive: true,
    });
    batch.set(store.collection('members').doc(accountant), {
      storeId: store.id, userId: accountant, role: 'accountant', isActive: true,
    });
    batch.set(store.collection('accounts').doc('3100'), {
      storeId: store.id,
      id: '3100',
      code: '3100',
      name: 'حقوق الملكية',
      type: 'equity',
      normalSide: 'credit',
      controlType: 'none',
      statementSection: 'equity',
      parentId: null,
      currency: 'ILS',
      isHeader: true,
      sortOrder: 400,
      isActive: true,
    });
    await batch.commit();
    await assert.rejects(
      functions.upgradeDefaultChart.run({
        auth: {uid: accountant, token: {uid: accountant}},
        data: {storeId: store.id},
      }),
      (error) => error.code === 'permission-denied',
    );
    await db.recursiveDelete(store);
  });

  it('selects only an existing active membership; prevents cross-store takeover', async () => {
    const storeRef = db.collection('stores').doc('bootstrap-selection-test');
    const uid = 'bootstrap-member-2';
    const prefRef = db.collection('user_store_preferences').doc(uid);
    await prefRef.delete();
    await db.recursiveDelete(storeRef);
    await storeRef.set({ ownerId: 'different-owner', name: 'Existing Store', currency: 'ILS' });
    await assert.rejects(
      functions.selectStore.run(request({ storeId: storeRef.id }, uid)),
      (error) => error.code === 'permission-denied',
    );
    await storeRef.collection('members').doc(uid).set({
      storeId: storeRef.id, userId: uid, role: 'sales', isActive: false,
    });
    await assert.rejects(
      functions.selectStore.run(request({ storeId: storeRef.id }, uid)),
      (error) => error.code === 'permission-denied',
    );
    await storeRef.collection('members').doc(uid).update({ isActive: true });
    const selected = await functions.selectStore.run(request({ storeId: storeRef.id }, uid));
    assert.equal(selected.storeId, storeRef.id);
    assert.equal((await prefRef.get()).data().selectedStoreId, storeRef.id);
    assert.equal((await prefRef.get()).data().createdStoreId, undefined);
    await db.recursiveDelete(storeRef);
    await prefRef.delete();
  });
});

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
    assert.equal(member.data().role, 'owner');
    assert.equal(member.data().isActive, true);
    assert.equal(member.data().storeId, first.storeId);
    assert.equal(pref.data().selectedStoreId, first.storeId);
    assert.equal(pref.data().createdStoreId, first.storeId);
    const again = await functions.createStore.run(request({ name: 'Electrical Shop' }, uid));
    assert.equal(again.storeId, first.storeId);
    assert.equal(again.alreadyCreated, true);
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

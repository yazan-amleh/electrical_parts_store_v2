'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');
const admin = require('firebase-admin');
const {HttpsError} = require('firebase-functions/v2/https');
require('./index');
const {
  updateStoreProfileHandler,
  addStoreMemberHandler,
  updateStoreMemberHandler,
} = require('./settings_management');

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

async function seed(storeId) {
  const store = db.collection('stores').doc(storeId);
  await db.recursiveDelete(store);
  const batch = db.batch();
  batch.set(store, {
    ownerId: 'owner-1',
    name: 'Original Store',
    currency: 'ILS',
  });
  for (const [uid, role] of [
    ['owner-1', 'owner'],
    ['admin-1', 'admin'],
    ['sales-1', 'sales'],
  ]) {
    batch.set(store.collection('members').doc(uid), {
      storeId,
      userId: uid,
      role,
      isActive: true,
    });
  }
  await batch.commit();
  return store;
}

function request(uid, data) {
  return {
    auth: {uid, token: {uid}},
    data,
  };
}

describe('server-owned settings management', () => {
  after(async () => {await admin.app().delete();});

  it('allows managers to update normal members but never the owner', async () => {
    const store = await seed('settings-member-guard');

    const updated = await updateStoreMemberHandler({
      db,
      FieldValue,
      HttpsError,
      request: request('admin-1', {
        storeId: store.id,
        member: {
          userId: 'sales-1',
          role: 'accountant',
          isActive: false,
        },
      }),
    });
    assert.equal(updated.role, 'accountant');
    assert.equal(updated.isActive, false);

    const sales = (await store.collection('members')
      .doc('sales-1').get()).data();
    assert.equal(sales.role, 'accountant');
    assert.equal(sales.isActive, false);

    await assert.rejects(
      updateStoreMemberHandler({
        db,
        FieldValue,
        HttpsError,
        request: request('admin-1', {
          storeId: store.id,
          member: {
            userId: 'owner-1',
            role: 'admin',
            isActive: false,
          },
        }),
      }),
      (error) => error.code === 'failed-precondition',
    );

    const owner = (await store.collection('members')
      .doc('owner-1').get()).data();
    assert.equal(owner.role, 'owner');
    assert.equal(owner.isActive, true);
    await db.recursiveDelete(store);
  });

  it('rejects owner role assignment and non-manager member mutation', async () => {
    const store = await seed('settings-role-guard');

    await assert.rejects(
      updateStoreMemberHandler({
        db,
        FieldValue,
        HttpsError,
        request: request('admin-1', {
          storeId: store.id,
          member: {
            userId: 'sales-1',
            role: 'owner',
            isActive: true,
          },
        }),
      }),
      (error) => error.code === 'invalid-argument',
    );

    await assert.rejects(
      updateStoreMemberHandler({
        db,
        FieldValue,
        HttpsError,
        request: request('sales-1', {
          storeId: store.id,
          member: {
            userId: 'admin-1',
            role: 'viewer',
            isActive: true,
          },
        }),
      }),
      (error) => error.code === 'permission-denied',
    );
    await db.recursiveDelete(store);
  });

  it('adds an existing auth user using trusted auth profile data', async () => {
    const store = await seed('settings-add-member');
    const fakeAuth = {
      getUser: async (uid) => ({
        uid,
        displayName: 'Trusted Auth Name',
        email: 'TRUSTED@EXAMPLE.COM',
      }),
    };

    const added = await addStoreMemberHandler({
      db,
      auth: fakeAuth,
      FieldValue,
      HttpsError,
      request: request('admin-1', {
        storeId: store.id,
        member: {
          userId: 'new-user',
          role: 'viewer',
          displayName: 'Forged Client Name',
          email: 'forged@example.com',
        },
      }),
    });

    assert.equal(added.displayName, 'Trusted Auth Name');
    assert.equal(added.email, 'trusted@example.com');

    const stored = (await store.collection('members')
      .doc('new-user').get()).data();
    assert.equal(stored.role, 'viewer');
    assert.equal(stored.displayName, 'Trusted Auth Name');
    assert.equal(stored.email, 'trusted@example.com');
    await db.recursiveDelete(store);
  });

  it('updates only profile fields and keeps initialized currency immutable', async () => {
    const store = await seed('settings-profile-guard');

    const updated = await updateStoreProfileHandler({
      db,
      FieldValue,
      HttpsError,
      request: request('admin-1', {
        storeId: store.id,
        profile: {
          name: 'Updated Store',
          currency: 'ILS',
          phone: '0599000000',
          address: 'Ramallah',
          ownerId: 'attacker',
        },
      }),
    });
    assert.equal(updated.name, 'Updated Store');

    const stored = (await store.get()).data();
    assert.equal(stored.ownerId, 'owner-1');
    assert.equal(stored.name, 'Updated Store');

    await assert.rejects(
      updateStoreProfileHandler({
        db,
        FieldValue,
        HttpsError,
        request: request('admin-1', {
          storeId: store.id,
          profile: {
            name: 'Currency Attack',
            currency: 'USD',
            phone: '',
            address: '',
          },
        }),
      }),
      (error) => error.code === 'failed-precondition',
    );
    await db.recursiveDelete(store);
  });
});

'use strict';

const { buildDefaultChartDocuments, getDefaultChart } = require('./default_chart_of_accounts');

// Server-owned first-store provisioning. Firebase credentials and store ownership
// are never accepted from client payloads.
function requireUser(request, HttpsError) {
  const uid = request.auth?.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new HttpsError('unauthenticated', 'Sign in before managing stores.');
  }
  return uid;
}

function requireStoreName(value, HttpsError) {
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', 'Store name is required.');
  }
  const name = value.trim();
  if (name.length < 2 || name.length > 100) {
    throw new HttpsError('invalid-argument', 'Store name must contain 2-100 characters.');
  }
  return name;
}

function requireStoreId(value, HttpsError) {
  if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]{1,128}$/.test(value)) {
    throw new HttpsError('invalid-argument', 'Invalid store identifier.');
  }
  return value;
}

async function createStoreHandler({ db, FieldValue, HttpsError, request }) {
  const uid = requireUser(request, HttpsError);
  const name = requireStoreName(request.data?.name, HttpsError);
  const preferencesRef = db.collection('user_store_preferences').doc(uid);
  // Random server-generated ID; never use a shared default store ID for provisioning.
  const storeRef = db.collection('stores').doc();
  const memberRef = storeRef.collection('members').doc(uid);
  // Validate the pinned template before any transaction writes.
  const initialAccounts = buildDefaultChartDocuments(storeRef.id);
  const chartVersion = getDefaultChart().version;
  return db.runTransaction(async (tx) => {
    const existing = await tx.get(preferencesRef);
    if (existing.exists && existing.data()?.createdStoreId) {
      // Retry of a previously acknowledged or ambiguous commit: no second store.
      return { storeId: existing.data().createdStoreId, alreadyCreated: true };
    }
    const timestamp = FieldValue.serverTimestamp();
    tx.create(storeRef, {
      ownerId: uid,
      name,
      currency: 'ILS',
      initialChartVersion: chartVersion,
      initialChartAccountCount: initialAccounts.length,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    // Atomic seed: a store cannot become visible without its complete chart.
    // This does not create journals, balance deltas, or opening entries.
    for (const account of initialAccounts) {
      tx.create(storeRef.collection('accounts').doc(account.id), account);
    }
    tx.create(memberRef, {
      storeId: storeRef.id,
      userId: uid,
      role: 'owner',
      isActive: true,
      displayName: request.auth?.token?.name || '',
      email: request.auth?.token?.email || '',
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    tx.set(preferencesRef, {
      userId: uid,
      selectedStoreId: storeRef.id,
      createdStoreId: storeRef.id,
      updatedAt: timestamp,
    }, { merge: true });
    return { storeId: storeRef.id, alreadyCreated: false };
  });
}

async function selectStoreHandler({ db, FieldValue, HttpsError, request }) {
  const uid = requireUser(request, HttpsError);
  const storeId = requireStoreId(request.data?.storeId, HttpsError);
  const storeRef = db.collection('stores').doc(storeId);
  const memberRef = storeRef.collection('members').doc(uid);
  const preferencesRef = db.collection('user_store_preferences').doc(uid);

  return db.runTransaction(async (tx) => {
    const [store, member] = await Promise.all([tx.get(storeRef), tx.get(memberRef)]);
    const data = member.data() || {};
    if (!store.exists || !member.exists || data.isActive !== true ||
        (data.storeId && data.storeId !== storeId) ||
        (data.userId && data.userId !== uid)) {
      throw new HttpsError('permission-denied', 'No active membership in the selected store.');
    }
    tx.set(preferencesRef, {
      userId: uid,
      selectedStoreId: storeId,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    return { storeId };
  });
}

module.exports = {
  createStoreHandler,
  selectStoreHandler,
  requireStoreId,
  requireStoreName,
};

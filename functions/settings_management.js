'use strict';

const {requireStoreId} = require('./store_onboarding');

const MEMBER_ROLES = new Set([
  'admin',
  'accountant',
  'sales',
  'warehouse',
  'viewer',
]);

function requireUid(request, HttpsError) {
  const uid = request.auth?.uid;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  return uid;
}

function requireMemberId(value, HttpsError) {
  if (typeof value !== 'string' ||
      !/^[^/]{1,128}$/.test(value.trim())) {
    throw new HttpsError('invalid-argument', 'Invalid member identifier.');
  }
  return value.trim();
}

function requireRole(value, HttpsError) {
  if (typeof value !== 'string' || !MEMBER_ROLES.has(value)) {
    throw new HttpsError(
      'invalid-argument',
      'Member role must be a non-owner store role.',
    );
  }
  return value;
}

function requireBoolean(value, label, HttpsError) {
  if (typeof value !== 'boolean') {
    throw new HttpsError('invalid-argument', label + ' must be boolean.');
  }
  return value;
}

function normalizedText(value, label, maxLength, HttpsError, {
  required = false,
} = {}) {
  if (value == null) {
    if (required) {
      throw new HttpsError('invalid-argument', label + ' is required.');
    }
    return '';
  }
  if (typeof value !== 'string') {
    throw new HttpsError('invalid-argument', label + ' must be text.');
  }
  const result = value.trim();
  if (required && result.length < 2) {
    throw new HttpsError(
      'invalid-argument',
      label + ' must contain at least 2 characters.',
    );
  }
  if (result.length > maxLength) {
    throw new HttpsError(
      'invalid-argument',
      label + ' is too long.',
    );
  }
  return result;
}

function assertManager(memberSnapshot, storeId, uid, HttpsError) {
  if (!memberSnapshot.exists) {
    throw new HttpsError(
      'permission-denied',
      'Active store manager membership is required.',
    );
  }
  const member = memberSnapshot.data() || {};
  if (member.isActive !== true ||
      (member.storeId && member.storeId !== storeId) ||
      (member.userId && member.userId !== uid) ||
      !['owner', 'admin'].includes(member.role)) {
    throw new HttpsError(
      'permission-denied',
      'Owner or administrator access is required.',
    );
  }
  return member;
}

async function updateStoreProfileHandler({
  db,
  FieldValue,
  HttpsError,
  request,
}) {
  const uid = requireUid(request, HttpsError);
  const storeId = requireStoreId(request.data?.storeId, HttpsError);
  const raw = request.data?.profile;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'Store profile is required.');
  }

  const name = normalizedText(
    raw.name,
    'Store name',
    100,
    HttpsError,
    {required: true},
  );
  const currency = normalizedText(
    raw.currency,
    'Store currency',
    8,
    HttpsError,
    {required: true},
  ).toUpperCase();
  const phone = normalizedText(raw.phone, 'Store phone', 50, HttpsError);
  const address = normalizedText(
    raw.address,
    'Store address',
    500,
    HttpsError,
  );

  const storeRef = db.collection('stores').doc(storeId);
  const memberRef = storeRef.collection('members').doc(uid);

  return db.runTransaction(async (tx) => {
    const [storeSnapshot, memberSnapshot] = await Promise.all([
      tx.get(storeRef),
      tx.get(memberRef),
    ]);
    assertManager(memberSnapshot, storeId, uid, HttpsError);
    if (!storeSnapshot.exists) {
      throw new HttpsError('not-found', 'Store was not found.');
    }
    const store = storeSnapshot.data() || {};
    const currentCurrency =
      typeof store.currency === 'string'
        ? store.currency.trim().toUpperCase()
        : '';
    if (currentCurrency && currency !== currentCurrency) {
      throw new HttpsError(
        'failed-precondition',
        'Store currency cannot change after initialization.',
      );
    }

    tx.update(storeRef, {
      name,
      currency: currentCurrency || currency,
      phone,
      address,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      storeId,
      name,
      currency: currentCurrency || currency,
      phone,
      address,
    };
  });
}

async function addStoreMemberHandler({
  db,
  auth,
  FieldValue,
  HttpsError,
  request,
}) {
  const uid = requireUid(request, HttpsError);
  const storeId = requireStoreId(request.data?.storeId, HttpsError);
  const raw = request.data?.member;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'Member details are required.');
  }
  const targetUid = requireMemberId(raw.userId, HttpsError);
  const role = requireRole(raw.role, HttpsError);

  let authUser;
  try {
    authUser = await auth.getUser(targetUid);
  } catch (error) {
    if (error?.code === 'auth/user-not-found') {
      throw new HttpsError(
        'not-found',
        'The user must exist in Firebase Authentication first.',
      );
    }
    throw error;
  }

  const storeRef = db.collection('stores').doc(storeId);
  const actorRef = storeRef.collection('members').doc(uid);
  const targetRef = storeRef.collection('members').doc(targetUid);

  return db.runTransaction(async (tx) => {
    const [storeSnapshot, actorSnapshot, targetSnapshot] = await Promise.all([
      tx.get(storeRef),
      tx.get(actorRef),
      tx.get(targetRef),
    ]);
    assertManager(actorSnapshot, storeId, uid, HttpsError);
    if (!storeSnapshot.exists) {
      throw new HttpsError('not-found', 'Store was not found.');
    }
    if (targetSnapshot.exists) {
      throw new HttpsError(
        'already-exists',
        'This user is already a member of the store.',
      );
    }

    const displayName =
      typeof authUser.displayName === 'string'
        ? authUser.displayName.trim()
        : '';
    const email =
      typeof authUser.email === 'string'
        ? authUser.email.trim().toLowerCase()
        : '';

    tx.create(targetRef, {
      storeId,
      userId: targetUid,
      role,
      isActive: true,
      displayName,
      email,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      storeId,
      userId: targetUid,
      role,
      isActive: true,
      displayName,
      email,
    };
  });
}

async function updateStoreMemberHandler({
  db,
  FieldValue,
  HttpsError,
  request,
}) {
  const uid = requireUid(request, HttpsError);
  const storeId = requireStoreId(request.data?.storeId, HttpsError);
  const raw = request.data?.member;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new HttpsError('invalid-argument', 'Member details are required.');
  }
  const targetUid = requireMemberId(raw.userId, HttpsError);
  const role = requireRole(raw.role, HttpsError);
  const isActive = requireBoolean(
    raw.isActive,
    'Member active state',
    HttpsError,
  );

  const storeRef = db.collection('stores').doc(storeId);
  const actorRef = storeRef.collection('members').doc(uid);
  const targetRef = storeRef.collection('members').doc(targetUid);

  return db.runTransaction(async (tx) => {
    const [actorSnapshot, targetSnapshot] = await Promise.all([
      tx.get(actorRef),
      tx.get(targetRef),
    ]);
    assertManager(actorSnapshot, storeId, uid, HttpsError);
    if (!targetSnapshot.exists) {
      throw new HttpsError('not-found', 'Member was not found.');
    }

    const target = targetSnapshot.data() || {};
    if ((target.storeId && target.storeId !== storeId) ||
        (target.userId && target.userId !== targetUid)) {
      throw new HttpsError(
        'failed-precondition',
        'Stored membership identity is inconsistent.',
      );
    }
    if (target.role === 'owner') {
      throw new HttpsError(
        'failed-precondition',
        'The store owner cannot be changed here.',
      );
    }

    tx.update(targetRef, {
      role,
      isActive,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      storeId,
      userId: targetUid,
      role,
      isActive,
    };
  });
}

module.exports = {
  updateStoreProfileHandler,
  addStoreMemberHandler,
  updateStoreMemberHandler,
};

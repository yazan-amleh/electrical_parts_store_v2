'use strict';

// Tenant-scoped server-only chart changes, serialized with the same financial
// source epoch as journal postings. Never edit posted journals or balances.
const {markJournalPosting} = require('./posting_epoch');

const TYPES = new Set(['asset', 'liability', 'equity', 'revenue', 'expense']);
const SIDES = new Set(['debit', 'credit']);
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const CURRENCY = /^[A-Z]{3}$/;
const CREATE_FIELDS = new Set([
  'id', 'code', 'name', 'type', 'normalSide', 'currency',
  'isHeader', 'isActive', 'parentId', 'sortOrder', 'statementSection',
  'controlType', 'description',
]);
const UPDATE_FIELDS = new Set([
  'name', 'description', 'sortOrder', 'isActive',
  // Allow reparenting only through the guarded server-side operation.
  'parentId',
]);

function error(HttpsError, code, message) {
  throw new HttpsError(code, message);
}
function owned(value) {
  return value != null && typeof value === 'object' &&
    !Array.isArray(value);
}
function cleanText(v, max) {
  return typeof v === 'string' && v.trim().length > 0 &&
    v.trim().length <= max;
}
function validParent(v) {
  return v === null || (typeof v === 'string' && ID.test(v));
}
function parseCommand(data, HttpsError) {
  if (!owned(data) || typeof data.storeId !== 'string' ||
      !ID.test(data.storeId) || !owned(data.account)) {
    error(HttpsError, 'invalid-argument', 'Invalid chart mutation command.');
  }
  const {account, storeId} = data;
  if (typeof account.id !== 'string' || !ID.test(account.id)) {
    error(HttpsError, 'invalid-argument', 'Invalid chart account ID.');
  }
  const kind = data.operation;
  if (kind !== 'create' && kind !== 'update') {
    error(HttpsError, 'invalid-argument', 'Unsupported chart operation.');
  }
  const allowed = kind === 'create' ? CREATE_FIELDS : new Set([
    ...UPDATE_FIELDS, 'id',
  ]);
  if (Object.keys(account).some((key) => !allowed.has(key))) {
    error(HttpsError, 'invalid-argument', 'Unsupported chart account fields.');
  }
  if (kind === 'create') {
    if (account.code !== account.id || !cleanText(account.name, 160) ||
        !TYPES.has(account.type) || !SIDES.has(account.normalSide) ||
        typeof account.currency !== 'string' ||
        !CURRENCY.test(account.currency) ||
        typeof account.isHeader !== 'boolean' ||
        typeof account.isActive !== 'boolean' ||
        !validParent(account.parentId) ||
        !Number.isSafeInteger(account.sortOrder) ||
        account.sortOrder < 0 || account.sortOrder > 1000000 ||
        !cleanText(account.statementSection, 120) ||
        !cleanText(account.controlType, 80) ||
        account.controlType !== 'none') {
      error(HttpsError, 'invalid-argument', 'Invalid chart account metadata.');
    }
  } else {
    if (Object.keys(account).length < 2 ||
        ('name' in account && !cleanText(account.name, 160)) ||
        ('description' in account &&
         account.description !== null &&
         (typeof account.description !== 'string' ||
          account.description.length > 500)) ||
        ('sortOrder' in account &&
         (!Number.isSafeInteger(account.sortOrder) ||
          account.sortOrder < 0 || account.sortOrder > 1000000)) ||
        ('isActive' in account &&
         typeof account.isActive !== 'boolean') ||
        ('parentId' in account && !validParent(account.parentId))) {
      error(HttpsError, 'invalid-argument', 'Invalid chart account update.');
    }
  }
  return {storeId, account, kind};
}
async function mutateChartAccount({
  db, FieldValue, HttpsError, userId, data, assertAccess,
}) {
  const command = parseCommand(data, HttpsError);
  const {storeId, account, kind} = command;
  const store = db.collection('stores').doc(storeId);
  const target = store.collection('accounts').doc(account.id);
  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(userId));
    assertAccess(member, storeId);
    const current = await tx.get(target);
    if (kind === 'create' && current.exists) {
      error(HttpsError, 'already-exists', 'Chart account already exists.');
    }
    if (kind === 'update' && !current.exists) {
      error(HttpsError, 'not-found', 'Chart account not found.');
    }

    const before = current.exists ? current.data() : null;
    if (before && (before.storeId !== storeId ||
        before.id !== account.id ||
        before.code !== account.id)) {
      error(HttpsError, 'failed-precondition',
        'Existing chart account identity is corrupted.');
    }
    // All monetary classification fields are immutable on update.
    // This avoids reclassifying previously posted transactions and changing
    // their interpretation through metadata-only chart modifications.
    const after = before ? {...before, ...account} : {
      ...account, storeId,
    };
    if (after.parentId === account.id) {
      error(HttpsError, 'invalid-argument', 'Account cannot parent itself.');
    }
    if (before && before.isHeader === true &&
        account.isActive === false) {
      error(HttpsError, 'failed-precondition',
        'Cannot deactivate a grouping account.');
    }

    if (after.parentId != null) {
      const parentRef = store.collection('accounts').doc(after.parentId);
      const parent = await tx.get(parentRef);
      if (!parent.exists || parent.data().storeId !== storeId ||
          parent.data().isHeader !== true ||
          parent.data().type !== after.type ||
          parent.data().currency !== after.currency ||
          parent.data().isActive !== true) {
        error(HttpsError, 'failed-precondition',
          'Parent must be an active grouping account of the same type and currency.');
      }
      // A header cannot be nested beneath its own descendant.
      let ancestorId = parent.data().parentId;
      const visited = new Set([account.id, after.parentId]);
      for (let step = 0; ancestorId != null && step < 32; step++) {
        if (!ID.test(ancestorId) || visited.has(ancestorId)) {
          error(HttpsError, 'failed-precondition',
            'Chart has a cycle or invalid parent chain.');
        }
        visited.add(ancestorId);
        const ancestor = await tx.get(
          store.collection('accounts').doc(ancestorId));
        if (!ancestor.exists || ancestor.data().storeId !== storeId) {
          error(HttpsError, 'failed-precondition',
            'Chart parent chain is incomplete.');
        }
        ancestorId = ancestor.data().parentId;
        if (step === 31 && ancestorId != null) {
          error(HttpsError, 'failed-precondition',
            'Chart hierarchy depth exceeds supported limit.');
        }
      }
    }

    // Idempotent no-change update does not advance the financial epoch.
    if (before && Object.keys(account).every((key) =>
      Object.is(before[key], account[key]))) {
      return {status: 'unchanged', accountId: account.id, storeId};
    }

    tx.set(target, {
      ...after,
      updatedAt: FieldValue.serverTimestamp(),
    });
    markJournalPosting(tx, store, 'chart:' + account.id, FieldValue);
    return {
      status: kind === 'create' ? 'created' : 'updated',
      accountId: account.id, storeId,
    };
  });
}

module.exports = {
  parseCommand, mutateChartAccount,
};

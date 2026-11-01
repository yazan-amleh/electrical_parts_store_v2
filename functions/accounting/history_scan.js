'use strict';

// Durable, bounded document-inventory phase of historical accounting audits.
// This is NOT a ledger reconciliation and NOT a point-in-time snapshot.
// Each page updates a server-owned checkpoint atomically. Clients cannot
// choose collection paths, mutate source documents, or certify balances.

const PAGE_SIZE = 100;
const RUN_SCHEMA_VERSION = 1;
const PHASES = Object.freeze([
  'accounts',
  'account_balances',
  'journal_entries',
  'parties',
  'party_balances',
  'party_ledger_entries',
  'products',
  'inventory_movements',
]);

function validateRunState(state, storeId, userId, HttpsError) {
  if (!state || state.schemaVersion !== RUN_SCHEMA_VERSION ||
      state.storeId !== storeId || state.createdBy !== userId ||
      !Number.isSafeInteger(state.phaseIndex) ||
      state.phaseIndex < 0 || state.phaseIndex > PHASES.length ||
      !Number.isSafeInteger(state.documentsScanned) ||
      state.documentsScanned < 0 ||
      !Number.isSafeInteger(state.pagesScanned) || state.pagesScanned < 0 ||
      (state.cursor !== null &&
        (typeof state.cursor !== 'string' || !state.cursor)) ||
      !state.phaseCounts || typeof state.phaseCounts !== 'object' ||
      Array.isArray(state.phaseCounts) ||
      !['running', 'enumeration_complete'].includes(state.status)) {
    throw new HttpsError('failed-precondition',
      'The accounting inventory checkpoint is invalid.');
  }
  if ((state.status === 'enumeration_complete') !==
      (state.phaseIndex === PHASES.length)) {
    throw new HttpsError('failed-precondition',
      'The accounting inventory checkpoint status is inconsistent.');
  }
}

function publicStatus(runId, state) {
  return {
    runId,
    storeId: state.storeId,
    status: state.status,
    scope: 'document_inventory_only',
    certified: false,
    consistency: 'non_atomic',
    phase: PHASES[state.phaseIndex] || null,
    pagesScanned: state.pagesScanned,
    documentsScanned: state.documentsScanned,
    phaseCounts: {...state.phaseCounts},
  };
}

async function createHistoryScan({
  db, FieldValue, storeId, userId, assertAccess,
}) {
  const storeRef = db.collection('stores').doc(storeId);
  // No checkpoint can be created without current authorized membership.
  const membership = await storeRef.collection('members').doc(userId).get();
  assertAccess(membership, storeId);
  const runRef = storeRef.collection('accounting_audit_runs').doc();
  const state = {
    schemaVersion: RUN_SCHEMA_VERSION,
    storeId,
    createdBy: userId,
    status: 'running',
    phaseIndex: 0,
    cursor: null,
    documentsScanned: 0,
    pagesScanned: 0,
    phaseCounts: {},
    consistency: 'non_atomic',
    certified: false,
    scope: 'document_inventory_only',
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await runRef.create(state);
  return publicStatus(runRef.id, state);
}

async function advanceHistoryScan({
  db, FieldValue, HttpsError, storeId, runId, userId, assertAccess,
}) {
  const storeRef = db.collection('stores').doc(storeId);
  const memberRef = storeRef.collection('members').doc(userId);
  const runRef = storeRef.collection('accounting_audit_runs').doc(runId);

  return db.runTransaction(async (transaction) => {
    // Read membership inside the same transaction as the checkpoint.
    // A concurrent advance of the same run must retry against the new cursor.
    const membership = await transaction.get(memberRef);
    assertAccess(membership, storeId);
    const run = await transaction.get(runRef);
    if (!run.exists) {
      throw new HttpsError('not-found', 'Accounting inventory run not found.');
    }
    const state = run.data();
    if (state.createdBy !== userId || state.storeId !== storeId) {
      throw new HttpsError('permission-denied',
        'Accounting inventory run belongs to another user or store.');
    }
    validateRunState(state, storeId, userId, HttpsError);
    if (state.status === 'enumeration_complete') {
      return publicStatus(runId, state);
    }

    const collectionName = PHASES[state.phaseIndex];
    let query = storeRef.collection(collectionName)
      .orderBy('__name__').limit(PAGE_SIZE + 1);
    if (state.cursor !== null) {
      query = query.startAfter(state.cursor);
    }
    const page = await transaction.get(query);
    const batch = page.docs.slice(0, PAGE_SIZE);
    const more = page.docs.length > PAGE_SIZE;
    const phaseCounts = {...state.phaseCounts};
    const previous = phaseCounts[collectionName] || 0;
    const nextTotal = state.documentsScanned + batch.length;
    const nextPhaseTotal = previous + batch.length;
    if (!Number.isSafeInteger(nextTotal) ||
        !Number.isSafeInteger(nextPhaseTotal) ||
        !Number.isSafeInteger(state.pagesScanned + 1)) {
      throw new HttpsError('failed-precondition',
        'Accounting inventory counter exceeds safe integer precision.');
    }
    phaseCounts[collectionName] = nextPhaseTotal;
    const phaseIndex = more ? state.phaseIndex : state.phaseIndex + 1;
    const nextState = {
      ...state,
      status: phaseIndex === PHASES.length
        ? 'enumeration_complete' : 'running',
      phaseIndex,
      cursor: more ? batch[batch.length - 1].id : null,
      documentsScanned: nextTotal,
      pagesScanned: state.pagesScanned + 1,
      phaseCounts,
      updatedAt: FieldValue.serverTimestamp(),
    };
    transaction.update(runRef, nextState);
    return publicStatus(runId, nextState);
  });
}

module.exports = {
  PAGE_SIZE,
  PHASES,
  createHistoryScan,
  advanceHistoryScan,
};

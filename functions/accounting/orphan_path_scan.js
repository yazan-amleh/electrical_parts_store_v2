'use strict';

// Tenant-path-scoped, read-only *collection group* census. A document nested
// below a deleted journal header remains queryable even when its embedded
// storeId is missing, so storeId-filtered queries cannot locate all orphans.
// Ordered __name__ traversal begins at the store document reference and
// ends at the first path outside its descendant prefix.
//
// One call reads at most PAGE_SIZE+1 group documents plus 40 journal header
// snapshots; the server-owned cursor makes progress resumable. This is a
// non-atomic historical audit, not a source-of-truth or certified snapshot.

const PAGE_SIZE = 40;
const MAX_GROUP_DOCUMENTS = 100000;
const SAMPLE_LIMIT = 20;
const VERSION = 1;

function abort(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}
function add(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    abort(HttpsError, 'Orphan census counter overflow.');
  }
  return a + b;
}
function isJournalLinePath(ref, storeId) {
  const path = ref.path.split('/');
  return path.length === 6 && path[0] === 'stores' &&
    path[1] === storeId && path[2] === 'journal_entries' &&
    Boolean(path[3]) && path[4] === 'lines' && Boolean(path[5]);
}
function validate(state, storeId, uid, HttpsError) {
  if (!state || state.schemaVersion !== VERSION ||
      state.storeId !== storeId || state.createdBy !== uid ||
      !['running', 'enumeration_complete', 'budget_exhausted']
        .includes(state.status) ||
      (state.cursorPath !== null &&
       (typeof state.cursorPath !== 'string' ||
        !state.cursorPath.startsWith('stores/' + storeId + '/') ||
        state.cursorPath.split('/').length % 2 !== 0 ||
        state.cursorPath.split('/').at(-2) !== 'lines')) ||
      !Number.isSafeInteger(state.groupDocumentsScanned) ||
      state.groupDocumentsScanned < 0 ||
      state.groupDocumentsScanned > MAX_GROUP_DOCUMENTS ||
      !Number.isSafeInteger(state.pagesScanned) ||
      state.pagesScanned < 0 ||
      !Number.isSafeInteger(state.journalLinesScanned) ||
      state.journalLinesScanned < 0 ||
      !Number.isSafeInteger(state.orphanLines) ||
      state.orphanLines < 0 ||
      !Number.isSafeInteger(state.orphansWithoutCorrectStoreId) ||
      state.orphansWithoutCorrectStoreId < 0 ||
      !Array.isArray(state.orphanSamples) ||
      state.orphanSamples.length > SAMPLE_LIMIT ||
      state.orphansWithoutCorrectStoreId > state.orphanLines ||
      state.orphanLines > state.journalLinesScanned ||
      state.journalLinesScanned > state.groupDocumentsScanned) {
    abort(HttpsError, 'Invalid path-based orphan census checkpoint.');
  }
}

function present(runId, state) {
  return {
    runId, storeId: state.storeId, status: state.status,
    scope: 'tenant_document_path_collection_group_lines',
    consistency: 'non_atomic', certified: false,
    accountingCutoffApplied: false,
    groupDocumentsScanned: state.groupDocumentsScanned,
    journalLinesScanned: state.journalLinesScanned,
    orphanLines: state.orphanLines,
    orphansWithoutCorrectStoreId: state.orphansWithoutCorrectStoreId,
    pagesScanned: state.pagesScanned,
    scanLimit: MAX_GROUP_DOCUMENTS,
    orphanSamples: [...state.orphanSamples],
  };
}

async function startPathOrphanScan({
  db, FieldValue, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const member = await store.collection('members').doc(uid).get();
  assertAccess(member, storeId);
  const ref = store.collection('accounting_orphan_path_runs').doc();
  const state = {
    schemaVersion: VERSION,
    storeId, createdBy: uid, status: 'running',
    cursorPath: null,
    groupDocumentsScanned: 0,
    pagesScanned: 0,
    journalLinesScanned: 0,
    orphanLines: 0,
    orphansWithoutCorrectStoreId: 0,
    orphanSamples: [],
    consistency: 'non_atomic', certified: false,
    accountingCutoffApplied: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.create(state);
  return present(ref.id, state);
}

async function advancePathOrphanScan({
  db, FieldValue, HttpsError, storeId, runId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const prefix = 'stores/' + storeId + '/';
  const run = store.collection('accounting_orphan_path_runs').doc(runId);
  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(uid));
    assertAccess(member, storeId);
    const record = await tx.get(run);
    if (!record.exists) {
      throw new HttpsError('not-found', 'Orphan census checkpoint not found.');
    }
    const state = record.data();
    if (state.storeId !== storeId || state.createdBy !== uid) {
      throw new HttpsError('permission-denied',
        'Orphan census belongs to another user or store.');
    }
    validate(state, storeId, uid, HttpsError);
    if (state.status !== 'running') return present(runId, state);

    const remaining = MAX_GROUP_DOCUMENTS - state.groupDocumentsScanned;
    if (remaining <= 0) {
      const bounded = {...state, status: 'budget_exhausted',
        updatedAt: FieldValue.serverTimestamp()};
      tx.update(run, bounded);
      return present(runId, bounded);
    }

    let query = db.collectionGroup('lines').orderBy('__name__');
    // __name__ is a full Firestore document reference for group queries.
    // Start at this store's document (not at an embedded, mutable storeId).
    query = state.cursorPath === null
      ? query.startAt(store)
      : query.startAfter(db.doc(state.cursorPath));
    const limit = Math.min(PAGE_SIZE, remaining);
    const page = await tx.get(query.limit(limit + 1));
    const visible = [];
    let crossedTenantEnd = false;
    for (const doc of page.docs) {
      if (!doc.ref.path.startsWith(prefix)) {
        crossedTenantEnd = true;
        break;
      }
      if (visible.length === limit) break;
      visible.push(doc);
    }

    const headers = new Map();
    for (const doc of visible) {
      if (!isJournalLinePath(doc.ref, storeId)) continue;
      const entryId = doc.ref.parent.parent.id;
      if (!headers.has(entryId)) {
        headers.set(entryId, await tx.get(
          store.collection('journal_entries').doc(entryId),
        ));
      }
    }
    let journals = state.journalLinesScanned;
    let orphans = state.orphanLines;
    let wrongId = state.orphansWithoutCorrectStoreId;
    const samples = [...state.orphanSamples];
    for (const doc of visible) {
      if (!isJournalLinePath(doc.ref, storeId)) continue;
      journals = add(journals, 1, HttpsError);
      const header = headers.get(doc.ref.parent.parent.id);
      if (header.exists) continue;
      orphans = add(orphans, 1, HttpsError);
      if (doc.data().storeId !== storeId) {
        wrongId = add(wrongId, 1, HttpsError);
      }
      if (samples.length < SAMPLE_LIMIT) {
        samples.push({
          linePath: doc.ref.path,
          embeddedStoreIdMatches: doc.data().storeId === storeId,
          code: 'ORPHAN_JOURNAL_LINE',
        });
      }
    }
    const scanned = add(
      state.groupDocumentsScanned, visible.length, HttpsError);
    const moreInStore = !crossedTenantEnd &&
      page.docs.length > visible.length;
    const complete = crossedTenantEnd || page.docs.length <= limit;
    const nextStatus = complete ? 'enumeration_complete'
      : scanned >= MAX_GROUP_DOCUMENTS ? 'budget_exhausted' : 'running';
    if (nextStatus === 'running' && (!moreInStore || visible.length === 0)) {
      abort(HttpsError, 'Orphan census pagination did not advance.');
    }
    const next = {
      ...state,
      status: nextStatus,
      cursorPath: visible.length > 0
        ? visible[visible.length - 1].ref.path : state.cursorPath,
      groupDocumentsScanned: scanned,
      journalLinesScanned: journals,
      orphanLines: orphans,
      orphansWithoutCorrectStoreId: wrongId,
      orphanSamples: samples,
      pagesScanned: add(state.pagesScanned, 1, HttpsError),
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(run, next);
    return present(runId, next);
  });
}

module.exports = {
  PAGE_SIZE, MAX_GROUP_DOCUMENTS, isJournalLinePath,
  validatePathRun: validate,
  startPathOrphanScan, advancePathOrphanScan,
};

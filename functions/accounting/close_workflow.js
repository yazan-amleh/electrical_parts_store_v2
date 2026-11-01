'use strict';

// Recoverable, bounded orchestration for the four source-read-only audits.
// Audit run checkpoints are already transactional and independently resumable.
const {controlRef, assertAuditsStartedAfterFreeze} =
  require('./period_close');
const {readPostingEpoch, epochsMatch} = require('./posting_epoch');
const {startLedgerReconciliation, advanceLedgerReconciliation} =
  require('./ledger_reconciliation');
const {startJournalHeaderReconciliation, advanceJournalHeaderReconciliation} =
  require('./journal_header_reconciliation');
const {startPathOrphanScan, advancePathOrphanScan} =
  require('./orphan_path_scan');
const {startBalanceProjectionScan, advanceBalanceProjectionScan} =
  require('./balance_projection_scan');

const STEPS = [
  {key: 'ledgerRunId', collection: 'accounting_ledger_runs',
    start: startLedgerReconciliation, advance: advanceLedgerReconciliation,
    complete: 'reconciliation_complete'},
  {key: 'journalRunId', collection: 'accounting_journal_runs',
    start: startJournalHeaderReconciliation,
    advance: advanceJournalHeaderReconciliation,
    complete: 'reconciliation_complete'},
  {key: 'orphanRunId', collection: 'accounting_orphan_path_runs',
    start: startPathOrphanScan, advance: advancePathOrphanScan,
    complete: 'enumeration_complete'},
  {key: 'balanceRunId', collection: 'accounting_balance_path_runs',
    start: startBalanceProjectionScan, advance: advanceBalanceProjectionScan,
    complete: 'enumeration_complete'},
];

function fail(HttpsError, code, message) {
  throw new HttpsError(code, message);
}
async function readAuthorizedState({
  db, HttpsError, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const member = await store.collection('members').doc(uid).get();
  assertAccess(member, storeId);
  const doc = await controlRef(store).get();
  return {store, state: doc.exists ? doc.data() : null};
}
function checkState(state, storeId, HttpsError) {
  if (state && (state.storeId !== storeId ||
      !['open', 'locked', 'closed'].includes(state.status))) {
    fail(HttpsError, 'failed-precondition',
      'Invalid accounting close control.');
  }
}
function locked(state, storeId, uid, HttpsError) {
  checkState(state, storeId, HttpsError);
  if (!state || state.status !== 'locked' || state.requestedBy !== uid) {
    fail(HttpsError, 'failed-precondition',
      'The requester must own an active accounting freeze.');
  }
}
function publicState(state, storeId) {
  return {
    storeId,
    status: state?.status || 'not_started',
    closeId: state?.closeId || null,
    throughDate: state?.throughDate || null,
    closedThroughDate: state?.closedThroughDate || null,
    auditRuns: state?.auditRuns || null,
    postingWritesBlocked: state?.status === 'locked' ||
      state?.status === 'closed',
    certified: false,
    immutableHistoricalSnapshot: false,
  };
}
async function getCloseState(args) {
  const {store, state} = await readAuthorizedState(args);
  checkState(state, store.id, args.HttpsError);
  return publicState(state, store.id);
}
async function startCloseAudits(args) {
  const {db, FieldValue, HttpsError, storeId, uid, assertAccess} = args;
  const {store, state} = await readAuthorizedState(args);
  locked(state, storeId, uid, HttpsError);
  if (state.auditRuns) return publicState(state, storeId);

  // If a request fails here, the independent audit checkpoints are
  // harmless read-only artifacts. Retrying may create fresh checkpoints;
  // the lock control keeps only one winning set of run IDs.
  const started = await Promise.all(STEPS.map((step) => step.start({
    db, FieldValue, HttpsError, storeId, uid, assertAccess,
  })));
  const runIds = Object.fromEntries(
    STEPS.map((step, i) => [step.key, started[i].runId]));
  return db.runTransaction(async (tx) => {
    assertAccess(await tx.get(store.collection('members').doc(uid)), storeId);
    const currentSnapshot = await tx.get(controlRef(store));
    if (!currentSnapshot.exists) {
      fail(HttpsError, 'failed-precondition', 'Accounting freeze disappeared.');
    }
    const current = currentSnapshot.data();
    locked(current, storeId, uid, HttpsError);
    if (current.closeId !== state.closeId) {
      fail(HttpsError, 'failed-precondition', 'Accounting freeze changed.');
    }
    if (current.auditRuns) return publicState(current, storeId);
    const docs = await Promise.all(STEPS.map((step) =>
      tx.get(store.collection(step.collection).doc(runIds[step.key]))));
    if (docs.some((doc) => !doc.exists)) {
      fail(HttpsError, 'failed-precondition', 'Audit startup was incomplete.');
    }
    const checkpoints = docs.map((doc) => doc.data());
    if (checkpoints.some((run) => run.storeId !== storeId ||
        run.createdBy !== uid)) {
      fail(HttpsError, 'permission-denied', 'Audit run owner mismatch.');
    }
    assertAuditsStartedAfterFreeze(checkpoints, current.frozenAt, HttpsError);
    const epoch = await readPostingEpoch(tx, store, HttpsError);
    if (!epochsMatch(current.frozenEpoch, epoch) ||
        checkpoints.some((run) =>
          !epochsMatch(run.postingEpoch, epoch))) {
      fail(HttpsError, 'failed-precondition',
        'Financial sources changed before audit runs were registered.');
    }
    tx.update(controlRef(store), {
      auditRuns: runIds,
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    return publicState({...current, auditRuns: runIds}, storeId);
  });
}

async function advanceCloseAudits(args) {
  const {db, FieldValue, HttpsError, storeId, uid, assertAccess} = args;
  const {store, state} = await readAuthorizedState(args);
  locked(state, storeId, uid, HttpsError);
  if (!state.auditRuns) {
    fail(HttpsError, 'failed-precondition',
      'Start the four accounting checks before advancing.');
  }
  const checkpoints = await Promise.all(STEPS.map((step) =>
    store.collection(step.collection).doc(state.auditRuns[step.key]).get()));
  if (checkpoints.some((doc) => !doc.exists)) {
    fail(HttpsError, 'failed-precondition', 'A registered audit is missing.');
  }
  const results = await Promise.all(STEPS.map(async (step, i) => {
    const doc = checkpoints[i].data();
    if (doc.storeId !== storeId || doc.createdBy !== uid) {
      fail(HttpsError, 'permission-denied', 'Audit owner mismatch.');
    }
    const status = doc.status === 'running'
      ? (await step.advance({db, FieldValue, HttpsError, storeId, uid,
        runId: state.auditRuns[step.key], assertAccess})).status
      : doc.status;
    return {name: step.key, runId: state.auditRuns[step.key],
      status, complete: status === step.complete};
  }));
  return {
    storeId, closeId: state.closeId,
    runIds: state.auditRuns, scans: results,
    complete: results.every((item) => item.complete),
    hasFailures: results.some((item) =>
      item.status !== 'running' && !item.complete),
    certified: false, immutableHistoricalSnapshot: false,
  };
}

module.exports = {getCloseState, startCloseAudits, advanceCloseAudits};

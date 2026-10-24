'use strict';

// Controlled freeze of all *instrumented* V2 financial write paths.
// This is an operational barrier, NOT a historical snapshot of legacy data.
const {readPostingEpoch, epochsMatch} = require('./posting_epoch');
const {checkComparable} = require('./audit_coverage');
const {verifyOrphanRun, verifyBalanceRun,
  buildUnifiedAuditReport} = require('./unified_audit_report');

const ID = /^[A-Za-z0-9_-]{1,128}$/;
const CLOSED_STATUSES = new Set(['locked', 'closed']);
const MAX_REASON = 400;

function fail(HttpsError, code, message) {
  throw new HttpsError(code, message);
}
function controlRef(store) {
  return store.collection('accounting_period_control').doc('current');
}

async function assertAccountingWritesOpen(tx, store, HttpsError) {
  const state = await tx.get(controlRef(store));
  if (!state.exists) return;
  const data = state.data();
  if (data.storeId !== store.id ||
      !['open', 'locked', 'closed'].includes(data.status)) {
    fail(HttpsError, 'failed-precondition',
      'Financial write control is invalid; posting blocked.');
  }
  if (CLOSED_STATUSES.has(data.status)) {
    fail(HttpsError, 'failed-precondition',
      'Accounting close is active; financial writes are blocked.');
  }
}

function parseIds(data, HttpsError) {
  if (!data || !ID.test(data.storeId || '')) {
    fail(HttpsError, 'invalid-argument', 'Invalid store ID.');
  }
  return data.storeId;
}
async function beginAccountingClose({
  db, FieldValue, HttpsError, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const ref = controlRef(store);
  return db.runTransaction(async (tx) => {
    assertAccess(await tx.get(store.collection('members').doc(uid)), storeId);
    const old = await tx.get(ref);
    if (old.exists && old.data().status !== 'open') {
      fail(HttpsError, 'failed-precondition',
        'An accounting close is already active.');
    }
    if (old.exists && old.data().storeId !== storeId) {
      fail(HttpsError, 'failed-precondition', 'Invalid close control tenant.');
    }
    // Read all epoch shards inside the *same* transaction as the freeze.
    const frozenEpoch = await readPostingEpoch(tx, store, HttpsError);
    const closeId = store.collection('accounting_close_events').doc().id;
    tx.set(ref, {
      storeId, status: 'locked', closeId,
      requestedBy: uid, frozenEpoch,
      frozenAt: FieldValue.serverTimestamp(),
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    tx.create(store.collection('accounting_close_events').doc(closeId), {
      storeId, kind: 'began', by: uid,
      postingEpoch: frozenEpoch,
      at: FieldValue.serverTimestamp(),
      certified: false,
    });
    return {
      storeId, closeId, status: 'locked',
      postingWritesBlocked: true, certified: false,
      immutableHistoricalSnapshot: false,
    };
  });
}

async function finalizeAccountingClose({
  db, FieldValue, HttpsError, storeId, uid,
  ledgerRunId, journalRunId, orphanRunId, balanceRunId, assertAccess,
}) {
  for (const value of [ledgerRunId, journalRunId,
    orphanRunId, balanceRunId]) {
    if (!ID.test(value || '')) {
      fail(HttpsError, 'invalid-argument', 'A valid audit run ID is required.');
    }
  }
  const store = db.collection('stores').doc(storeId);
  return db.runTransaction(async (tx) => {
    assertAccess(await tx.get(store.collection('members').doc(uid)), storeId);
    const control = await tx.get(controlRef(store));
    if (!control.exists || control.data().status !== 'locked' ||
        control.data().storeId !== storeId) {
      fail(HttpsError, 'failed-precondition',
        'An active accounting freeze must precede finalization.');
    }
    const state = control.data();
    const refs = [
      store.collection('accounting_ledger_runs').doc(ledgerRunId),
      store.collection('accounting_journal_runs').doc(journalRunId),
      store.collection('accounting_orphan_path_runs').doc(orphanRunId),
      store.collection('accounting_balance_path_runs').doc(balanceRunId),
    ];
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    if (snapshots.some((doc) => !doc.exists)) {
      fail(HttpsError, 'not-found', 'Accounting close evidence is missing.');
    }
    const [ledger, journal, orphan, balance] =
      snapshots.map((snapshot) => snapshot.data());
    checkComparable(ledger, journal, storeId, uid, HttpsError);
    verifyOrphanRun(orphan, storeId, uid, HttpsError);
    verifyBalanceRun(balance, storeId, uid, HttpsError);
    const currentEpoch = await readPostingEpoch(tx, store, HttpsError);
    if (!epochsMatch(currentEpoch, state.frozenEpoch)) {
      fail(HttpsError, 'failed-precondition',
        'Financial sources changed after the accounting freeze.');
    }
    const report = buildUnifiedAuditReport({
      storeId, ledgerRunId, journalRunId, orphanRunId, balanceRunId,
      ledger, journal, orphan, balance, currentPostingEpoch: currentEpoch,
    }, HttpsError);
    if (report.verdict !== 'observed_aggregates_agree_non_atomic' ||
        !report.complete || report.certified !== false ||
        report.checks.postingEpoch.postingChangesObserved) {
      fail(HttpsError, 'failed-precondition',
        'All four scans must agree without source changes before closing.');
    }
    // Store evidence IDs and status, not a claim of certified historical
    // balances. The write lock remains active after finalization.
    tx.update(controlRef(store), {
      status: 'closed',
      evidence: {ledgerRunId, journalRunId, orphanRunId, balanceRunId},
      closedAt: FieldValue.serverTimestamp(),
      closedBy: uid,
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    tx.create(store.collection('accounting_close_events')
      .doc(state.closeId + '-finalized'), {
      storeId, kind: 'finalized', closeId: state.closeId, by: uid,
      evidence: {ledgerRunId, journalRunId, orphanRunId, balanceRunId},
      postingEpoch: currentEpoch, certified: false,
      at: FieldValue.serverTimestamp(),
    });
    return {
      storeId, closeId: state.closeId, status: 'closed',
      postingWritesBlocked: true,
      reportVerdict: report.verdict,
      certified: false, immutableHistoricalSnapshot: false,
    };
  });
}

async function reopenAccountingClose({
  db, FieldValue, HttpsError, storeId, uid, reason, assertAccess,
}) {
  if (typeof reason !== 'string' ||
      reason.trim().length < 12 || reason.trim().length > MAX_REASON) {
    fail(HttpsError, 'invalid-argument',
      'Reopening requires a specific explanation of 12-400 characters.');
  }
  const store = db.collection('stores').doc(storeId);
  return db.runTransaction(async (tx) => {
    assertAccess(await tx.get(store.collection('members').doc(uid)), storeId);
    const current = await tx.get(controlRef(store));
    if (!current.exists || current.data().storeId !== storeId ||
        !CLOSED_STATUSES.has(current.data().status)) {
      fail(HttpsError, 'failed-precondition',
        'No active accounting freeze is available to reopen.');
    }
    const previous = current.data();
    const event = store.collection('accounting_close_events').doc();
    tx.create(event, {
      storeId, kind: 'reopened', closeId: previous.closeId,
      previousStatus: previous.status, reason: reason.trim(),
      by: uid, at: FieldValue.serverTimestamp(),
      certified: false,
    });
    tx.set(controlRef(store), {
      storeId, status: 'open',
      reopenedFromCloseId: previous.closeId,
      reopenedBy: uid,
      reason: reason.trim(),
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    return {storeId, status: 'open', postingWritesBlocked: false,
      previousCloseId: previous.closeId, certified: false};
  });
}

module.exports = {
  controlRef, assertAccountingWritesOpen, parseIds,
  beginAccountingClose, finalizeAccountingClose, reopenAccountingClose,
};

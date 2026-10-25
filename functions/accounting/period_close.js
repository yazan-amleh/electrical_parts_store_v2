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
const DAY = /^\d{4}-\d{2}-\d{2}$/;

function fail(HttpsError, code, message) {
  throw new HttpsError(code, message);
}
function controlRef(store) {
  return store.collection('accounting_period_control').doc('current');
}

function validCutoff(day) {
  if (typeof day !== 'string' || !DAY.test(day)) return false;
  const date = new Date(day + 'T00:00:00.000Z');
  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === day;
}
async function assertAccountingWritesOpen(tx, store, HttpsError,
    postingDate = null) {
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
  if (data.closedThroughDate != null) {
    if (!validCutoff(data.closedThroughDate)) {
      fail(HttpsError, 'failed-precondition',
        'Stored accounting cutoff date is invalid.');
    }
    if (postingDate != null) {
      if (!(postingDate instanceof Date) ||
          Number.isNaN(postingDate.getTime())) {
        fail(HttpsError, 'failed-precondition',
          'Posting date cannot be validated against the closed period.');
      }
      if (postingDate.toISOString().slice(0, 10) <= data.closedThroughDate) {
        fail(HttpsError, 'failed-precondition',
          'Posting date falls inside a previously closed accounting period.');
      }
    }
  }
}

// A posting epoch alone is insufficient proof that a scan was performed
// under this lock: an earlier full scan can have identical counters.
function compareTimestamps(left, right, HttpsError) {
  const valid = (value) => value &&
    Number.isSafeInteger(value.seconds) &&
    Number.isInteger(value.nanoseconds) &&
    value.nanoseconds >= 0 && value.nanoseconds < 1000000000;
  if (!valid(left) || !valid(right)) {
    fail(HttpsError, 'failed-precondition',
      'Missing or corrupt accounting freeze/audit timestamp.');
  }
  return left.seconds === right.seconds
    ? left.nanoseconds - right.nanoseconds
    : left.seconds - right.seconds;
}

function assertAuditsStartedAfterFreeze(runs, frozenAt, HttpsError) {
  for (const run of runs) {
    if (compareTimestamps(run.createdAt, frozenAt, HttpsError) <= 0) {
      fail(HttpsError, 'failed-precondition',
        'All four audit runs must start after the current accounting freeze.');
    }
  }
}

function parseIds(data, HttpsError) {
  if (!data || !ID.test(data.storeId || '')) {
    fail(HttpsError, 'invalid-argument', 'Invalid store ID.');
  }
  return data.storeId;
}
async function beginAccountingClose({
  db, FieldValue, HttpsError, storeId, uid, throughDate, assertAccess,
}) {
  if (!validCutoff(throughDate)) {
    fail(HttpsError, 'invalid-argument',
      'throughDate must be a valid UTC YYYY-MM-DD accounting date.');
  }
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
    const previousCutoff = old.exists ? old.data().closedThroughDate : null;
    if (previousCutoff != null &&
        (!validCutoff(previousCutoff) || throughDate <= previousCutoff)) {
      fail(HttpsError, 'failed-precondition',
        'The new cutoff must be after the previously closed period.');
    }
    // Read all epoch shards inside the *same* transaction as the freeze.
    const frozenEpoch = await readPostingEpoch(tx, store, HttpsError);
    const closeId = store.collection('accounting_close_events').doc().id;
    tx.set(ref, {
      storeId, status: 'locked', closeId, throughDate,
      closedThroughDate: previousCutoff,
      requestedBy: uid, frozenEpoch,
      frozenAt: FieldValue.serverTimestamp(),
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    tx.create(store.collection('accounting_close_events').doc(closeId), {
      storeId, kind: 'began', by: uid, throughDate,
      postingEpoch: frozenEpoch,
      at: FieldValue.serverTimestamp(),
      certified: false,
    });
    return {
      storeId, closeId, status: 'locked', throughDate,
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
    assertAuditsStartedAfterFreeze(
      [ledger, journal, orphan, balance], state.frozenAt, HttpsError);
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
      closedThroughDate: state.throughDate,
      evidence: {ledgerRunId, journalRunId, orphanRunId, balanceRunId},
      closedAt: FieldValue.serverTimestamp(),
      closedBy: uid,
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    tx.create(store.collection('accounting_close_events')
      .doc(state.closeId + '-finalized'), {
      storeId, kind: 'finalized', closeId: state.closeId, by: uid,
      throughDate: state.throughDate,
      evidence: {ledgerRunId, journalRunId, orphanRunId, balanceRunId},
      postingEpoch: currentEpoch, certified: false,
      at: FieldValue.serverTimestamp(),
    });
    return {
      storeId, closeId: state.closeId, status: 'closed',
      closedThroughDate: state.throughDate,
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
      closedThroughDate: previous.closedThroughDate || null,
      reopenedFromCloseId: previous.closeId,
      reopenedBy: uid,
      reason: reason.trim(),
      lastChangedAt: FieldValue.serverTimestamp(),
    });
    return {storeId, status: 'open', postingWritesBlocked: false,
      closedThroughDate: previous.closedThroughDate || null,
      previousCloseId: previous.closeId, certified: false};
  });
}

module.exports = {
  compareTimestamps, assertAuditsStartedAfterFreeze,
  controlRef, assertAccountingWritesOpen, parseIds,
  beginAccountingClose, finalizeAccountingClose, reopenAccountingClose,
};

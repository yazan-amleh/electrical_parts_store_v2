'use strict';

// Checkpointed, read-only journal-header-to-lines reconciliation.
// This evidence is non-atomic across pages, is NOT a historical cutoff,
// and must never certify a complete ledger or balance sheet.

const {
  readPostingEpoch,
  validateEpoch,
  epochsMatch,
} = require('./posting_epoch');

const {
  validateJournalCoverage,
  appendJournalCoverage,
} = require('./audit_coverage');

const PAGE_SIZE = 40;
const MAX_SAMPLE_ISSUES = 20;
// Version 3 adds per-currency evidence to durable account-reference/index counters.
// Older partially scanned checkpoints cannot safely be upgraded mid-run.
const VERSION = 4;

function validAccountId(value) {
  return typeof value === 'string' &&
    /^[A-Za-z0-9_-]{1,128}$/.test(value);
}

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function safeAdd(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Historical journal audit integer overflow.');
  }
  return a + b;
}

function headerRevision(snapshot) {
  const stamp = snapshot.updateTime;
  // Compare nanosecond precision when available; a different header revision
  // aborts the run instead of reconciling lines against mixed header versions.
  return stamp ? String(stamp.seconds) + ':' +
    String(stamp.nanoseconds) : null;
}

function validateState(state, storeId, uid, HttpsError) {
  if (!state || state.schemaVersion !== VERSION ||
      state.storeId !== storeId || state.createdBy !== uid ||
      !['running', 'reconciliation_complete', 'source_changed']
        .includes(state.status) ||
      (state.lastEntryId !== null &&
       (typeof state.lastEntryId !== 'string' || !state.lastEntryId)) ||
      (state.activeEntryId !== null &&
       (typeof state.activeEntryId !== 'string' || !state.activeEntryId)) ||
      (state.lineCursor !== null &&
       (typeof state.lineCursor !== 'string' ||
        !state.lineCursor || state.lineCursor.includes('/'))) ||
      (state.activeEntryId === null &&
       (state.lineCursor !== null || state.headerRevision !== null)) ||
      (state.activeEntryId !== null && state.lastEntryId ===
        state.activeEntryId) ||
      (state.headerRevision !== null &&
       (typeof state.headerRevision !== 'string' ||
        !/^\d+:\d+$/.test(state.headerRevision))) ||
      !Number.isSafeInteger(state.debit) || state.debit < 0 ||
      !Number.isSafeInteger(state.credit) || state.credit < 0 ||
      !Number.isSafeInteger(state.activeLineCount) ||
      state.activeLineCount < 0 ||
      !Number.isSafeInteger(state.activeIssueCount) ||
      state.activeIssueCount < 0 ||
      !Number.isSafeInteger(state.entriesChecked) ||
      state.entriesChecked < 0 ||
      !Number.isSafeInteger(state.linesChecked) || state.linesChecked < 0 ||
      !Number.isSafeInteger(state.pagesChecked) || state.pagesChecked < 0 ||
      !Number.isSafeInteger(state.failedEntries) || state.failedEntries < 0 ||
      !Number.isSafeInteger(state.invalidAccountReferenceLines) ||
      state.invalidAccountReferenceLines < 0 ||
      !Number.isSafeInteger(state.potentiallyUnindexedLines) ||
      state.potentiallyUnindexedLines < 0 ||
      state.potentiallyUnindexedLines > state.linesChecked ||
      state.invalidAccountReferenceLines > state.linesChecked ||
      !Array.isArray(state.activeIssueSamples) ||
      state.activeIssueSamples.length > MAX_SAMPLE_ISSUES ||
      (state.status === 'reconciliation_complete' &&
       state.activeEntryId !== null)) {
    fail(HttpsError, 'Invalid persisted journal audit checkpoint.');
  }
  validateJournalCoverage(state, HttpsError);
  validateEpoch(state.postingEpoch, HttpsError);
}

function publicStatus(runId, state) {
  return {
    runId,
    storeId: state.storeId,
    status: state.status,
    scope: 'existing_journal_headers_and_direct_lines',
    consistency: 'non_atomic',
    certified: false,
    accountingCutoffApplied: false,
    entriesChecked: state.entriesChecked,
    linesChecked: state.linesChecked,
    pagesChecked: state.pagesChecked,
    failedEntries: state.failedEntries,
    invalidAccountReferenceLines: state.invalidAccountReferenceLines,
    potentiallyUnindexedLines: state.potentiallyUnindexedLines,
    unclassifiedJournalEntries: state.unclassifiedJournalEntries,
    journalCurrencyTotals: {...state.journalCurrencyTotals},
    activeEntryId: state.activeEntryId,
  };
}

async function startJournalHeaderReconciliation({
  db, FieldValue, HttpsError, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const member = await store.collection('members').doc(uid).get();
  assertAccess(member, storeId);
  const postingEpoch = await readPostingEpoch(db, store, HttpsError);
  const ref = store.collection('accounting_journal_runs').doc();
  const state = {
    schemaVersion: VERSION,
    postingEpoch,
    storeId,
    createdBy: uid,
    status: 'running',
    lastEntryId: null,
    activeEntryId: null,
    headerRevision: null,
    lineCursor: null,
    debit: 0,
    credit: 0,
    activeLineCount: 0,
    activeIssueCount: 0,
    activeIssueSamples: [],
    entriesChecked: 0,
    linesChecked: 0,
    pagesChecked: 0,
    failedEntries: 0,
    invalidAccountReferenceLines: 0,
    potentiallyUnindexedLines: 0,
    unclassifiedJournalEntries: 0,
    journalCurrencyTotals: {},
    scope: 'existing_journal_headers_and_direct_lines',
    consistency: 'non_atomic',
    certified: false,
    accountingCutoffApplied: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await ref.create(state);
  return publicStatus(ref.id, state);
}

async function advanceJournalHeaderReconciliation({
  db, FieldValue, HttpsError, storeId, uid, runId, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const runRef = store.collection('accounting_journal_runs').doc(runId);

  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(uid));
    assertAccess(member, storeId);
    const run = await tx.get(runRef);
    if (!run.exists) {
      throw new HttpsError('not-found', 'Journal audit run not found.');
    }
    const state = run.data();
    if (state.storeId !== storeId || state.createdBy !== uid) {
      throw new HttpsError('permission-denied',
        'Journal audit run belongs to another user or store.');
    }
    validateState(state, storeId, uid, HttpsError);
    if (state.status !== 'running') {
      return publicStatus(runId, state);
    }
    const currentPostingEpoch = await readPostingEpoch(
      tx, store, HttpsError,
    );
    if (!epochsMatch(currentPostingEpoch, state.postingEpoch)) {
      const changed = {
        ...state, status: 'source_changed',
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.update(runRef, changed);
      return publicStatus(runId, changed);
    }

    let entryId = state.activeEntryId;
    if (entryId === null) {
      let query = store.collection('journal_entries')
        .orderBy('__name__').limit(1);
      if (state.lastEntryId !== null) {
        query = query.startAfter(state.lastEntryId);
      }
      const next = await tx.get(query);
      if (next.empty) {
        const finished = {
          ...state,
          status: 'reconciliation_complete',
          updatedAt: FieldValue.serverTimestamp(),
        };
        tx.update(runRef, finished);
        return publicStatus(runId, finished);
      }
      entryId = next.docs[0].id;
    }

    const headerRef = store.collection('journal_entries').doc(entryId);
    const header = await tx.get(headerRef);
    const revision = header.exists ? headerRevision(header) : null;
    if (!header.exists ||
        (state.activeEntryId !== null &&
         revision !== state.headerRevision)) {
      // A deleted/modified header invalidates evidence already accumulated.
      // This does not attempt to repair, infer or silently restart the audit.
      const stale = {
        ...state, status: 'source_changed',
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.update(runRef, stale);
      return publicStatus(runId, stale);
    }

    let linesQuery = headerRef.collection('lines').orderBy('__name__')
      .limit(PAGE_SIZE + 1);
    if (state.lineCursor !== null) {
      linesQuery = linesQuery.startAfter(state.lineCursor);
    }
    const page = await tx.get(linesQuery);
    const lines = page.docs.slice(0, PAGE_SIZE);
    const hasMore = page.docs.length > PAGE_SIZE;

    // Traverse the actual journal subcollection, including records absent
    // from indexed storeId/accountId lookups. Resolve each distinct chart
    // account in the same transaction, bounded to this page's 40 lines.
    const chartAccounts = new Map();
    for (const line of lines) {
      const accountId = line.data().accountId;
      if (validAccountId(accountId) && !chartAccounts.has(accountId)) {
        chartAccounts.set(accountId, await tx.get(
          store.collection('accounts').doc(accountId),
        ));
      }
    }

    let invalidAccountReferenceLines = 0;
    let potentiallyUnindexedLines = 0;
    let debit = state.activeEntryId === null ? 0 : state.debit;
    let credit = state.activeEntryId === null ? 0 : state.credit;
    let lineCount = state.activeEntryId === null
      ? 0 : state.activeLineCount;
    let issueCount = state.activeEntryId === null
      ? 0 : state.activeIssueCount;
    const samples = state.activeEntryId === null
      ? [] : [...state.activeIssueSamples];
    const issue = (code, referenceId) => {
      issueCount = safeAdd(issueCount, 1, HttpsError);
      if (samples.length < MAX_SAMPLE_ISSUES) {
        samples.push({code, referenceId});
      }
    };
    const data = header.data();
    for (const doc of lines) {
      lineCount = safeAdd(lineCount, 1, HttpsError);
      const row = doc.data();
      const accountIdValid = validAccountId(row.accountId);
      const accountSnapshot = accountIdValid
        ? chartAccounts.get(row.accountId) : null;
      let accountReferenceInvalid = false;
      let potentiallyUnindexed = row.storeId !== storeId;

      if (row.storeId !== storeId || row.entryId !== entryId ||
          !accountIdValid) {
        issue('JOURNAL_LINE_IDENTITY_INVALID', doc.ref.path);
      }
      if (!accountIdValid) {
        issue('JOURNAL_LINE_ACCOUNT_ID_INVALID', doc.ref.path);
        accountReferenceInvalid = true;
        potentiallyUnindexed = true;
      } else if (!accountSnapshot || !accountSnapshot.exists) {
        issue('JOURNAL_LINE_ACCOUNT_MISSING', doc.ref.path);
        accountReferenceInvalid = true;
        potentiallyUnindexed = true;
      } else {
        const account = accountSnapshot.data();
        if (account.storeId !== storeId) {
          issue('JOURNAL_LINE_ACCOUNT_STORE_MISMATCH', doc.ref.path);
          accountReferenceInvalid = true;
        }
        if (account.isHeader === true) {
          issue('JOURNAL_LINE_ACCOUNT_NON_POSTING', doc.ref.path);
          accountReferenceInvalid = true;
        }
        if (account.currency !== row.currency ||
            account.currency !== data.currency) {
          issue('JOURNAL_LINE_ACCOUNT_CURRENCY_MISMATCH', doc.ref.path);
          accountReferenceInvalid = true;
        }
      }
      if (accountReferenceInvalid) {
        invalidAccountReferenceLines = safeAdd(
          invalidAccountReferenceLines, 1, HttpsError,
        );
      }
      if (potentiallyUnindexed) {
        potentiallyUnindexedLines = safeAdd(
          potentiallyUnindexedLines, 1, HttpsError,
        );
      }
      if (row.currency !== data.currency) {
        issue('JOURNAL_LINE_CURRENCY_MISMATCH', doc.ref.path);
      }
      const d = row.debitMinorUnits;
      const c = row.creditMinorUnits;
      if (!Number.isSafeInteger(d) || d < 0 ||
          !Number.isSafeInteger(c) || c < 0 ||
          ((d === 0) === (c === 0))) {
        issue('JOURNAL_LINE_MONEY_INVALID', doc.ref.path);
        continue;
      }
      debit = safeAdd(debit, d, HttpsError);
      credit = safeAdd(credit, c, HttpsError);
    }

    const linesChecked = safeAdd(state.linesChecked, lines.length, HttpsError);
    const pagesChecked = safeAdd(state.pagesChecked, 1, HttpsError);
    const accountReferenceCount = safeAdd(
      state.invalidAccountReferenceLines,
      invalidAccountReferenceLines, HttpsError,
    );
    const indexCoverageCount = safeAdd(
      state.potentiallyUnindexedLines, potentiallyUnindexedLines, HttpsError,
    );
    if (hasMore) {
      const progress = {
        ...state,
        activeEntryId: entryId,
        headerRevision: revision,
        lineCursor: lines[lines.length - 1].id,
        debit, credit, activeLineCount: lineCount,
        activeIssueCount: issueCount, activeIssueSamples: samples,
        linesChecked, pagesChecked,
        invalidAccountReferenceLines: accountReferenceCount,
        potentiallyUnindexedLines: indexCoverageCount,
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.update(runRef, progress);
      return publicStatus(runId, progress);
    }

    if (data.storeId !== storeId || data.status !== 'posted' ||
        typeof data.currency !== 'string' || !data.currency.trim()) {
      issue('JOURNAL_HEADER_IDENTITY_INVALID', entryId);
    }
    if (lineCount === 0) {
      issue('JOURNAL_LINES_MISSING', entryId);
    }
    if (!Number.isSafeInteger(data.totalDebitMinorUnits) ||
        data.totalDebitMinorUnits < 0 ||
        !Number.isSafeInteger(data.totalCreditMinorUnits) ||
        data.totalCreditMinorUnits < 0) {
      issue('JOURNAL_HEADER_TOTAL_INVALID', entryId);
    } else {
      if (data.totalDebitMinorUnits !== debit) {
        issue('JOURNAL_HEADER_DEBIT_MISMATCH', entryId);
      }
      if (data.totalCreditMinorUnits !== credit) {
        issue('JOURNAL_HEADER_CREDIT_MISMATCH', entryId);
      }
    }
    if (debit !== credit || debit === 0) {
      issue('JOURNAL_ENTRY_NOT_BALANCED', entryId);
    }
    const matched = issueCount === 0;
    const coverage = appendJournalCoverage(
      state, {currency: data.currency, lineCount, debit, credit, matched},
      HttpsError,
    );
    tx.create(runRef.collection('entry_results').doc(entryId), {
      storeId, entryId,
      currency: data.currency || null,
      matched,
      debitMinorUnits: debit,
      creditMinorUnits: credit,
      linesChecked: lineCount,
      issueCount,
      issueSamples: samples,
      headerRevision: revision,
      consistency: 'non_atomic',
      certified: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const progress = {
      ...state,
      activeEntryId: null,
      lastEntryId: entryId,
      headerRevision: null,
      lineCursor: null,
      debit: 0,
      credit: 0,
      activeLineCount: 0,
      activeIssueCount: 0,
      activeIssueSamples: [],
      entriesChecked: safeAdd(state.entriesChecked, 1, HttpsError),
      failedEntries: safeAdd(
        state.failedEntries, matched ? 0 : 1, HttpsError),
      linesChecked, pagesChecked,
      invalidAccountReferenceLines: accountReferenceCount,
      potentiallyUnindexedLines: indexCoverageCount,
      ...coverage,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(runRef, progress);
    return publicStatus(runId, progress);
  });
}

module.exports = {
  PAGE_SIZE,
  startJournalHeaderReconciliation,
  advanceJournalHeaderReconciliation,
};

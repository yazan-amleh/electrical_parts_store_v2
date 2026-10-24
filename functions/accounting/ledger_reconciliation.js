'use strict';

// Read-only accounting ledger reconciliation evidence. Checkpoints and
// per-account results are server-owned; source finance documents never change.
// No per-call limit on history: one bounded page per invocation, with progress
// stored transactionally. Non-atomic across invocations: never certify balances.

const {
  validateTrialBalance,
  appendAccountToTrialBalance,
  trialBalanceSummary,
} = require('./trial_balance');

const PAGE_SIZE = 40;
const ISSUE_SAMPLE_LIMIT = 20;
// Reject checkpoints from the pre-trial-balance format rather than derive
// false aggregates from an already partially scanned history.
const SCHEMA_VERSION = 2;

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function documentRevision(snapshot) {
  const time = snapshot.exists ? snapshot.updateTime : null;
  return time ? String(time.seconds) + ':' +
    String(time.nanoseconds) : null;
}

function checkedAdd(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Accounting ledger reconciliation amount overflow.');
  }
  return a + b;
}

function validateState(state, storeId, uid, HttpsError) {
  if (!state || state.schemaVersion !== SCHEMA_VERSION ||
      state.storeId !== storeId || state.createdBy !== uid ||
      !['running', 'reconciliation_complete', 'source_changed']
        .includes(state.status) ||
      (state.lastAccountId !== null &&
       (typeof state.lastAccountId !== 'string' || !state.lastAccountId)) ||
      (state.activeAccountId !== null &&
       (typeof state.activeAccountId !== 'string' || !state.activeAccountId)) ||
      (state.lineCursorPath !== null &&
       (typeof state.lineCursorPath !== 'string' ||
        state.lineCursorPath.split('/').length % 2 !== 0 ||
        state.lineCursorPath.split('/').length < 2 ||
        state.lineCursorPath.split('/').at(-2) !== 'lines' ||
        state.lineCursorPath.split('/').some((segment) => !segment))) ||
      (state.activeAccountId === null &&
       (state.lineCursorPath !== null ||
        state.activeAccountRevision !== null ||
        state.activeBalanceRevision !== null)) ||
      (state.activeAccountId !== null &&
       (state.lastAccountId === state.activeAccountId ||
        typeof state.activeAccountRevision !== 'string' ||
        !/^\d+:\d+$/.test(state.activeAccountRevision))) ||
      (state.activeBalanceRevision !== null &&
       (typeof state.activeBalanceRevision !== 'string' ||
        !/^\d+:\d+$/.test(state.activeBalanceRevision))) ||
      !Number.isSafeInteger(state.accountsCompared) ||
      state.accountsCompared < 0 ||
      !Number.isSafeInteger(state.linesScanned) || state.linesScanned < 0 ||
      !Number.isSafeInteger(state.pagesScanned) || state.pagesScanned < 0 ||
      !Number.isSafeInteger(state.mismatchCount) || state.mismatchCount < 0 ||
      !Number.isSafeInteger(state.runningDebit) || state.runningDebit < 0 ||
      !Number.isSafeInteger(state.runningCredit) || state.runningCredit < 0 ||
      !Number.isSafeInteger(state.activeLines) || state.activeLines < 0 ||
      !Number.isSafeInteger(state.activeIssueCount) ||
      state.activeIssueCount < 0 ||
      !Array.isArray(state.activeIssueSamples) ||
      state.activeIssueSamples.length > ISSUE_SAMPLE_LIMIT ||
      (state.status === 'reconciliation_complete' &&
       state.activeAccountId !== null)) {
    fail(HttpsError, 'Invalid accounting ledger reconciliation checkpoint.');
  }
  validateTrialBalance(state, HttpsError);
}

function status(runId, state) {
  return {
    runId,
    storeId: state.storeId,
    status: state.status,
    scope: 'known_chart_accounts_indexed_ledger_lines',
    consistency: 'non_atomic',
    certified: false,
    accountsCompared: state.accountsCompared,
    indexedDocumentsScanned: state.linesScanned,
    pagesScanned: state.pagesScanned,
    mismatchedAccounts: state.mismatchCount,
    activeAccountId: state.activeAccountId,
    accountingCutoffApplied: false,
    trialBalance: trialBalanceSummary(state),
  };
}

function journalPath(lineRef, storeId) {
  const parts = lineRef.path.split('/');
  return parts.length === 6 && parts[0] === 'stores' &&
    parts[1] === storeId && parts[2] === 'journal_entries' &&
    parts[3] && parts[4] === 'lines' && parts[5]
    ? parts[3] : null;
}

async function startLedgerReconciliation({
  db, FieldValue, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const member = await store.collection('members').doc(uid).get();
  assertAccess(member, storeId);
  const runRef = store.collection('accounting_ledger_runs').doc();
  const state = {
    schemaVersion: SCHEMA_VERSION,
    storeId,
    createdBy: uid,
    status: 'running',
    lastAccountId: null,
    activeAccountId: null,
    lineCursorPath: null,
    activeAccountRevision: null,
    activeBalanceRevision: null,
    runningDebit: 0,
    runningCredit: 0,
    activeLines: 0,
    activeIssueCount: 0,
    activeIssueSamples: [],
    accountsCompared: 0,
    linesScanned: 0,
    pagesScanned: 0,
    mismatchCount: 0,
    postingAccountsCompared: 0,
    unclassifiedPostingAccounts: 0,
    trialBalanceByCurrency: {},
    scope: 'known_chart_accounts_indexed_ledger_lines',
    consistency: 'non_atomic',
    certified: false,
    accountingCutoffApplied: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await runRef.create(state);
  return status(runRef.id, state);
}

async function advanceLedgerReconciliation({
  db, FieldValue, HttpsError, storeId, uid, runId, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const runRef = store.collection('accounting_ledger_runs').doc(runId);

  return db.runTransaction(async (tx) => {
    const member = await tx.get(store.collection('members').doc(uid));
    assertAccess(member, storeId);
    const run = await tx.get(runRef);
    if (!run.exists) {
      throw new HttpsError('not-found', 'Ledger reconciliation run not found.');
    }
    const state = run.data();
    if (state.storeId !== storeId || state.createdBy !== uid) {
      throw new HttpsError('permission-denied',
        'Ledger reconciliation run is owned by another user or store.');
    }
    validateState(state, storeId, uid, HttpsError);
    if (state.status !== 'running') {
      return status(runId, state);
    }

    let accountId = state.activeAccountId;
    if (accountId === null) {
      let accountQuery = store.collection('accounts')
        .orderBy('__name__').limit(1);
      if (state.lastAccountId !== null) {
        accountQuery = accountQuery.startAfter(state.lastAccountId);
      }
      const nextAccount = await tx.get(accountQuery);
      if (nextAccount.empty) {
        const finished = {
          ...state, status: 'reconciliation_complete',
          updatedAt: FieldValue.serverTimestamp(),
        };
        tx.update(runRef, finished);
        return status(runId, finished);
      }
      accountId = nextAccount.docs[0].id;
    }

    const accountRef = store.collection('accounts').doc(accountId);
    const balanceRef = store.collection('account_balances').doc(accountId);
    const [accountSnapshot, balanceSnapshot] = await Promise.all([
      tx.get(accountRef), tx.get(balanceRef),
    ]);
    if (!accountSnapshot.exists) {
      fail(HttpsError, 'An account disappeared during reconciliation.');
    }
    const currentAccountRevision = documentRevision(accountSnapshot);
    const currentBalanceRevision = documentRevision(balanceSnapshot);
    if (!currentAccountRevision) {
      fail(HttpsError, 'Account source revision is unavailable.');
    }
    if (state.activeAccountId !== null &&
        (currentAccountRevision !== state.activeAccountRevision ||
         currentBalanceRevision !== state.activeBalanceRevision)) {
      // Previously counted pages cannot be reliably reconciled against a
      // revised account or stored balance. Fail closed, never certify.
      const changed = {
        ...state, status: 'source_changed',
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.update(runRef, changed);
      return status(runId, changed);
    }
    const account = accountSnapshot.data();
    let query = db.collectionGroup('lines')
      .where('storeId', '==', storeId)
      .where('accountId', '==', accountId)
      .orderBy('__name__').limit(PAGE_SIZE + 1);
    if (state.lineCursorPath !== null) {
      // Collection-group names are not unique by leaf document ID.
      // A full absolute reference path preserves a stable pagination cursor.
      query = query.startAfter(db.doc(state.lineCursorPath));
    }
    const page = await tx.get(query);
    const batch = page.docs.slice(0, PAGE_SIZE);
    const more = page.docs.length > PAGE_SIZE;

    let debit = state.activeAccountId === null ? 0 : state.runningDebit;
    let credit = state.activeAccountId === null ? 0 : state.runningCredit;
    let acceptedLines = state.activeAccountId === null ? 0 : state.activeLines;
    let issueCount = state.activeAccountId === null
      ? 0 : state.activeIssueCount;
    const samples = state.activeAccountId === null
      ? [] : [...state.activeIssueSamples];
    const addIssue = (code, referenceId) => {
      issueCount = checkedAdd(issueCount, 1, HttpsError);
      if (samples.length < ISSUE_SAMPLE_LIMIT) {
        samples.push({code, referenceId});
      }
    };

    // Read every distinct source journal header in this bounded page.
    // Invoice lines from the same collection group are not ledger entries.
    const journalIds = new Set();
    for (const doc of batch) {
      const entryId = journalPath(doc.ref, storeId);
      if (entryId) journalIds.add(entryId);
    }
    const headers = new Map();
    for (const entryId of journalIds) {
      const snap = await tx.get(store.collection('journal_entries').doc(entryId));
      headers.set(entryId, snap);
    }

    for (const doc of batch) {
      const entryId = journalPath(doc.ref, storeId);
      if (!entryId) continue;
      acceptedLines = checkedAdd(acceptedLines, 1, HttpsError);
      const line = doc.data();
      const header = headers.get(entryId);
      if (!header.exists) {
        addIssue('LEDGER_LINE_PARENT_MISSING', doc.ref.path);
      } else {
        const h = header.data();
        if (h.storeId !== storeId || h.status !== 'posted') {
          addIssue('LEDGER_PARENT_NOT_POSTED_OR_WRONG_STORE', doc.ref.path);
        }
        if (h.currency !== account.currency) {
          addIssue('LEDGER_HEADER_CURRENCY_MISMATCH', doc.ref.path);
        }
      }
      if (line.entryId !== entryId || line.storeId !== storeId ||
          line.accountId !== accountId) {
        addIssue('LEDGER_LINE_IDENTITY_MISMATCH', doc.ref.path);
      }
      if (line.currency !== account.currency) {
        addIssue('LEDGER_LINE_CURRENCY_MISMATCH', doc.ref.path);
      }
      const d = line.debitMinorUnits;
      const c = line.creditMinorUnits;
      if (!Number.isSafeInteger(d) || d < 0 ||
          !Number.isSafeInteger(c) || c < 0 ||
          ((d === 0) === (c === 0))) {
        addIssue('LEDGER_LINE_MONEY_INVALID', doc.ref.path);
        continue;
      }
      debit = checkedAdd(debit, d, HttpsError);
      credit = checkedAdd(credit, c, HttpsError);
    }

    const scanned = checkedAdd(state.linesScanned, batch.length, HttpsError);
    const pages = checkedAdd(state.pagesScanned, 1, HttpsError);
    if (more) {
      const nextState = {
        ...state,
        activeAccountId: accountId,
        lineCursorPath: batch[batch.length - 1].ref.path,
        activeAccountRevision: currentAccountRevision,
        activeBalanceRevision: currentBalanceRevision,
        runningDebit: debit,
        runningCredit: credit,
        activeLines: acceptedLines,
        activeIssueCount: issueCount,
        activeIssueSamples: samples,
        linesScanned: scanned,
        pagesScanned: pages,
        updatedAt: FieldValue.serverTimestamp(),
      };
      tx.update(runRef, nextState);
      return status(runId, nextState);
    }

    // Final page of this account: only numeric evidence is compared.
    // Invalid metadata or journal lines always prevents 'matched'.
    const balance = balanceSnapshot.exists ? balanceSnapshot.data() : null;
    if (account.storeId !== storeId ||
        typeof account.currency !== 'string' || !account.currency.trim()) {
      addIssue('LEDGER_ACCOUNT_INVALID', accountId);
    }
    // Header accounts are non-posting chart nodes: no projection or lines
    // is the expected healthy state. Direct postings to headers are errors.
    if (account.isHeader === true) {
      if (acceptedLines > 0) {
        addIssue('LEDGER_HEADER_ACCOUNT_HAS_LINES', accountId);
      }
      if (balance) {
        addIssue('LEDGER_HEADER_ACCOUNT_HAS_BALANCE', accountId);
      }
    }
    if (!balance) {
      if (debit !== 0 || credit !== 0) {
        addIssue('LEDGER_PROJECTION_MISSING', accountId);
      }
    } else {
      if (balance.storeId !== storeId ||
          balance.accountId !== accountId ||
          balance.currency !== account.currency) {
        addIssue('LEDGER_PROJECTION_IDENTITY_MISMATCH', accountId);
      }
      const balanceDebit = balance.debitMinorUnits;
      const balanceCredit = balance.creditMinorUnits;
      const balanceNet = balance.balanceMinorUnits;
      if (!Number.isSafeInteger(balanceDebit) || balanceDebit < 0 ||
          !Number.isSafeInteger(balanceCredit) || balanceCredit < 0 ||
          !Number.isSafeInteger(balanceNet)) {
        addIssue('LEDGER_PROJECTION_MONEY_INVALID', accountId);
      } else if (balanceDebit !== debit || balanceCredit !== credit ||
          balanceNet !== checkedAdd(debit, -credit, HttpsError)) {
        addIssue('LEDGER_PROJECTION_TOTAL_MISMATCH', accountId);
      }
    }

    const matches = issueCount === 0;
    const trialBalance = appendAccountToTrialBalance(
      state, {storeId, account, debit, credit, matched: matches}, HttpsError,
    );
    const resultRef = runRef.collection('account_results').doc(accountId);
    tx.create(resultRef, {
      storeId, accountId, currency: account.currency || null,
      indexedDocumentsScanned: acceptedLines,
      debitMinorUnits: debit, creditMinorUnits: credit,
      matched: matches,
      issueCount,
      issueSamples: samples,
      consistency: 'non_atomic',
      certified: false,
      updatedAt: FieldValue.serverTimestamp(),
    });
    const nextState = {
      ...state,
      activeAccountId: null,
      lastAccountId: accountId,
      lineCursorPath: null,
      activeAccountRevision: null,
      activeBalanceRevision: null,
      runningDebit: 0,
      runningCredit: 0,
      activeLines: 0,
      activeIssueCount: 0,
      activeIssueSamples: [],
      accountsCompared: checkedAdd(state.accountsCompared, 1, HttpsError),
      mismatchCount: checkedAdd(state.mismatchCount, matches ? 0 : 1, HttpsError),
      ...trialBalance,
      linesScanned: scanned,
      pagesScanned: pages,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(runRef, nextState);
    return status(runId, nextState);
  });
}

module.exports = {
  PAGE_SIZE,
  startLedgerReconciliation,
  advanceLedgerReconciliation,
};

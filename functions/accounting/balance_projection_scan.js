'use strict';

// Reverse census of stored GL projections, independent of the chart-driven
// indexed-line reconciliation. Read-only source; checkpoints server-owned.
// Non-atomic across pages; NEVER certify an accounting cutoff.

const {
  readPostingEpoch,
  validateEpoch,
  epochsMatch,
} = require('./posting_epoch');

const {
  validateBalanceTotals,
  addStoredBalance,
} = require('./balance_currency_coverage');

const PAGE_SIZE = 40;
const MAX_ISSUE_SAMPLES = 20;
// Older partial checkpoints lack totals: reject instead of silently
// reconstructing misleading evidence after some pages were already read.
const VERSION = 3;

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}
function add(a, b, HttpsError) {
  if (!Number.isSafeInteger(a) || !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(HttpsError, 'Reverse balance audit integer overflow.');
  }
  return a + b;
}
function validState(state, storeId, uid, HttpsError) {
  if (!state || state.schemaVersion !== VERSION ||
      state.storeId !== storeId || state.createdBy !== uid ||
      !['running', 'enumeration_complete', 'source_changed'].includes(state.status) ||
      (state.cursorId !== null &&
       (typeof state.cursorId !== 'string' ||
        !/^[^/]+$/.test(state.cursorId))) ||
      !Number.isSafeInteger(state.balancesChecked) ||
      state.balancesChecked < 0 ||
      !Number.isSafeInteger(state.pagesChecked) ||
      state.pagesChecked < 0 ||
      !Number.isSafeInteger(state.invalidBalanceDocuments) ||
      state.invalidBalanceDocuments < 0 ||
      !Number.isSafeInteger(state.missingChartAccounts) ||
      state.missingChartAccounts < 0 ||
      !Number.isSafeInteger(state.headerAccountsWithBalance) ||
      state.headerAccountsWithBalance < 0 ||
      !Number.isSafeInteger(state.currencyMismatchBalances) ||
      state.currencyMismatchBalances < 0 ||
      !Number.isSafeInteger(state.invalidMoneyBalances) ||
      state.invalidMoneyBalances < 0 ||
      !Array.isArray(state.issueSamples) ||
      state.issueSamples.length > MAX_ISSUE_SAMPLES ||
      [
        state.invalidBalanceDocuments,
        state.missingChartAccounts,
        state.headerAccountsWithBalance,
        state.currencyMismatchBalances,
        state.invalidMoneyBalances,
      ].some((count) => count > state.balancesChecked) ||
      state.certified !== false ||
      state.accountingCutoffApplied !== false ||
      state.consistency !== 'non_atomic') {
    fail(HttpsError, 'Invalid reverse balance projection checkpoint.');
  }
  validateBalanceTotals(state, HttpsError);
  validateEpoch(state.postingEpoch, HttpsError);
}
function present(runId, state) {
  return {
    runId, storeId: state.storeId, status: state.status,
    scope: 'all_tenant_account_balance_documents',
    consistency: 'non_atomic',
    certified: false,
    accountingCutoffApplied: false,
    balancesChecked: state.balancesChecked,
    pagesChecked: state.pagesChecked,
    invalidBalanceDocuments: state.invalidBalanceDocuments,
    missingChartAccounts: state.missingChartAccounts,
    headerAccountsWithBalance: state.headerAccountsWithBalance,
    currencyMismatchBalances: state.currencyMismatchBalances,
    invalidMoneyBalances: state.invalidMoneyBalances,
    balanceTotalsByCurrency: {...state.balanceTotalsByCurrency},
    issueSamples: [...state.issueSamples],
  };
}
async function startBalanceProjectionScan({
  db, FieldValue, HttpsError, storeId, uid, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const member = await store.collection('members').doc(uid).get();
  assertAccess(member, storeId);
  const postingEpoch = await readPostingEpoch(db, store, HttpsError);
  const runRef = store.collection('accounting_balance_path_runs').doc();
  const state = {
    schemaVersion: VERSION,
    postingEpoch,
    storeId, createdBy: uid,
    status: 'running', cursorId: null,
    balancesChecked: 0, pagesChecked: 0,
    invalidBalanceDocuments: 0,
    missingChartAccounts: 0,
    headerAccountsWithBalance: 0,
    currencyMismatchBalances: 0,
    invalidMoneyBalances: 0,
    balanceTotalsByCurrency: {},
    issueSamples: [],
    consistency: 'non_atomic', certified: false,
    accountingCutoffApplied: false,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  await runRef.create(state);
  return present(runRef.id, state);
}
async function advanceBalanceProjectionScan({
  db, FieldValue, HttpsError, storeId, uid, runId, assertAccess,
}) {
  const store = db.collection('stores').doc(storeId);
  const runRef = store.collection('accounting_balance_path_runs').doc(runId);
  return db.runTransaction(async (tx) => {
    const membership = await tx.get(store.collection('members').doc(uid));
    assertAccess(membership, storeId);
    const checkpoint = await tx.get(runRef);
    if (!checkpoint.exists) {
      throw new HttpsError('not-found', 'Reverse balance audit not found.');
    }
    const state = checkpoint.data();
    if (state.storeId !== storeId || state.createdBy !== uid) {
      throw new HttpsError('permission-denied',
        'Reverse balance audit belongs to another user or store.');
    }
    validState(state, storeId, uid, HttpsError);
    if (state.status === 'enumeration_complete') {
      return present(runId, state);
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
      return present(runId, changed);
    }
    let query = store.collection('account_balances')
      .orderBy('__name__').limit(PAGE_SIZE + 1);
    if (state.cursorId !== null) query = query.startAfter(state.cursorId);
    const page = await tx.get(query);
    const batch = page.docs.slice(0, PAGE_SIZE);
    const more = page.docs.length > PAGE_SIZE;

    // Each balance document is checked against the account at the same
    // *document path*, never against untrusted embedded accountId.
    const charts = new Map();
    for (const row of batch) {
      charts.set(row.id, await tx.get(
        store.collection('accounts').doc(row.id),
      ));
    }

    let invalid = state.invalidBalanceDocuments;
    let missing = state.missingChartAccounts;
    let header = state.headerAccountsWithBalance;
    let currency = state.currencyMismatchBalances;
    let money = state.invalidMoneyBalances;
    let totals = state.balanceTotalsByCurrency;
    const samples = [...state.issueSamples];
    const issue = (code, path) => {
      if (samples.length < MAX_ISSUE_SAMPLES) {
        samples.push({code, referenceId: path});
      }
    };
    for (const row of batch) {
      const value = row.data();
      const accountSnap = charts.get(row.id);
      let defective = false;
      if (!accountSnap.exists) {
        missing = add(missing, 1, HttpsError);
        issue('BALANCE_CHART_ACCOUNT_MISSING', row.ref.path);
        defective = true;
      } else {
        const account = accountSnap.data();
        if (account.storeId !== storeId) {
          defective = true;
          issue('BALANCE_CHART_ACCOUNT_WRONG_STORE', row.ref.path);
        }
        if (account.isHeader === true) {
          header = add(header, 1, HttpsError);
          defective = true;
          issue('BALANCE_ON_NON_POSTING_HEADER', row.ref.path);
        }
        if (typeof account.currency !== 'string' ||
            !/^[A-Z]{3}$/.test(account.currency) ||
            value.currency !== account.currency) {
          currency = add(currency, 1, HttpsError);
          defective = true;
          issue('BALANCE_CHART_CURRENCY_MISMATCH', row.ref.path);
        }
      }
      if (value.storeId !== storeId || value.accountId !== row.id ||
          typeof value.currency !== 'string' ||
          !/^[A-Z]{3}$/.test(value.currency)) {
        defective = true;
        issue('BALANCE_EMBEDDED_IDENTITY_INVALID', row.ref.path);
      }
      const d = value.debitMinorUnits;
      const c = value.creditMinorUnits;
      const n = value.balanceMinorUnits;
      if (!Number.isSafeInteger(d) || d < 0 ||
          !Number.isSafeInteger(c) || c < 0 ||
          !Number.isSafeInteger(n) ||
          !Number.isSafeInteger(d - c) || n !== d - c) {
        money = add(money, 1, HttpsError);
        defective = true;
        issue('BALANCE_MONEY_OR_NET_INVALID', row.ref.path);
      }
      if (defective) {
        invalid = add(invalid, 1, HttpsError);
      } else {
        // Only individually validated, tenant-owned, non-header balances
        // may contribute to independent source totals.
        totals = addStoredBalance(totals, value, HttpsError);
      }
    }
    const next = {
      ...state,
      status: more ? 'running' : 'enumeration_complete',
      cursorId: batch.length > 0
        ? batch[batch.length - 1].id : state.cursorId,
      balancesChecked: add(state.balancesChecked, batch.length, HttpsError),
      pagesChecked: add(state.pagesChecked, 1, HttpsError),
      invalidBalanceDocuments: invalid,
      missingChartAccounts: missing,
      headerAccountsWithBalance: header,
      currencyMismatchBalances: currency,
      invalidMoneyBalances: money,
      balanceTotalsByCurrency: totals,
      issueSamples: samples,
      updatedAt: FieldValue.serverTimestamp(),
    };
    tx.update(runRef, next);
    return present(runId, next);
  });
}
module.exports = {
  PAGE_SIZE,
  validateBalanceProjectionRun: validState,
  startBalanceProjectionScan, advanceBalanceProjectionScan,
};

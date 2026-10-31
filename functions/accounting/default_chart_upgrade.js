'use strict';

const {getDefaultChart} = require('../default_chart_of_accounts');
const {markJournalPosting} = require('./posting_epoch');
const {assertAccountingWritesOpen} = require('./period_close');

const REQUIRED_ACCOUNT_IDS = Object.freeze(['3400', '4200', '5200']);
const ID = /^[A-Za-z0-9_-]{1,128}$/;
const SEMANTIC_FIELDS = Object.freeze([
  'id',
  'code',
  'type',
  'normalSide',
  'controlType',
  'statementSection',
  'parentId',
  'currency',
  'isHeader',
]);

function fail(HttpsError, code, message) {
  throw new HttpsError(code, message);
}

function requireStoreId(data, HttpsError) {
  const storeId = data?.storeId;
  if (typeof storeId !== 'string' || !ID.test(storeId)) {
    fail(HttpsError, 'invalid-argument', 'Invalid store identifier.');
  }
  return storeId;
}

function isCompatible(existing, template, storeId) {
  if (!existing || existing.storeId !== storeId || existing.isActive !== true) {
    return false;
  }
  return SEMANTIC_FIELDS.every((field) =>
    Object.is(existing[field], template[field]));
}

async function upgradeDefaultChart({
  db,
  FieldValue,
  HttpsError,
  userId,
  data,
  assertAccess,
}) {
  const storeId = requireStoreId(data, HttpsError);
  const chart = getDefaultChart();
  const templates = REQUIRED_ACCOUNT_IDS.map((id) => {
    const account = chart.accounts.find((candidate) => candidate.id === id);
    if (!account) {
      throw new Error('Required default chart account is missing: ' + id);
    }
    return account;
  });

  const storeRef = db.collection('stores').doc(storeId);
  const accountsRef = storeRef.collection('accounts');

  return db.runTransaction(async (tx) => {
    const store = await tx.get(storeRef);
    const member = await tx.get(storeRef.collection('members').doc(userId));
    if (!store.exists) {
      fail(HttpsError, 'not-found', 'Store not found.');
    }
    assertAccess(member, storeId);
    await assertAccountingWritesOpen(tx, storeRef, HttpsError);

    const currentVersion = store.data().accountingChartVersion ??
      store.data().initialChartVersion ?? 1;
    if (!Number.isSafeInteger(currentVersion) || currentVersion < 1 ||
        currentVersion > chart.version) {
      fail(HttpsError, 'failed-precondition',
        'Store chart version is invalid or newer than this application.');
    }

    const parent = await tx.get(accountsRef.doc('3100'));
    if (!parent.exists || parent.data().storeId !== storeId ||
        parent.data().id !== '3100' || parent.data().code !== '3100' ||
        parent.data().type !== 'equity' ||
        parent.data().currency !== chart.baseCurrency ||
        parent.data().isHeader !== true ||
        parent.data().isActive !== true) {
      fail(HttpsError, 'failed-precondition',
        'Equity parent account 3100 is missing or incompatible.');
    }

    const snapshots = [];
    const collisions = [];
    for (const template of templates) {
      snapshots.push(await tx.get(accountsRef.doc(template.id)));
      collisions.push(await tx.get(
        accountsRef.where('code', '==', template.code).limit(2),
      ));
    }

    const missing = [];
    for (let index = 0; index < templates.length; index++) {
      const template = templates[index];
      const snapshot = snapshots[index];
      const query = collisions[index];
      const foreignCode = query.docs.find((doc) => doc.id !== template.id);
      if (foreignCode) {
        fail(HttpsError, 'already-exists',
          'Chart code ' + template.code + ' is already used by another account.');
      }
      if (snapshot.exists) {
        if (!isCompatible(snapshot.data(), template, storeId)) {
          fail(HttpsError, 'failed-precondition',
            'Existing account ' + template.id +
            ' conflicts with the required chart definition.');
        }
      } else {
        missing.push(template);
      }
    }

    for (const account of missing) {
      tx.create(accountsRef.doc(account.id), {
        ...account,
        storeId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    const needsVersionMarker = currentVersion !== chart.version ||
      store.data().accountingChartVersion !== chart.version;
    if (needsVersionMarker) {
      tx.set(storeRef, {
        accountingChartVersion: chart.version,
        chartUpdatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }

    if (missing.length > 0) {
      markJournalPosting(
        tx,
        storeRef,
        'default-chart-upgrade-v' + chart.version,
        FieldValue,
      );
    }

    return {
      status: missing.length > 0 || needsVersionMarker
        ? 'upgraded'
        : 'unchanged',
      storeId,
      version: chart.version,
      addedAccountIds: missing.map((account) => account.id),
    };
  });
}

module.exports = {
  REQUIRED_ACCOUNT_IDS,
  isCompatible,
  requireStoreId,
  upgradeDefaultChart,
};

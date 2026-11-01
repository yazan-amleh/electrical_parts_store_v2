'use strict';

// Server-maintained change fence for every financial journal posting routed
// through the V2 callable posting transactions. The counter is bumped in the
// SAME Firestore transaction as the journal and its balance projections.
//
// This is NOT an immutable historical snapshot. Out-of-band Admin writes,
// chart-of-accounts changes, and migration scripts are NOT covered.
const {createHash} = require('node:crypto');

const SHARD_COUNT = 16;
const VERSION = 1;

function fail(HttpsError, message) {
  throw new HttpsError('failed-precondition', message);
}

function shardForEntry(journalEntryId) {
  if (typeof journalEntryId !== 'string' || !journalEntryId ||
      journalEntryId.includes('/')) {
    throw new Error('Invalid journal entry ID for mutation fence.');
  }
  const hash = createHash('sha256').update(journalEntryId).digest();
  return hash.readUInt32BE(0) % SHARD_COUNT;
}

function epochRefs(storeRef) {
  const collection = storeRef.collection('accounting_posting_epochs');
  return Array.from({length: SHARD_COUNT}, (_, i) =>
    collection.doc(String(i).padStart(2, '0')));
}

function markJournalPosting(transaction, storeRef, journalEntryId, FieldValue) {
  const shard = shardForEntry(journalEntryId);
  transaction.set(epochRefs(storeRef)[shard], {
    version: VERSION,
    sequence: FieldValue.increment(1),
    modifiedAt: FieldValue.serverTimestamp(),
  }, {merge: true});
}

function validateEpoch(epoch, HttpsError) {
  if (!Array.isArray(epoch) || epoch.length !== SHARD_COUNT ||
      epoch.some((n) => !Number.isSafeInteger(n) || n < 0)) {
    fail(HttpsError, 'Invalid accounting posting epoch checkpoint.');
  }
}

async function readPostingEpoch(reader, storeRef, HttpsError) {
  // Both Firestore and its transaction support getAll; one batched read
  // observes all sixteen shard documents in a single Firestore snapshot.
  const docs = await reader.getAll(...epochRefs(storeRef));
  const epoch = docs.map((doc) => {
    if (!doc.exists) return 0;
    const v = doc.data();
    if (v.version !== VERSION || !Number.isSafeInteger(v.sequence) ||
        v.sequence < 0) {
      fail(HttpsError, 'Accounting posting epoch source is malformed.');
    }
    return v.sequence;
  });
  validateEpoch(epoch, HttpsError);
  return epoch;
}

function epochsMatch(left, right) {
  return Array.isArray(left) && Array.isArray(right) &&
    left.length === SHARD_COUNT && right.length === SHARD_COUNT &&
    left.every((n, i) => n === right[i]);
}

module.exports = {
  SHARD_COUNT,
  VERSION,
  shardForEntry,
  epochRefs,
  markJournalPosting,
  validateEpoch,
  readPostingEpoch,
  epochsMatch,
};

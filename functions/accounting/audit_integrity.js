'use strict';

// Audit is deliberately read-only. Do not treat malformed money as a valid
// zero: add a material issue, and mark the report unhealthy.
// A single callable cannot guarantee an unlimited multi-collection audit.
// Read all pages up to these explicitly documented fail-closed limits.
const MAX_AUDIT_DOCS_PER_COLLECTION = 10000;
const MAX_AUDIT_TOTAL_DOCS = 30000;
const AUDIT_PAGE_SIZE = 200;
const AUDIT_JOURNAL_READ_CONCURRENCY = 8;

function isJournalLinePath(ref, storeId) {
  const parts = ref.path.split('/');
  return parts.length === 6 &&
    parts[0] === 'stores' &&
    parts[1] === storeId &&
    parts[2] === 'journal_entries' &&
    parts[3].length > 0 &&
    parts[4] === 'lines' &&
    parts[5].length > 0;
}

function auditInteger(value, issue, addIssue, {allowNegative = false} = {}) {
  if (!Number.isSafeInteger(value) || (!allowNegative && value < 0)) {
    addIssue({
      code: 'AUDIT_INVALID_INTEGER',
      scope: issue.scope,
      referenceId: issue.referenceId,
      message: issue.message || 'Invalid or unsafe persisted integer in accounting audit.',
      severity: 'error',
      valueKind: issue.valueKind || 'minorUnits',
    });
    return 0;
  }
  return value;
}

function auditSum(a, b, issue, addIssue) {
  if (!Number.isSafeInteger(a) ||
      !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    addIssue({
      code: 'AUDIT_INTEGER_OVERFLOW',
      scope: issue.scope,
      referenceId: issue.referenceId,
      message: 'Accounting audit sum exceeds safe integer precision.',
      severity: 'error',
      valueKind: issue.valueKind || 'minorUnits',
    });
    return 0;
  }
  return a + b;
}

/**
 * Traverse a Firestore collection by document ID, not by mutable postedAt.
 * Fetch one extra document to distinguish a complete scan from truncation.
 * The result deliberately has the QuerySnapshot fields used by the audit.
 */
async function readAuditPages(collectionRef, {
  maxDocuments = MAX_AUDIT_DOCS_PER_COLLECTION,
  pageSize = AUDIT_PAGE_SIZE,
} = {}) {
  if (!Number.isSafeInteger(maxDocuments) || maxDocuments < 0 ||
      !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > 500) {
    throw new Error('Invalid bounded audit pagination configuration');
  }
  const docs = [];
  let cursor = null;
  while (docs.length <= maxDocuments) {
    const remaining = maxDocuments + 1 - docs.length;
    let query = collectionRef.orderBy('__name__')
      .limit(Math.min(pageSize, remaining));
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    docs.push(...page.docs);
    if (docs.length > maxDocuments || page.empty ||
        page.size < Math.min(pageSize, remaining)) {
      break;
    }
    cursor = page.docs[page.docs.length - 1];
  }
  return {
    docs,
    size: docs.length,
    truncated: docs.length > maxDocuments,
  };
}

/**
 * Direct journal line scans bypass collectionGroup('lines') and its storeId
 * filter. Even malformed/missing line.storeId remains visible for reporting.
 * Each read stays read-only. Concurrency is bounded for emulator/Firestore.
 */
async function readJournalAuditLines(journalSnapshots, {
  maxDocuments = MAX_AUDIT_DOCS_PER_COLLECTION,
  pageSize = AUDIT_PAGE_SIZE,
  concurrency = AUDIT_JOURNAL_READ_CONCURRENCY,
} = {}) {
  const docs = [];
  for (let start = 0; start < journalSnapshots.length; start += concurrency) {
    const batch = journalSnapshots.slice(start, start + concurrency);
    const pages = await Promise.all(batch.map((journal) =>
      readAuditPages(journal.ref.collection('lines'), {
        maxDocuments: Math.min(maxDocuments, Math.max(0, maxDocuments - docs.length)),
        pageSize,
      }),
    ));
    for (const part of pages) {
      docs.push(...part.docs);
      if (part.truncated || docs.length > maxDocuments) {
        return {docs, size: docs.length, truncated: true};
      }
    }
  }
  return {docs, size: docs.length, truncated: false};
}

module.exports = {
  MAX_AUDIT_DOCS_PER_COLLECTION,
  MAX_AUDIT_TOTAL_DOCS,
  AUDIT_PAGE_SIZE,
  readAuditPages,
  readJournalAuditLines,
  isJournalLinePath,
  auditInteger,
  auditSum,
};

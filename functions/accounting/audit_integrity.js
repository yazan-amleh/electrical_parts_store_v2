'use strict';

// Audit is deliberately read-only. Do not treat malformed money as a valid
// zero: add a material issue, and mark the report unhealthy.
const MAX_AUDIT_DOCS_PER_COLLECTION = 4000;

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

module.exports = {
  MAX_AUDIT_DOCS_PER_COLLECTION,
  isJournalLinePath,
  auditInteger,
  auditSum,
};

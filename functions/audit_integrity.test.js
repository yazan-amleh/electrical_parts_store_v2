'use strict';

const assert = require('node:assert/strict');
const { describe, it } = require('node:test');
const {
  MAX_AUDIT_DOCS_PER_COLLECTION,
  MAX_AUDIT_TOTAL_DOCS,
  readAuditPages,
  readJournalAuditLines,
  isJournalLinePath,
  auditInteger,
  auditSum,
} = require('./accounting/audit_integrity');

describe('accounting audit safe parsing and data selection', () => {
  it('selects only the true nested journal_lines path of this store', () => {
    const ref = (path) => ({path});
    assert.equal(isJournalLinePath(
      ref('stores/shop-a/journal_entries/journal-1/lines/line-1'), 'shop-a',
    ), true);
    for (const path of [
      'stores/shop-a/sales/sale-1/lines/line-1',
      'stores/shop-a/purchases/purchase-1/lines/line-1',
      'stores/shop-b/journal_entries/journal-1/lines/line-1',
      'stores/shop-a/journal_entries/journal-1/lines/line-1/subitems/extra',
      'journal_entries/journal-1/lines/line-1',
    ]) {
      assert.equal(isJournalLinePath(ref(path), 'shop-a'), false, path);
    }
  });

  it('flags strings, fractions, missing values and unsafe integers', () => {
    const problems = [];
    for (const value of ['100', 1.5, null, undefined,
      Number.MAX_SAFE_INTEGER + 1, -1]) {
      assert.equal(auditInteger(
        value, {scope: 'accountBalance', referenceId: '1110'},
        (problem) => problems.push(problem),
      ), 0);
    }
    assert.equal(problems.length, 6);
    assert.equal(problems.every((p) => p.code === 'AUDIT_INVALID_INTEGER'), true);
    assert.equal(auditInteger(-25, {scope: 'inventory', referenceId: 'stock-a'},
      () => { throw Error('Negative stock adjustment should be permitted'); },
      {allowNegative: true}), -25);
  });

  it('flags arithmetic overflow rather than comparing imprecise sums', () => {
    const problems = [];
    assert.equal(auditSum(
      Number.MAX_SAFE_INTEGER, 1,
      {scope: 'journal', referenceId: 'journal-a'},
      (p) => problems.push(p),
    ), 0);
    assert.equal(problems[0].code, 'AUDIT_INTEGER_OVERFLOW');
    assert.equal(auditSum(500, -200, {scope: 'inventory', referenceId: 'A'},
      () => { throw Error('Should not fail'); }), 300);
  });

  function mockCollection(ids) {
    return {
      orderBy(field) {
        assert.equal(field, '__name__');
        let size = 0;
        let cursor = null;
        return {
          limit(next) {
            size = next;
            return this;
          },
          startAfter(lastDoc) {
            cursor = lastDoc.id;
            return this;
          },
          async get() {
            const after = cursor == null ? 0 :
              ids.findIndex((id) => id === cursor) + 1;
            const docs = ids.slice(after, after + size)
              .map((id) => ({id}));
            return {docs, size: docs.length, empty: docs.length === 0};
          },
        };
      },
    };
  }

  it('reads every page including the final partial page', async () => {
    const data = await readAuditPages(
      mockCollection(['a', 'b', 'c', 'd', 'e', 'f', 'g']),
      {maxDocuments: 9, pageSize: 3},
    );
    assert.equal(data.truncated, false);
    assert.deepEqual(data.docs.map((d) => d.id),
      ['a', 'b', 'c', 'd', 'e', 'f', 'g']);
  });

  it('scans beyond the previous 4000-row audit limit without truncation', async () => {
    const ids = Array.from({length: 4101}, (_, n) =>
      'record-' + String(n).padStart(6, '0'));
    const result = await readAuditPages(
      mockCollection(ids), {maxDocuments: 10000, pageSize: 200},
    );
    assert.equal(result.truncated, false);
    assert.equal(result.size, 4101);
    assert.equal(result.docs[4100].id, 'record-004100');
  });

  it('does not mistake a full last page for truncation', async () => {
    const data = await readAuditPages(
      mockCollection(['a', 'b', 'c', 'd']),
      {maxDocuments: 4, pageSize: 2},
    );
    assert.equal(data.truncated, false);
    assert.equal(data.size, 4);
  });

  it('flags a partial audit on the first extra row beyond a bound', async () => {
    const data = await readAuditPages(
      mockCollection(['a', 'b', 'c', 'd', 'e', 'f']),
      {maxDocuments: 4, pageSize: 2},
    );
    assert.equal(data.truncated, true);
    assert.equal(data.size, 5);
  });

  it('visits each journal direct subcollection and preserves malformed lines', async () => {
    const makeJournal = (id, lines) => ({
      id,
      ref: {
        collection(name) {
          assert.equal(name, 'lines');
          return mockCollection(lines);
        },
      },
    });
    const result = await readJournalAuditLines([
      makeJournal('j-1', ['a', 'b']),
      makeJournal('j-2', ['c', 'd', 'e']),
    ], {maxDocuments: 6, pageSize: 2, concurrency: 1});
    assert.equal(result.truncated, false);
    assert.deepEqual(result.docs.map((d) => d.id), ['a', 'b', 'c', 'd', 'e']);
  });

  it('holds concurrent journal page scans to a bounded global limit', async () => {
    const makeJournal = (id) => ({
      id,
      ref: {
        collection(name) {
          assert.equal(name, 'lines');
          return mockCollection(Array.from({length: 150}, (_, n) =>
            id + '-line-' + String(n).padStart(3, '0')));
        },
      },
    });
    const journals = ['a', 'b', 'c', 'd']
      .map((id) => makeJournal('j-' + id));
    const result = await readJournalAuditLines(journals, {
      maxDocuments: 100, pageSize: 40, concurrency: 4,
    });
    assert.equal(result.truncated, true);
    assert.equal(result.size > 100, true);
    assert.equal(result.size <= 104, true);
  });

  it('reports a complete journal scan at exactly the global limit', async () => {
    const journal = (id, ids) => ({
      id,
      ref: {collection: () => mockCollection(ids)},
    });
    const result = await readJournalAuditLines([
      journal('journal-a', ['a', 'b']),
      journal('journal-b', ['c', 'd']),
    ], {maxDocuments: 4, pageSize: 2, concurrency: 2});
    assert.equal(result.truncated, false);
    assert.equal(result.size, 4);
  });

  it('limits each audited collection to an explicit finite bound', () => {
    assert.equal(Number.isSafeInteger(MAX_AUDIT_DOCS_PER_COLLECTION), true);
    assert.equal(MAX_AUDIT_DOCS_PER_COLLECTION > 0, true);
    assert.equal(MAX_AUDIT_DOCS_PER_COLLECTION <= 10000, true);
    assert.equal(MAX_AUDIT_TOTAL_DOCS >= MAX_AUDIT_DOCS_PER_COLLECTION, true);
  });
});

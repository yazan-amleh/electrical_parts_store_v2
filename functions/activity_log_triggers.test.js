'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  activitySnapshot,
  changeKind,
  eventDocumentId,
  writeActivity,
} = require('./activity_log_triggers');

function snapshot(id, data, exists = true) {
  return {
    id,
    exists,
    data: () => data,
  };
}

function fakeDatabase() {
  const writes = new Map();
  return {
    writes,
    db: {
      collection: (root) => ({
        doc: (storeId) => ({
          collection: (collection) => ({
            doc: (id) => ({
              set: async (value) => {
                writes.set(`${root}/${storeId}/${collection}/${id}`, value);
              },
            }),
          }),
        }),
      }),
    },
  };
}

const Timestamp = {
  fromDate: (value) => value,
  now: () => new Date('2026-10-30T00:00:00.000Z'),
};

test('event ids are stable for the same CloudEvent', () => {
  const event = {
    id: 'event-123',
    params: {storeId: 'store-a'},
    time: '2026-10-30T10:00:00.000Z',
  };
  assert.equal(eventDocumentId(event), eventDocumentId(event));
});

test('changeKind and activitySnapshot preserve deleted source data', () => {
  const before = snapshot('product-1', {storeId: 'store-a', name: 'قاطع'});
  const after = snapshot('product-1', {}, false);
  const event = {data: {before, after}};

  assert.equal(changeKind(event), 'deleted');
  assert.equal(activitySnapshot(event), before);
});

test('writeActivity is server-owned and idempotent by event id', async () => {
  const {db, writes} = fakeDatabase();
  const source = snapshot('sale-1', {
    storeId: 'store-a',
    invoiceNumber: 'INV-1',
    createdBy: 'user-1',
  });
  const event = {
    id: 'sale-created-event',
    params: {storeId: 'store-a', saleId: 'sale-1'},
    data: source,
    time: '2026-10-30T10:00:00.000Z',
  };

  const write = () => writeActivity({
    db,
    Timestamp,
    event,
    type: 'saleCreated',
    description: (data) => `فاتورة ${data.invoiceNumber}`,
    metadata: {source: 'sales'},
  });

  const first = await write();
  const second = await write();

  assert.equal(first.activityId, second.activityId);
  assert.equal(writes.size, 1);
  const stored = [...writes.values()][0];
  assert.equal(stored.storeId, 'store-a');
  assert.equal(stored.userId, 'user-1');
  assert.equal(stored.type, 'saleCreated');
  assert.equal(stored.metadata.sourceId, 'sale-1');
  assert.equal(stored.metadata.operation, 'created');
});

test('writeActivity rejects a cross-store source document', async () => {
  const {db} = fakeDatabase();
  const event = {
    id: 'event-cross-store',
    params: {storeId: 'store-a', productId: 'product-1'},
    data: snapshot('product-1', {
      storeId: 'store-b',
      name: 'مصدر غير صحيح',
    }),
    time: '2026-10-30T10:00:00.000Z',
  };

  await assert.rejects(
    () => writeActivity({
      db,
      Timestamp,
      event,
      type: 'productChanged',
      description: 'تعديل صنف',
    }),
    /another store/,
  );
});

test('delete events record the deleted document and operation', async () => {
  const {db, writes} = fakeDatabase();
  const event = {
    id: 'product-delete-event',
    params: {storeId: 'store-a', productId: 'product-1'},
    data: {
      before: snapshot('product-1', {
        storeId: 'store-a',
        name: 'قاطع',
        updatedBy: 'user-2',
      }),
      after: snapshot('product-1', {}, false),
    },
    time: '2026-10-30T10:00:00.000Z',
  };

  await writeActivity({
    db,
    Timestamp,
    event,
    type: 'productChanged',
    description: (data, params, operation) =>
      `${operation}:${data.name}:${params.productId}`,
  });

  const stored = [...writes.values()][0];
  assert.equal(stored.description, 'deleted:قاطع:product-1');
  assert.equal(stored.metadata.operation, 'deleted');
  assert.equal(stored.userId, 'user-2');
});

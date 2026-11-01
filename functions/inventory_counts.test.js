'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {createInventoryCountHandlers} = require('./inventory_counts');

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function setup() {
  const documents = new Map();
  const recordedWrites = [];
  let rawProducts = [
    {id: 'p1', data: {
      storeId: 'store-a', name: 'فيوز', isService: false, isActive: true,
      categoryId: 'cat-1', quantityOnHandMilliUnits: 3000,
      purchasePriceMinorUnits: 200, currency: 'ILS',
    }},
    {id: 'p2', data: {
      storeId: 'store-a', name: 'مفتاح', isService: false, isActive: true,
      categoryId: 'cat-1', quantityOnHandMilliUnits: 1000,
      purchasePriceMinorUnits: 500, currency: 'USD',
    }},
  ];
  documents.set('stores/store-a/members/owner', {
    storeId: 'store-a', role: 'owner', isActive: true,
  });
  documents.set('stores/store-a/members/warehouse', {
    storeId: 'store-a', role: 'warehouse', isActive: true,
  });
  documents.set('stores/store-a/members/viewer', {
    storeId: 'store-a', role: 'viewer', isActive: true,
  });
  function snapshot(path) {
    const value = documents.get(path);
    return {
      exists: value !== undefined,
      data: () => value && structuredClone(value),
    };
  }
  function ref(path, filter = null, bound = null) {
    return {
      path,
      doc(id) { return ref(path + '/' + id); },
      collection(name) { return ref(path + '/' + name); },
      where(field, op, value) {
        assert.equal(op, '==');
        return ref(path, {field, value}, bound);
      },
      limit(value) { return ref(path, filter, value); },
      async get() {
        if (path.endsWith('/products')) {
          let products = rawProducts;
          if (filter) products = products.filter((p) =>
            p.data[filter.field] === filter.value);
          return {docs: products.slice(0, bound ?? products.length).map(
            (p) => ({id: p.id, data: () => structuredClone(p.data)}))};
        }
        return snapshot(path);
      },
    };
  }
  const db = {
    collection(name) { return ref(name); },
    async runTransaction(callback) {
      const writes = [];
      const tx = {
        async get(target) { return snapshot(target.path); },
        create(target, data) { writes.push({kind: 'create', target, data}); },
        update(target, data) { writes.push({kind: 'update', target, data}); },
      };
      const result = await callback(tx);
      for (const change of writes) {
        if (change.kind === 'create') {
          assert.equal(documents.has(change.target.path), false);
          documents.set(change.target.path, structuredClone(change.data));
        } else {
          documents.set(change.target.path, {
            ...documents.get(change.target.path),
            ...structuredClone(change.data),
          });
        }
        recordedWrites.push(change.target.path);
      }
      return result;
    },
  };
  const handlers = createInventoryCountHandlers({
    db,
    FieldValue: {serverTimestamp: () => 'now'},
    HttpsError,
  });
  function request(role, data = {}) {
    return {
      auth: {uid: role},
      data: {storeId: 'store-a', countId: 'count-1', ...data},
    };
  }
  function get() {
    return documents.get('stores/store-a/inventory_counts/count-1');
  }
  return {
    handlers, request, get, documents, recordedWrites,
    setProducts(value) { rawProducts = value; },
  };
}

test('owner creates an isolated count with fixed original quantities', async () => {
  const {handlers, request, get, recordedWrites} = setup();
  const first = await handlers.create(request('owner', {notes: 'الجرد الأول'}));
  assert.deepEqual(first, {
    storeId: 'store-a', countId: 'count-1', status: 'draft', revision: 1,
  });
  assert.equal(get().items.length, 2);
  assert.equal(get().items[0].systemQuantityMilliUnits, 3000);
  assert.equal(get().items[0].actualQuantityMilliUnits, null);
  const retry = await handlers.create(request('owner', {notes: 'الجرد الأول'}));
  assert.equal(retry.revision, 1);
  assert.equal(recordedWrites.length, 1);
  assert.deepEqual(recordedWrites, ['stores/store-a/inventory_counts/count-1']);
});

test('permission and cross-tenant membership are enforced server-side', async () => {
  const {handlers, request, documents, recordedWrites} = setup();
  await assert.rejects(
    handlers.create(request('viewer')),
    (err) => err.code === 'permission-denied',
  );
  await assert.rejects(
    handlers.create(request('owner', {storeId: 'store-b'})),
    (err) => err.code === 'permission-denied',
  );
  await assert.rejects(
    handlers.create({auth: null, data: {storeId: 'store-a', countId: 'c'}}),
    (err) => err.code === 'unauthenticated',
  );
  documents.set('stores/store-a/members/owner', {
    storeId: 'store-a', role: 'owner', isActive: false,
  });
  await assert.rejects(
    handlers.create(request('owner')),
    (err) => err.code === 'permission-denied',
  );
  assert.equal(recordedWrites.length, 0);
});

test('item revisions prevent lost updates and completion requires review', async () => {
  const {handlers, request, get, recordedWrites} = setup();
  await handlers.create(request('warehouse'));
  await assert.rejects(
    handlers.complete(request('warehouse', {expectedRevision: 1})),
    (err) => err.code === 'failed-precondition',
  );
  await assert.rejects(
    handlers.edit(request('warehouse', {
      productId: 'p1', expectedRevision: 1,
      actualQuantityMilliUnits: 2000, reviewed: true,
    })),
    (err) => err.code === 'invalid-argument',
  );
  const result = await handlers.edit(request('warehouse', {
    productId: 'p1', expectedRevision: 1,
    actualQuantityMilliUnits: 2000, reviewed: true,
    reason: 'تلف',
  }));
  assert.equal(result.revision, 2);
  assert.equal(get().decreaseItems, 1);
  assert.equal(get().estimatedDifferenceByCurrency.ILS, -200);
  await assert.rejects(
    handlers.edit(request('warehouse', {
      productId: 'p1', expectedRevision: 1,
      actualQuantityMilliUnits: 1000, reviewed: true, reason: 'خطأ',
    })),
    (err) => err.code === 'aborted',
  );
  const second = await handlers.edit(request('owner', {
    productId: 'p2', expectedRevision: 2,
    actualQuantityMilliUnits: 1000, reviewed: true, reason: '',
  }));
  assert.equal(second.revision, 3);
  assert.equal(get().matchedItems, 1);
  assert.deepEqual(get().estimatedDifferenceByCurrency, {ILS: -200, USD: 0});
  const completed = await handlers.complete(
    request('warehouse', {expectedRevision: 3}),
  );
  assert.equal(completed.status, 'completed');
  assert.equal(get().revision, 4);
  await assert.rejects(
    handlers.complete(request('owner', {expectedRevision: 4})),
    (err) => err.code === 'failed-precondition',
  );
  await assert.rejects(
    handlers.edit(request('owner', {
      productId: 'p1', expectedRevision: 4,
      actualQuantityMilliUnits: 3000, reviewed: true,
    })),
    (err) => err.code === 'failed-precondition',
  );
  assert(recordedWrites.every((path) => path.includes('/inventory_counts/')));
});

test('cancelled counts cannot be edited, completed, or cancelled again',
    async () => {
      const {handlers, request, get} = setup();
      await handlers.create(request('warehouse'));
      await assert.rejects(
        handlers.cancel(request('warehouse', {expectedRevision: 1})),
        (err) => err.code === 'invalid-argument',
      );
      const result = await handlers.cancel(request('owner', {
        expectedRevision: 1, reason: 'جرد خاطئ',
      }));
      assert.equal(result.status, 'cancelled');
      assert.equal(get().cancellationReason, 'جرد خاطئ');
      await assert.rejects(
        handlers.cancel(request('owner', {
          expectedRevision: 2, reason: 'تكرار',
        })),
        (err) => err.code === 'failed-precondition',
      );
      await assert.rejects(
        handlers.complete(request('owner', {expectedRevision: 2})),
        (err) => err.code === 'failed-precondition',
      );
    });

test('oversized count refuses truncation and category scope is respected',
    async () => {
      const {handlers, request, setProducts, get, recordedWrites} = setup();
      setProducts(Array.from({length: 151}, (_, i) => ({
        id: 'p' + i,
        data: {
          storeId: 'store-a', name: 'X', isActive: true, isService: false,
          categoryId: i < 2 ? 'cat-a' : 'cat-b',
          quantityOnHandMilliUnits: 0,
          purchasePriceMinorUnits: 100,
          currency: 'ILS',
        },
      })));
      await assert.rejects(
        handlers.create(request('warehouse')),
        (err) => err.code === 'failed-precondition',
      );
      assert.equal(recordedWrites.length, 0);
      const created = await handlers.create(request('warehouse', {
        categoryId: 'cat-a',
      }));
      assert.equal(created.status, 'draft');
      assert.equal(get().items.length, 2);
    });

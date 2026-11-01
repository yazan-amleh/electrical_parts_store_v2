'use strict';

// Inventory count workflow. Drafting/completing a count NEVER changes stock,
// inventory movements, accounts, or journals. Financial approval needs a
// separate atomic posting workflow with product-version and period checks.
function createInventoryCountHandlers({db, FieldValue, HttpsError}) {
  const authorRoles = new Set(['owner', 'admin', 'warehouse']);
  const maxProducts = 150;

  function fail(code, message) {
    throw new HttpsError(code, message);
  }

  function safeId(value, label) {
    if (typeof value !== 'string' || !value.trim() ||
        value.length > 130 || value.includes('/') ||
        value === '.' || value === '..') {
      fail('invalid-argument', label + ' is invalid.');
    }
    return value;
  }

  function optionalText(value, label, max = 500) {
    if (value == null) return '';
    if (typeof value !== 'string' || value.length > max) {
      fail('invalid-argument', label + ' is invalid.');
    }
    return value.trim();
  }

  function identity(request) {
    if (!request.auth?.uid) {
      fail('unauthenticated', 'Authentication is required.');
    }
    if (!request.data || typeof request.data !== 'object' ||
        Array.isArray(request.data)) {
      fail('invalid-argument', 'Request body is invalid.');
    }
    const raw = request.data;
    return {
      userId: request.auth.uid,
      storeId: safeId(raw.storeId, 'storeId'),
      countId: safeId(raw.countId, 'countId'),
      raw,
    };
  }

  function refs({userId, storeId, countId}) {
    const store = db.collection('stores').doc(storeId);
    return {
      count: store.collection('inventory_counts').doc(countId),
      member: store.collection('members').doc(userId),
      products: store.collection('products'),
    };
  }

  function authorize(snapshot, storeId) {
    const member = snapshot.exists ? snapshot.data() : null;
    if (!member || member.isActive !== true ||
        (member.storeId && member.storeId !== storeId) ||
        !authorRoles.has(member.role)) {
      fail('permission-denied', 'Inventory count requires warehouse access.');
    }
  }

  function readCount(snapshot, {storeId, countId}) {
    if (!snapshot.exists) fail('not-found', 'Inventory count was not found.');
    const count = snapshot.data();
    if (count.storeId !== storeId || count.id !== countId ||
        !Array.isArray(count.items) ||
        count.items.length > maxProducts ||
        !Number.isSafeInteger(count.revision)) {
      fail('failed-precondition', 'Inventory count data is not valid.');
    }
    return count;
  }

  function response(count) {
    return {
      storeId: count.storeId,
      countId: count.id,
      status: count.status,
      revision: count.revision,
    };
  }

  function countSummary(items) {
    let matched = 0;
    let increased = 0;
    let decreased = 0;
    let reviewed = 0;
    const values = {};
    for (const item of items) {
      if (item.reviewed) reviewed++;
      if (item.actualQuantityMilliUnits == null) continue;
      const delta = item.actualQuantityMilliUnits -
        item.systemQuantityMilliUnits;
      if (delta === 0) matched++;
      else if (delta > 0) increased++;
      else decreased++;
      const sign = delta === 0 ? 0 : delta > 0 ? 1 : -1;
      const absolute = Math.abs(delta);
      // Expected stock difference cost is informational. Approval must
      // independently recalculate from the currently posted cost basis.
      const estimated = Math.round(
        absolute * item.unitCostMinorUnits / 1000,
      ) * sign;
      if (!Number.isSafeInteger(estimated)) {
        fail('invalid-argument', 'Inventory difference value is too large.');
      }
      values[item.currency] = (values[item.currency] || 0) + estimated;
      if (!Number.isSafeInteger(values[item.currency])) {
        fail('invalid-argument', 'Inventory count total is too large.');
      }
    }
    return {
      totalItems: items.length,
      reviewedItems: reviewed,
      matchedItems: matched,
      increaseItems: increased,
      decreaseItems: decreased,
      estimatedDifferenceByCurrency: values,
    };
  }

  async function create(request) {
    const ctx = identity(request);
    const {count, member, products} = refs(ctx);
    const categoryId = ctx.raw.categoryId == null
      ? null : safeId(ctx.raw.categoryId, 'categoryId');
    const notes = optionalText(ctx.raw.notes, 'notes');
    const memberSnapshot = await member.get();
    authorize(memberSnapshot, ctx.storeId);
    // A bounded, store-scoped snapshot. Larger stores must count by category;
    // never silently omit items while pretending this is a full stocktake.
    let query = products;
    if (categoryId) query = query.where('categoryId', '==', categoryId);
    const data = await query.limit(maxProducts + 1).get();
    if (data.docs.length > maxProducts) {
      fail('failed-precondition',
        'Too many products. Choose a category and count at most 150 products.');
    }
    const items = data.docs
      .filter((doc) => {
        const p = doc.data();
        return p.isActive !== false && p.isService !== true;
      })
      .map((doc) => {
        const p = doc.data();
        const quantity = p.quantityOnHandMilliUnits;
        const cost = p.purchasePriceMinorUnits;
        const currency = p.currency || 'ILS';
        if (p.storeId !== ctx.storeId ||
            !Number.isSafeInteger(quantity) || quantity < 0 ||
            !Number.isSafeInteger(cost) || cost < 0 ||
            typeof currency !== 'string' || !currency.trim()) {
          fail('failed-precondition', 'The product ledger requires repair.');
        }
        return {
          productId: doc.id,
          productName: String(p.name || doc.id).slice(0, 120),
          barcode: String(p.barcode || '').slice(0, 100),
          systemQuantityMilliUnits: quantity,
          actualQuantityMilliUnits: null,
          unitCostMinorUnits: cost,
          currency,
          reviewed: false,
          reason: '',
          notes: '',
        };
      });
    if (!items.length) {
      fail('failed-precondition', 'No active stock products to count.');
    }
    items.sort((a, b) => a.productId.localeCompare(b.productId));
    return db.runTransaction(async (tx) => {
      const [membership, existing] = await Promise.all([
        tx.get(member),
        tx.get(count),
      ]);
      authorize(membership, ctx.storeId);
      if (existing.exists) {
        const previous = readCount(existing, ctx);
        if (previous.createdBy === ctx.userId &&
            previous.categoryId === categoryId &&
            previous.notes === notes) return response(previous);
        fail('already-exists', 'Inventory count ID is already in use.');
      }
      const next = {
        id: ctx.countId,
        storeId: ctx.storeId,
        categoryId,
        notes,
        status: 'draft',
        createdBy: ctx.userId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        revision: 1,
        items,
        ...countSummary(items),
      };
      tx.create(count, next);
      return response(next);
    });
  }

  async function edit(request) {
    const ctx = identity(request);
    const {count, member} = refs(ctx);
    const revision = ctx.raw.expectedRevision;
    if (!Number.isSafeInteger(revision) || revision < 1) {
      fail('invalid-argument', 'Expected revision is required.');
    }
    const productId = safeId(ctx.raw.productId, 'productId');
    const actualQuantityMilliUnits = ctx.raw.actualQuantityMilliUnits;
    if (!Number.isSafeInteger(actualQuantityMilliUnits) ||
        actualQuantityMilliUnits < 0 ||
        actualQuantityMilliUnits > 1000000000000) {
      fail('invalid-argument', 'Actual count must be a nonnegative integer.');
    }
    if (ctx.raw.reviewed !== true && ctx.raw.reviewed !== false) {
      fail('invalid-argument', 'Review flag is required.');
    }
    const reason = optionalText(ctx.raw.reason, 'reason', 160);
    const notes = optionalText(ctx.raw.notes, 'notes', 300);
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member), tx.get(count),
      ]);
      authorize(membership, ctx.storeId);
      const data = readCount(snapshot, ctx);
      if (data.status !== 'draft') {
        fail('failed-precondition', 'Only draft counts can be edited.');
      }
      if (data.revision !== revision) {
        fail('aborted', 'Another user updated this inventory count.');
      }
      const index = data.items.findIndex((item) => item.productId === productId);
      if (index === -1) fail('invalid-argument', 'Product is not in this count.');
      const items = data.items.map((item) => ({...item}));
      const system = items[index].systemQuantityMilliUnits;
      if (actualQuantityMilliUnits !== system &&
          ctx.raw.reviewed === true && !reason) {
        fail('invalid-argument', 'A difference requires a reason.');
      }
      items[index] = {
        ...items[index],
        actualQuantityMilliUnits,
        reviewed: ctx.raw.reviewed,
        reason,
        notes,
      };
      const nextRevision = revision + 1;
      tx.update(count, {
        items,
        ...countSummary(items),
        revision: nextRevision,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        storeId: ctx.storeId,
        countId: ctx.countId,
        status: 'draft',
        revision: nextRevision,
      };
    });
  }

  async function complete(request) {
    const ctx = identity(request);
    const {count, member} = refs(ctx);
    const revision = ctx.raw.expectedRevision;
    if (!Number.isSafeInteger(revision) || revision < 1) {
      fail('invalid-argument', 'Expected revision is required.');
    }
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member), tx.get(count),
      ]);
      authorize(membership, ctx.storeId);
      const data = readCount(snapshot, ctx);
      if (data.status !== 'draft' || data.revision !== revision) {
        fail('failed-precondition', 'Count changed or is no longer a draft.');
      }
      if (!data.items.length ||
          !data.items.every((item) =>
            item.reviewed === true &&
            Number.isSafeInteger(item.actualQuantityMilliUnits) &&
            item.actualQuantityMilliUnits >= 0 &&
            (item.actualQuantityMilliUnits === item.systemQuantityMilliUnits ||
             (typeof item.reason === 'string' && item.reason.trim())))) {
        fail('failed-precondition', 'All items need reviewed counts and reasons.');
      }
      const nextRevision = revision + 1;
      tx.update(count, {
        status: 'completed',
        completedBy: ctx.userId,
        completedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        revision: nextRevision,
      });
      return {
        storeId: ctx.storeId,
        countId: ctx.countId,
        status: 'completed',
        revision: nextRevision,
      };
    });
  }

  async function cancel(request) {
    const ctx = identity(request);
    const {count, member} = refs(ctx);
    const revision = ctx.raw.expectedRevision;
    if (!Number.isSafeInteger(revision) || revision < 1) {
      fail('invalid-argument', 'Expected revision is required.');
    }
    const reason = optionalText(ctx.raw.reason, 'reason', 300);
    if (!reason) fail('invalid-argument', 'Cancellation reason is required.');
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member), tx.get(count),
      ]);
      authorize(membership, ctx.storeId);
      const data = readCount(snapshot, ctx);
      if (!['draft', 'completed'].includes(data.status) ||
          data.revision !== revision) {
        fail('failed-precondition', 'Count changed or cannot be cancelled.');
      }
      const nextRevision = revision + 1;
      tx.update(count, {
        status: 'cancelled',
        cancellationReason: reason,
        cancelledBy: ctx.userId,
        cancelledAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        revision: nextRevision,
      });
      return {
        storeId: ctx.storeId,
        countId: ctx.countId,
        status: 'cancelled',
        revision: nextRevision,
      };
    });
  }

  return {create, edit, complete, cancel};
}

module.exports = {createInventoryCountHandlers};

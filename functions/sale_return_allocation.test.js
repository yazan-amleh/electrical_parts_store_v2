'use strict';

const assert = require('node:assert/strict');
const {describe, it} = require('node:test');
const {
  allocateCumulative,
  allocateHeaderBySubtotal,
} = require('./accounting/sale_return_allocation');

describe('sale return cumulative allocation', () => {
  it('allocates rounding from cumulative targets without drift', () => {
    const first = allocateCumulative({
      sourceTotal: 100,
      sourceQuantity: 3,
      alreadyReturnedQuantity: 0,
      alreadyAllocated: 0,
      returnQuantity: 1,
    });
    const second = allocateCumulative({
      sourceTotal: 100,
      sourceQuantity: 3,
      alreadyReturnedQuantity: first.nextReturnedQuantity,
      alreadyAllocated: first.nextAllocated,
      returnQuantity: 1,
    });
    const third = allocateCumulative({
      sourceTotal: 100,
      sourceQuantity: 3,
      alreadyReturnedQuantity: second.nextReturnedQuantity,
      alreadyAllocated: second.nextAllocated,
      returnQuantity: 1,
    });

    assert.deepEqual(
      [first.allocated, second.allocated, third.allocated],
      [33, 34, 33],
    );
    assert.equal(
      first.allocated + second.allocated + third.allocated,
      100,
    );
    assert.equal(third.completed, true);
    assert.equal(third.nextAllocated, 100);
  });

  it('preserves tiny source totals across several partial returns', () => {
    const first = allocateCumulative({
      sourceTotal: 1,
      sourceQuantity: 3,
      alreadyReturnedQuantity: 0,
      alreadyAllocated: 0,
      returnQuantity: 1,
      label: 'COGS',
    });
    const second = allocateCumulative({
      sourceTotal: 1,
      sourceQuantity: 3,
      alreadyReturnedQuantity: 1,
      alreadyAllocated: first.nextAllocated,
      returnQuantity: 1,
      label: 'COGS',
    });
    const final = allocateCumulative({
      sourceTotal: 1,
      sourceQuantity: 3,
      alreadyReturnedQuantity: 2,
      alreadyAllocated: second.nextAllocated,
      returnQuantity: 1,
      label: 'COGS',
    });

    assert.deepEqual(
      [first.allocated, second.allocated, final.allocated],
      [0, 1, 0],
    );
    assert.equal(final.nextAllocated, 1);
  });

  it('allocates header tax by cumulative returned subtotal', () => {
    const first = allocateHeaderBySubtotal({
      sourceTotal: 17,
      sourceSubtotal: 100,
      alreadyReturnedSubtotal: 0,
      alreadyAllocated: 0,
      returnSubtotal: 33,
      label: 'tax',
    });
    const second = allocateHeaderBySubtotal({
      sourceTotal: 17,
      sourceSubtotal: 100,
      alreadyReturnedSubtotal: 33,
      alreadyAllocated: first.nextAllocated,
      returnSubtotal: 34,
      label: 'tax',
    });
    const final = allocateHeaderBySubtotal({
      sourceTotal: 17,
      sourceSubtotal: 100,
      alreadyReturnedSubtotal: 67,
      alreadyAllocated: second.nextAllocated,
      returnSubtotal: 33,
      label: 'tax',
    });

    assert.equal(
      first.allocated + second.allocated + final.allocated,
      17,
    );
    assert.equal(final.nextAllocated, 17);
    assert.equal(final.completed, true);
  });

  it('rejects over-return and corrupt cumulative state', () => {
    assert.throws(
      () => allocateCumulative({
        sourceTotal: 100,
        sourceQuantity: 1000,
        alreadyReturnedQuantity: 700,
        alreadyAllocated: 70,
        returnQuantity: 301,
      }),
      /exceeds the remaining source quantity/,
    );
    assert.throws(
      () => allocateCumulative({
        sourceTotal: 100,
        sourceQuantity: 1000,
        alreadyReturnedQuantity: 500,
        alreadyAllocated: 101,
        returnQuantity: 100,
      }),
      /stored allocation exceeds source total/,
    );
  });

  it('rejects arithmetic beyond safe integer precision', () => {
    assert.throws(
      () => allocateCumulative({
        sourceTotal: Number.MAX_SAFE_INTEGER,
        sourceQuantity: 2,
        alreadyReturnedQuantity: 0,
        alreadyAllocated: 0,
        returnQuantity: 1,
      }),
      /multiplication exceeds safe integer precision/,
    );
  });
});

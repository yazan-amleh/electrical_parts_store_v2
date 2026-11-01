'use strict';

function fail(message) {
  throw new RangeError(message);
}

function safeNonNegative(value, label) {
  if (!Number.isSafeInteger(value) || value < 0) {
    fail(label + ' must be a non-negative safe integer.');
  }
  return value;
}

function safePositive(value, label) {
  if (!Number.isSafeInteger(value) || value <= 0) {
    fail(label + ' must be a positive safe integer.');
  }
  return value;
}

function checkedAdd(a, b, label) {
  if (!Number.isSafeInteger(a) ||
      !Number.isSafeInteger(b) ||
      !Number.isSafeInteger(a + b)) {
    fail(label + ' exceeds safe integer precision.');
  }
  return a + b;
}

function roundedRatio(total, numerator, denominator, label) {
  safeNonNegative(total, label + ' total');
  safeNonNegative(numerator, label + ' numerator');
  safePositive(denominator, label + ' denominator');
  if (numerator > denominator) {
    fail(label + ' numerator exceeds denominator.');
  }
  const product = total * numerator;
  if (!Number.isSafeInteger(product)) {
    fail(label + ' multiplication exceeds safe integer precision.');
  }
  return Math.floor((product + Math.floor(denominator / 2)) / denominator);
}

/**
 * Allocate an immutable source amount over cumulative returned quantity.
 *
 * Allocation is based on the cumulative target, not repeated per-return
 * multiplication. Therefore rounding cannot drift across several returns.
 * The final return receives the exact residual so cumulative allocation
 * always equals sourceTotal.
 */
function allocateCumulative({
  sourceTotal,
  sourceQuantity,
  alreadyReturnedQuantity,
  alreadyAllocated,
  returnQuantity,
  label = 'return allocation',
}) {
  safeNonNegative(sourceTotal, label + ' sourceTotal');
  safePositive(sourceQuantity, label + ' sourceQuantity');
  safeNonNegative(
    alreadyReturnedQuantity,
    label + ' alreadyReturnedQuantity',
  );
  safeNonNegative(alreadyAllocated, label + ' alreadyAllocated');
  safePositive(returnQuantity, label + ' returnQuantity');

  if (alreadyReturnedQuantity > sourceQuantity) {
    fail(label + ' stored returned quantity exceeds source quantity.');
  }
  if (alreadyAllocated > sourceTotal) {
    fail(label + ' stored allocation exceeds source total.');
  }

  const nextQuantity = checkedAdd(
    alreadyReturnedQuantity,
    returnQuantity,
    label + ' returned quantity',
  );
  if (nextQuantity > sourceQuantity) {
    fail(label + ' return quantity exceeds the remaining source quantity.');
  }

  const nextAllocated = nextQuantity === sourceQuantity
    ? sourceTotal
    : roundedRatio(
        sourceTotal,
        nextQuantity,
        sourceQuantity,
        label,
      );
  if (nextAllocated < alreadyAllocated) {
    fail(label + ' cumulative allocation moved backwards.');
  }

  return {
    allocated: nextAllocated - alreadyAllocated,
    nextReturnedQuantity: nextQuantity,
    nextAllocated,
    completed: nextQuantity === sourceQuantity,
  };
}

/**
 * Allocate a header amount (for example tax) by cumulative returned subtotal.
 * This uses the same residual rule as line allocations.
 */
function allocateHeaderBySubtotal({
  sourceTotal,
  sourceSubtotal,
  alreadyReturnedSubtotal,
  alreadyAllocated,
  returnSubtotal,
  label = 'header return allocation',
}) {
  return allocateCumulative({
    sourceTotal,
    sourceQuantity: sourceSubtotal,
    alreadyReturnedQuantity: alreadyReturnedSubtotal,
    alreadyAllocated,
    returnQuantity: returnSubtotal,
    label,
  });
}

module.exports = {
  allocateCumulative,
  allocateHeaderBySubtotal,
};

'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {nextVoucherNumber} = require('./voucher_numbering');

const date = new Date('2026-12-31T23:59:59Z');
test('first receipt and payment have separately scoped serials', () => {
  const first = nextVoucherNumber({
    storeId: 'store-a',
    partyType: 'customer',
    postedAt: date,
    sequence: null,
  });
  assert.equal(first.voucherNumber, 'RC-2026-000001');
  assert.equal(first.serial, 1);
  const second = nextVoucherNumber({
    storeId: 'store-a',
    partyType: 'customer',
    postedAt: date,
    sequence: {
      storeId: 'store-a',
      kind: 'receipt',
      year: 2026,
      lastNumber: 1,
    },
  });
  assert.equal(second.voucherNumber, 'RC-2026-000002');
  const supplier = nextVoucherNumber({
    storeId: 'store-a',
    partyType: 'supplier',
    postedAt: date,
  });
  assert.equal(supplier.voucherNumber, 'PV-2026-000001');
  const nextYear = nextVoucherNumber({
    storeId: 'store-a',
    partyType: 'customer',
    postedAt: new Date('2027-01-01T00:00:01Z'),
  });
  assert.equal(nextYear.voucherNumber, 'RC-2027-000001');
});

test('rejects wrong store, wrong year, wrong direction and exhausted counter', () => {
  const valid = {storeId: 'store-a', kind: 'receipt', year: 2026, lastNumber: 10};
  for (const sequence of [
    {...valid, storeId: 'store-b'},
    {...valid, kind: 'payment'},
    {...valid, year: 2027},
    {...valid, lastNumber: -1},
    {...valid, lastNumber: 999999},
    {...valid, lastNumber: 1.5},
  ]) {
    assert.throws(() => nextVoucherNumber({
      storeId: 'store-a',
      partyType: 'customer',
      postedAt: date,
      sequence,
    }));
  }
});

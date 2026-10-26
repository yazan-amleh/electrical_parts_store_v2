'use strict';

// A pure function: caller must read and commit the counter INSIDE the same
// Firestore transaction as posting the voucher and journal entry.
function nextVoucherNumber({
  storeId,
  partyType,
  postedAt,
  sequence,
}) {
  if (!['customer', 'supplier'].includes(partyType)) {
    throw Error('Unsupported voucher direction.');
  }
  if (!(postedAt instanceof Date) || Number.isNaN(postedAt.getTime())) {
    throw Error('Invalid voucher posting date.');
  }
  const year = postedAt.getUTCFullYear();
  const kind = partyType === 'customer' ? 'receipt' : 'payment';
  const previous = sequence || null;
  if (previous &&
      (previous.storeId !== storeId ||
        previous.kind !== kind ||
        previous.year !== year)) {
    throw Error('Voucher sequence ownership or scope mismatch.');
  }
  const last = previous ? previous.lastNumber : 0;
  if (!Number.isSafeInteger(last) || last < 0 || last >= 999999) {
    throw Error('Voucher sequence invalid or exhausted.');
  }
  const number = last + 1;
  const prefix = kind === 'receipt' ? 'RC' : 'PV';
  return {
    kind,
    year,
    serial: number,
    voucherNumber: prefix + '-' + year + '-' +
      String(number).padStart(6, '0'),
  };
}

module.exports = {nextVoucherNumber};

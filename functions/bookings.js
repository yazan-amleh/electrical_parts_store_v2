const { HttpsError, onCall } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const BOOKING_WRITE_ROLES = new Set([
  'owner',
  'admin',
  'accountant',
  'sales',
]);

const TERMINAL_STATUSES = new Set(['completed', 'cancelled']);

function invalid(message) {
  throw new HttpsError('invalid-argument', message);
}

function conflict(message) {
  throw new HttpsError('failed-precondition', message);
}

function requireObject(value, label) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    invalid(label + ' must be an object.');
  }
  return value;
}

function requiredString(value, label) {
  if (typeof value !== 'string' || value.trim() === '') {
    invalid(label + ' is required.');
  }
  return value.trim();
}

function optionalString(value) {
  if (typeof value !== 'string') {
    return null;
  }
  const result = value.trim();
  return result === '' ? null : result;
}

function safeId(value, label) {
  const result = requiredString(value, label);
  if (result.includes('/')) {
    invalid(label + ' is invalid.');
  }
  return result;
}

function integerValue(value, label, minimum = 0) {
  if (!Number.isInteger(value) || value < minimum) {
    invalid(label + ' must be an integer greater than or equal to ' + minimum + '.');
  }
  return value;
}

function parseDate(value, label) {
  if (typeof value !== 'string' || Number.isNaN(Date.parse(value))) {
    invalid(label + ' must be a valid ISO date.');
  }
  return new Date(value);
}

function parseBookingDraft(rawCommand) {
  const command = requireObject(rawCommand, 'command');
  const booking = requireObject(command.booking, 'booking');
  const storeId = safeId(command.storeId, 'storeId');

  const draft = {
    id: safeId(booking.id, 'booking.id'),
    idempotencyKey: safeId(
      booking.idempotencyKey,
      'booking.idempotencyKey',
    ),
    customerId: safeId(booking.customerId, 'booking.customerId'),
    photographyOptionId: safeId(
      booking.photographyOptionId,
      'booking.photographyOptionId',
    ),
    startAt: parseDate(booking.startAt, 'booking.startAt'),
    durationMinutes: integerValue(
      booking.durationMinutes,
      'booking.durationMinutes',
      1,
    ),
    location: requiredString(booking.location, 'booking.location'),
    notes: optionalString(booking.notes),
    totalPriceMinorUnits: integerValue(
      booking.totalPriceMinorUnits,
      'booking.totalPriceMinorUnits',
    ),
    totalDiscountMinorUnits: integerValue(
      booking.totalDiscountMinorUnits ?? 0,
      'booking.totalDiscountMinorUnits',
    ),
    depositAmountMinorUnits: integerValue(
      booking.depositAmountMinorUnits ?? 0,
      'booking.depositAmountMinorUnits',
    ),
  };

  if (draft.totalDiscountMinorUnits > draft.totalPriceMinorUnits) {
    invalid('Booking discount cannot exceed the total price.');
  }
  if (draft.depositAmountMinorUnits > draft.totalPriceMinorUnits) {
    invalid('Booking deposit cannot exceed the total price.');
  }

  return {storeId, draft};
}

function assertBookingMembership(snapshot, storeId, userId) {
  if (!snapshot.exists) {
    throw new HttpsError('permission-denied', 'Store membership is required.');
  }
  const member = snapshot.data() || {};
  if (member.storeId && member.storeId !== storeId) {
    throw new HttpsError('permission-denied', 'Store membership is invalid.');
  }
  if (member.isActive === false || !BOOKING_WRITE_ROLES.has(member.role)) {
    throw new HttpsError(
      'permission-denied',
      'You do not have permission to manage bookings.',
    );
  }
}

async function readCatalog(transaction, storeRef, draft) {
  const customerRef = storeRef
    .collection('booking_customers')
    .doc(draft.customerId);
  const optionRef = storeRef
    .collection('photography_options')
    .doc(draft.photographyOptionId);
  const customerSnapshot = await transaction.get(customerRef);
  const optionSnapshot = await transaction.get(optionRef);

  if (!customerSnapshot.exists) {
    throw new HttpsError('not-found', 'Booking customer was not found.');
  }
  if (!optionSnapshot.exists) {
    throw new HttpsError('not-found', 'Photography option was not found.');
  }

  const customer = customerSnapshot.data() || {};
  const option = optionSnapshot.data() || {};
  if (customer.storeId !== storeRef.id || option.storeId !== storeRef.id) {
    throw new HttpsError('permission-denied', 'Booking catalog data is invalid.');
  }
  if (option.isActive === false) {
    conflict('The selected photography option is inactive.');
  }

  const optionPrice = integerValue(
    option.priceMinorUnits,
    'Photography option price',
  );
  const expectedTotal = optionPrice - draft.totalDiscountMinorUnits;
  if (expectedTotal !== draft.totalPriceMinorUnits) {
    invalid('Booking total does not match the selected photography option.');
  }

  return {
    customer,
    option,
    currency: typeof option.currency === 'string' && option.currency.trim()
      ? option.currency.trim()
      : 'ILS',
  };
}

function storedBooking({storeId, draft, customer, option, currency, now, existing}) {
  return {
    storeId,
    idempotencyKey: existing?.idempotencyKey || draft.idempotencyKey,
    customerId: draft.customerId,
    customerName: customer.name,
    customerPhone: customer.phoneNumber,
    customerEmail: optionalString(customer.email),
    startAt: Timestamp.fromDate(draft.startAt),
    durationMinutes: draft.durationMinutes,
    location: draft.location,
    notes: draft.notes,
    photographyOptionId: draft.photographyOptionId,
    photographyOptionName: option.name,
    totalPriceMinorUnits: draft.totalPriceMinorUnits,
    currency,
    depositAmountMinorUnits: draft.depositAmountMinorUnits,
    paidAmountMinorUnits: existing?.paidAmountMinorUnits || 0,
    status: existing?.status || 'pending',
    paymentStatus: existing?.paymentStatus || 'unpaid',
    payments: Array.isArray(existing?.payments) ? existing.payments : [],
    expenses: Array.isArray(existing?.expenses) ? existing.expenses : [],
    totalDiscountMinorUnits: draft.totalDiscountMinorUnits,
    createdAt: existing?.createdAt || now,
    updatedAt: now,
  };
}

exports.createBooking = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const {storeId, draft} = parseBookingDraft(request.data);
  const storeRef = db.collection('stores').doc(storeId);
  const bookingRef = storeRef.collection('bookings').doc(draft.id);
  const idempotencyRef = storeRef
    .collection('booking_idempotency')
    .doc(draft.idempotencyKey);

  try {
    return await db.runTransaction(async (transaction) => {
      const memberSnapshot = await transaction.get(
        storeRef.collection('members').doc(request.auth.uid),
      );
      assertBookingMembership(memberSnapshot, storeId, request.auth.uid);

      const idempotencySnapshot = await transaction.get(idempotencyRef);
      if (idempotencySnapshot.exists) {
        const existing = idempotencySnapshot.data() || {};
        if (existing.bookingId === draft.id) {
          return {
            status: 'already_created',
            bookingId: draft.id,
          };
        }
        conflict('The booking idempotency key is already assigned.');
      }

      const bookingSnapshot = await transaction.get(bookingRef);
      if (bookingSnapshot.exists) {
        conflict('The booking already exists.');
      }

      const catalog = await readCatalog(transaction, storeRef, draft);
      const now = Timestamp.now();
      transaction.set(
        bookingRef,
        storedBooking({
          storeId,
          draft,
          customer: catalog.customer,
          option: catalog.option,
          currency: catalog.currency,
          now,
        }),
      );
      transaction.set(idempotencyRef, {
        storeId,
        bookingId: draft.id,
        idempotencyKey: draft.idempotencyKey,
        createdAt: now,
        createdBy: request.auth.uid,
      });
      return {
        status: 'created',
        bookingId: draft.id,
      };
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('createBooking failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError('internal', 'The booking could not be created.');
  }
});

exports.updateBooking = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const {storeId, draft} = parseBookingDraft(request.data);
  const storeRef = db.collection('stores').doc(storeId);
  const bookingRef = storeRef.collection('bookings').doc(draft.id);

  try {
    return await db.runTransaction(async (transaction) => {
      const memberSnapshot = await transaction.get(
        storeRef.collection('members').doc(request.auth.uid),
      );
      assertBookingMembership(memberSnapshot, storeId, request.auth.uid);

      const bookingSnapshot = await transaction.get(bookingRef);
      if (!bookingSnapshot.exists) {
        throw new HttpsError('not-found', 'Booking was not found.');
      }
      const existing = bookingSnapshot.data() || {};
      if (existing.storeId !== storeId) {
        throw new HttpsError('permission-denied', 'Booking belongs to another store.');
      }
      if (TERMINAL_STATUSES.has(existing.status)) {
        conflict('Completed or cancelled bookings cannot be edited.');
      }

      const catalog = await readCatalog(transaction, storeRef, draft);
      if (
        draft.totalPriceMinorUnits <
        integerValue(existing.paidAmountMinorUnits || 0, 'Existing paid amount')
      ) {
        invalid('Booking total cannot be lower than the amount already paid.');
      }

      const now = Timestamp.now();
      transaction.set(
        bookingRef,
        storedBooking({
          storeId,
          draft,
          customer: catalog.customer,
          option: catalog.option,
          currency: catalog.currency,
          now,
          existing,
        }),
      );
      return {
        status: 'updated',
        bookingId: draft.id,
      };
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('updateBooking failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError('internal', 'The booking could not be updated.');
  }
});

exports.transitionBooking = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Authentication is required.');
  }
  const command = requireObject(request.data, 'command');
  const storeId = safeId(command.storeId, 'storeId');
  const bookingId = safeId(command.bookingId, 'bookingId');
  const nextStatus = requiredString(command.status, 'status');
  const allowedStatuses = new Set([
    'pending',
    'confirmed',
    'completed',
    'cancelled',
  ]);
  if (!allowedStatuses.has(nextStatus)) {
    invalid('Unsupported booking status.');
  }

  const storeRef = db.collection('stores').doc(storeId);
  const bookingRef = storeRef.collection('bookings').doc(bookingId);

  try {
    return await db.runTransaction(async (transaction) => {
      const memberSnapshot = await transaction.get(
        storeRef.collection('members').doc(request.auth.uid),
      );
      assertBookingMembership(memberSnapshot, storeId, request.auth.uid);

      const bookingSnapshot = await transaction.get(bookingRef);
      if (!bookingSnapshot.exists) {
        throw new HttpsError('not-found', 'Booking was not found.');
      }
      const booking = bookingSnapshot.data() || {};
      if (booking.storeId !== storeId) {
        throw new HttpsError('permission-denied', 'Booking belongs to another store.');
      }

      const allowedNext = {
        pending: new Set(['confirmed', 'cancelled']),
        confirmed: new Set(['completed', 'cancelled']),
        completed: new Set(),
        cancelled: new Set(),
      };
      if (!allowedNext[booking.status]?.has(nextStatus)) {
        conflict('This booking status transition is not allowed.');
      }

      transaction.update(bookingRef, {
        status: nextStatus,
        updatedAt: Timestamp.now(),
      });
      return {
        status: nextStatus,
        bookingId,
      };
    });
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    console.error('transitionBooking failed', {
      message: error.message,
      stack: error.stack,
    });
    throw new HttpsError(
      'internal',
      'The booking status could not be changed.',
    );
  }
});

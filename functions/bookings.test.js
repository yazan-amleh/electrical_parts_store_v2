'use strict';

const assert = require('node:assert/strict');
const {after, describe, it} = require('node:test');

const admin = require('firebase-admin');
const functions = require('./index');

const db = admin.firestore();
const STORE_ID = 'booking-lifecycle-test';
const USER_ID = 'sales-1';
const START_AT = '2026-02-15T10:00:00.000Z';

async function seedStore() {
  const storeRef = db.collection('stores').doc(STORE_ID);
  await db.recursiveDelete(storeRef);
  const batch = db.batch();

  batch.set(storeRef, {
    storeId: STORE_ID,
    name: STORE_ID,
    currency: 'ILS',
  });
  batch.set(storeRef.collection('members').doc(USER_ID), {
    storeId: STORE_ID,
    role: 'sales',
    isActive: true,
  });
  batch.set(storeRef.collection('booking_customers').doc('customer-1'), {
    storeId: STORE_ID,
    name: 'Customer One',
    phoneNumber: '0590000000',
    email: 'customer@example.test',
  });
  batch.set(storeRef.collection('photography_options').doc('option-1'), {
    storeId: STORE_ID,
    name: 'Studio Session',
    description: 'One hour session',
    priceMinorUnits: 10000,
    currency: 'ILS',
    durationMinutes: 60,
    isActive: true,
  });

  await batch.commit();
}

function createPayload(overrides = {}) {
  return {
    storeId: STORE_ID,
    booking: {
      id: 'booking-1',
      idempotencyKey: 'booking-key-1',
      customerId: 'customer-1',
      photographyOptionId: 'option-1',
      startAt: START_AT,
      durationMinutes: 60,
      location: 'Main studio',
      notes: 'Bring the sample album',
      totalPriceMinorUnits: 10000,
      totalDiscountMinorUnits: 0,
      depositAmountMinorUnits: 2500,
      ...overrides,
    },
  };
}

function authRequest(data) {
  return {
    data,
    auth: {
      uid: USER_ID,
      token: {uid: USER_ID},
    },
  };
}

async function invoke(callable, data) {
  return callable.run(authRequest(data));
}

describe('booking lifecycle scenarios', () => {
  after(async () => {
    await admin.app().delete();
  });

  it('creates once under concurrent retries, updates, and transitions', async () => {
    await seedStore();

    const payload = createPayload();
    const results = await Promise.all([
      invoke(functions.createBooking, payload),
      invoke(functions.createBooking, payload),
    ]);
    assert.equal(results[0].bookingId, 'booking-1');
    assert.equal(results[1].bookingId, 'booking-1');
    assert.ok(
      ['created', 'already_created'].includes(results[0].status),
    );
    assert.ok(
      ['created', 'already_created'].includes(results[1].status),
    );

    const storeRef = db.collection('stores').doc(STORE_ID);
    const bookingRef = storeRef.collection('bookings').doc('booking-1');
    const booking = await bookingRef.get();
    assert.equal(booking.exists, true);
    assert.equal(booking.data().status, 'pending');
    assert.equal(booking.data().customerName, 'Customer One');
    assert.equal(booking.data().totalPriceMinorUnits, 10000);

    const idempotency = await storeRef.collection('booking_idempotency').get();
    assert.equal(idempotency.size, 1);

    const replay = await invoke(functions.createBooking, payload);
    assert.equal(replay.status, 'already_created');

    await invoke(
      functions.updateBooking,
      createPayload({location: 'Second studio'}),
    );
    const updated = await bookingRef.get();
    assert.equal(updated.data().location, 'Second studio');

    const confirmed = await invoke(functions.transitionBooking, {
      storeId: STORE_ID,
      bookingId: 'booking-1',
      status: 'confirmed',
    });
    assert.equal(confirmed.status, 'confirmed');

    const completed = await invoke(functions.transitionBooking, {
      storeId: STORE_ID,
      bookingId: 'booking-1',
      status: 'completed',
    });
    assert.equal(completed.status, 'completed');

    const finalBooking = await bookingRef.get();
    assert.equal(finalBooking.data().status, 'completed');
  });
});

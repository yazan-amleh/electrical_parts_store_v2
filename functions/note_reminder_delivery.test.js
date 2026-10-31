'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  nextOccurrence,
  reminderEventId,
  noteLocator,
  queueDueReminders,
  claimReminder,
  deliverQueuedReminders,
} = require('./note_reminder_delivery');

const Timestamp = {fromDate: (value) => value};

class FakeRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split('/').at(-1);
  }

  collection(name) {
    return new FakeCollection(this.db, this.path + '/' + name);
  }

  async get() {
    const value = this.db.docs.get(this.path);
    return {
      id: this.id,
      ref: this,
      exists: value !== undefined,
      data: () => value,
    };
  }

  async update(fields) {
    const old = this.db.docs.get(this.path);
    if (!old) throw new Error('Missing document: ' + this.path);
    this.db.docs.set(this.path, {...old, ...fields});
  }
}

class FakeCollection {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    return new FakeRef(this.db, this.path + '/' + id);
  }

  where(field, operator, value) {
    return new FakeQuery(this.db, this.path.split('/').at(-1), this.path)
      .where(field, operator, value);
  }
}

class FakeQuery {
  constructor(db, name, collectionPath = null) {
    this.db = db;
    this.name = name;
    this.collectionPath = collectionPath;
    this.filters = [];
    this.max = Infinity;
  }

  where(field, op, value) {
    this.filters.push([field, op, value]);
    return this;
  }

  limit(value) {
    this.max = value;
    return this;
  }

  async get() {
    const matches = [];
    for (const [path, data] of this.db.docs) {
      const segments = path.split('/');
      if (segments.length < 4 ||
          segments.at(-2) !== this.name ||
          (this.collectionPath && path.slice(0, path.lastIndexOf('/')) !==
            this.collectionPath)) continue;
      if (!this.filters.every(([field, op, wanted]) => {
        const actual = data[field];
        if (actual == null) return false;
        if (op === '<=') return actual <= wanted;
        if (op === 'in') return wanted.includes(actual);
        if (op === '==') return actual === wanted;
        throw new Error('Unsupported operator ' + op);
      })) continue;
      const ref = new FakeRef(this.db, path);
      matches.push(await ref.get());
    }
    return {docs: matches.slice(0, this.max)};
  }
}

class FakeDb {
  constructor() {
    this.docs = new Map();
  }

  collection(name) {
    return new FakeCollection(this, name);
  }

  collectionGroup(name) {
    return new FakeQuery(this, name);
  }

  async runTransaction(handler) {
    return handler({
      get: (ref) => ref.get(),
      create: (ref, value) => {
        if (this.docs.has(ref.path)) throw new Error('Duplicate event');
        this.docs.set(ref.path, value);
      },
      update: (ref, fields) => ref.update(fields),
    });
  }

  batch() {
    const deletes = [];
    return {
      delete: (ref) => deletes.push(ref.path),
      commit: async () => {
        for (const path of deletes) this.docs.delete(path);
      },
    };
  }
}

test('daily, weekly and monthly UTC occurrences use stable anchors', () => {
  const first = new Date('2026-01-31T09:30:00Z');
  assert.equal(
    nextOccurrence(first, 'daily', new Date('2026-02-02T10:00:00Z'))
      .toISOString(),
    '2026-02-03T09:30:00.000Z',
  );
  assert.equal(
    nextOccurrence(first, 'weekly', new Date('2026-02-07T10:00:00Z'))
      .toISOString(),
    '2026-02-14T09:30:00.000Z',
  );
  assert.equal(
    nextOccurrence(first, 'monthly', new Date('2026-02-01T00:00:00Z'))
      .toISOString(),
    '2026-02-28T09:30:00.000Z',
  );
  assert.equal(
    nextOccurrence(first, 'monthly', new Date('2026-03-01T00:00:00Z'))
      .toISOString(),
    '2026-03-31T09:30:00.000Z',
  );
  assert.equal(nextOccurrence(first, 'none', new Date('2026-02-01')), null);
});

test('reminder IDs are repeat-stable and isolated per tenant and owner', () => {
  const event = {
    storeId: 'store-a',
    userId: 'user-1',
    noteId: 'note-1',
    scheduledFor: new Date('2026-10-31T10:00:00Z'),
  };
  assert.equal(reminderEventId(event), reminderEventId({...event}));
  assert.notEqual(reminderEventId(event),
    reminderEventId({...event, storeId: 'store-b'}));
  assert.notEqual(reminderEventId(event),
    reminderEventId({...event, userId: 'user-2'}));
  assert.deepEqual(noteLocator(
    {path: 'stores/store-a/notes/note-1'},
    {storeId: 'store-a', userId: 'user-1'},
  ), {storeId: 'store-a', userId: 'user-1', noteId: 'note-1'});
  assert.equal(noteLocator(
    {path: 'stores/store-a/notes/note-1'},
    {storeId: 'store-b', userId: 'user-1'},
  ), null);
});

test('queue and dispatch notify once for a due note; replay does not enqueue twice', async () => {
  const db = new FakeDb();
  const now = new Date('2026-10-31T12:00:00Z');
  db.docs.set('stores/store-a/notes/note-1', {
    storeId: 'store-a',
    userId: 'user-1',
    title: 'متابعة المخزون',
    content: 'جرد أسبوعي',
    reminderAt: new Date('2026-10-31T11:59:00Z'),
    reminderNextAt: new Date('2026-10-31T11:59:00Z'),
    reminderRepeat: 'none',
    isArchived: false,
    isCompleted: false,
  });
  db.docs.set('stores/store-a/members/user-1', {isActive: true});
  db.docs.set('stores/store-a/notificationTokens/token-a', {
    userId: 'user-1',
    token: 'valid-device-token',
  });
  const queued = await queueDueReminders({db, Timestamp, now});
  assert.equal(queued.queued, 1);
  assert.equal(db.docs.get('stores/store-a/notes/note-1').reminderNextAt, null);
  assert.equal((await queueDueReminders({db, Timestamp, now})).queued, 0);
  let count = 0;
  const result = await deliverQueuedReminders({
    db,
    Timestamp,
    now,
    messaging: {
      sendEachForMulticast: async (payload) => {
        count++;
        assert.deepEqual(payload.tokens, ['valid-device-token']);
        assert.equal(payload.data.storeId, 'store-a');
        assert.equal(payload.data.noteId, 'note-1');
        return {successCount: 1, failureCount: 0, responses: [{}]};
      },
    },
  });
  assert.equal(result.processed, 1);
  assert.equal(count, 1);
  assert.equal((await deliverQueuedReminders({
    db, Timestamp, now, messaging: {sendEachForMulticast: () => {
      throw Error('Duplicate dispatch');
    }},
  })).processed, 0);
});

test('claims use leases and stop when the retry ceiling is reached', async () => {
  const db = new FakeDb();
  const now = new Date('2026-10-31T12:00:00Z');
  const ref = db.collection('stores').doc('store-a')
    .collection('reminderNotifications').doc('event-1');
  db.docs.set(ref.path, {
    storeId: 'store-a',
    userId: 'user-1',
    status: 'queued',
    attempts: 0,
  });
  const first = await claimReminder({db, Timestamp, ref, now});
  assert.equal(first.attempts, 1);
  assert.equal(await claimReminder({db, Timestamp, ref, now}), null);
  const later = new Date(now.getTime() + 3 * 60 * 1000);
  const second = await claimReminder({db, Timestamp, ref, now: later});
  assert.equal(second.attempts, 2);
  const third = await claimReminder({
    db, Timestamp, ref, now: new Date(later.getTime() + 3 * 60 * 1000),
  });
  assert.equal(third.attempts, 3);
  assert.equal(await claimReminder({
    db, Timestamp, ref, now: new Date(later.getTime() + 6 * 60 * 1000),
  }), null);
  assert.equal(db.docs.get(ref.path).status, 'failed');
});

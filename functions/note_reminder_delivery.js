'use strict';

const {createHash} = require('node:crypto');

const MAX_DUE_PER_RUN = 60;
const MAX_SEND_PER_RUN = 60;
const MAX_LATENESS_MS = 24 * 60 * 60 * 1000;
const LEASE_MS = 2 * 60 * 1000;
const RETRY_LIMIT = 3;

function asDate(value) {
  if (value instanceof Date && !Number.isNaN(value.getTime())) return value;
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  if (typeof value === 'string') {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

// Preserve the original UTC wall-clock time, including leap/month-end cases.
function nextOccurrence(firstValue, repeat, afterValue) {
  const first = asDate(firstValue);
  const after = asDate(afterValue);
  if (!first || !after) return null;
  if (first > after) return first;
  if (repeat === 'none' || !['daily', 'weekly', 'monthly'].includes(repeat)) {
    return null;
  }
  if (repeat === 'daily' || repeat === 'weekly') {
    const step = (repeat === 'daily' ? 1 : 7) * 86400000;
    const count = Math.floor((after.getTime() - first.getTime()) / step) + 1;
    return new Date(first.getTime() + count * step);
  }
  const baseMonth = first.getUTCFullYear() * 12 + first.getUTCMonth();
  const afterMonth = after.getUTCFullYear() * 12 + after.getUTCMonth();
  function monthly(monthOffset) {
    const m = baseMonth + monthOffset;
    const y = Math.floor(m / 12);
    const month = m % 12;
    const last = new Date(Date.UTC(y, month + 1, 0)).getUTCDate();
    return new Date(Date.UTC(
      y, month, Math.min(first.getUTCDate(), last),
      first.getUTCHours(), first.getUTCMinutes(), first.getUTCSeconds(),
      first.getUTCMilliseconds(),
    ));
  }
  let offset = Math.max(0, afterMonth - baseMonth);
  let candidate = monthly(offset);
  if (candidate <= after) candidate = monthly(offset + 1);
  return candidate;
}

function reminderEventId({storeId, userId, noteId, scheduledFor}) {
  const scheduled = asDate(scheduledFor);
  if (!storeId || !userId || !noteId || !scheduled) {
    throw new TypeError('A reminder must have a stable owner and due time.');
  }
  return createHash('sha256')
    .update(JSON.stringify([storeId, userId, noteId, scheduled.toISOString()]))
    .digest('hex');
}

function noteLocator(ref, data) {
  const parts = ref?.path?.split('/') ?? [];
  if (parts.length !== 4 || parts[0] !== 'stores' ||
      parts[2] !== 'notes' || parts[1] !== data?.storeId ||
      typeof data.userId !== 'string' || !data.userId.trim()) {
    return null;
  }
  return {storeId: parts[1], noteId: parts[3], userId: data.userId};
}

function isActiveNote(note) {
  return note?.isCompleted !== true && note?.isArchived !== true &&
    typeof note?.title === 'string' && note.title.trim().length > 0;
}

async function queueDueReminders({db, Timestamp, now = new Date()}) {
  const point = Timestamp.fromDate(now);
  const snapshot = await db.collectionGroup('notes')
    .where('reminderNextAt', '<=', point)
    .limit(MAX_DUE_PER_RUN)
    .get();
  let queued = 0;
  for (const doc of snapshot.docs) {
    const locator = noteLocator(doc.ref, doc.data());
    if (!locator) continue;
    const {storeId, noteId, userId} = locator;
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists) return;
      const note = fresh.data() || {};
      if (!noteLocator(doc.ref, note) || note.userId !== userId) return;
      const due = asDate(note.reminderNextAt);
      if (!due || due > now) return;

      const repeat = typeof note.reminderRepeat === 'string'
        ? note.reminderRepeat : 'none';
      const next = isActiveNote(note)
        ? nextOccurrence(note.reminderAt, repeat, now)
        : null;
      const updated = {
        reminderNextAt: next ? Timestamp.fromDate(next) : null,
        reminderProcessedAt: point,
      };

      if (!isActiveNote(note) ||
          now.getTime() - due.getTime() > MAX_LATENESS_MS) {
        tx.update(doc.ref, updated);
        return;
      }
      const eventId = reminderEventId({
        storeId, userId, noteId, scheduledFor: due,
      });
      const eventRef = db.collection('stores').doc(storeId)
        .collection('reminderNotifications').doc(eventId);
      const existing = await tx.get(eventRef);
      if (!existing.exists) {
        tx.create(eventRef, {
          storeId,
          userId,
          noteId,
          title: note.title.trim().slice(0, 100),
          body: typeof note.content === 'string' && note.content.trim()
            ? note.content.trim().slice(0, 160) : 'حان وقت متابعة ملاحظتك.',
          scheduledFor: Timestamp.fromDate(due),
          createdAt: point,
          status: 'queued',
          attempts: 0,
        });
        queued++;
      }
      tx.update(doc.ref, updated);
    });
  }
  return {examined: snapshot.docs.length, queued};
}

async function claimReminder({db, Timestamp, ref, now}) {
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) return null;
    const value = doc.data() || {};
    const parts = ref.path.split('/');
    if (parts.length !== 4 || parts[0] !== 'stores' ||
        parts[2] !== 'reminderNotifications' ||
        parts[1] !== value.storeId ||
        typeof value.userId !== 'string' || !value.userId) {
      return null;
    }
    if (!['queued', 'sending'].includes(value.status)) return null;
    const leasedUntil = asDate(value.leaseUntil);
    if (value.status === 'sending' && leasedUntil && leasedUntil > now) {
      return null;
    }
    const attempts = (Number.isSafeInteger(value.attempts)
      ? value.attempts : 0);
    if (attempts >= RETRY_LIMIT) {
      tx.update(ref, {status: 'failed', leaseUntil: null});
      return null;
    }
    tx.update(ref, {
      status: 'sending',
      attempts: attempts + 1,
      leaseUntil: Timestamp.fromDate(new Date(now.getTime() + LEASE_MS)),
    });
    return {...value, eventId: ref.id, attempts: attempts + 1};
  });
}

async function deliverQueuedReminders({
  db, Timestamp, messaging, now = new Date(),
}) {
  const snapshot = await db.collectionGroup('reminderNotifications')
    .where('status', 'in', ['queued', 'sending'])
    .limit(MAX_SEND_PER_RUN)
    .get();
  let processed = 0;
  for (const doc of snapshot.docs) {
    const event = await claimReminder({db, Timestamp, ref: doc.ref, now});
    if (!event) continue;
    const {storeId, userId, eventId, noteId} = event;
    try {
      // Membership may have been revoked since the reminder was queued.
      const member = await db.collection('stores').doc(storeId)
        .collection('members').doc(userId).get();
      if (!member.exists || member.data()?.isActive !== true) {
        await doc.ref.update({
          status: 'skipped',
          leaseUntil: null,
          reason: 'inactive-member',
        });
        continue;
      }
      const tokensSnapshot = await db.collection('stores').doc(storeId)
        .collection('notificationTokens')
        .where('userId', '==', userId).limit(250).get();
      const tokenMap = new Map();
      for (const item of tokensSnapshot.docs) {
        const token = item.data()?.token;
        if (typeof token === 'string' && token) tokenMap.set(token, item.ref);
      }
      if (tokenMap.size === 0) {
        await doc.ref.update({
          status: 'noDevice',
          leaseUntil: null,
          successCount: 0,
        });
        processed++;
        continue;
      }
      const tokens = [...tokenMap.keys()];
      const response = await messaging.sendEachForMulticast({
        tokens,
        notification: {title: event.title, body: event.body},
        data: {type: 'noteReminder', storeId, noteId, eventId},
      });
      const invalid = [];
      for (let i = 0; i < response.responses.length; i++) {
        const code = response.responses[i].error?.code;
        if (code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token') {
          invalid.push(tokenMap.get(tokens[i]));
        }
      }
      if (invalid.length > 0) {
        const batch = db.batch();
        for (const ref of invalid) batch.delete(ref);
        await batch.commit();
      }
      const hasSuccess = response.successCount > 0;
      const retry = !hasSuccess &&
        invalid.length < tokens.length && event.attempts < RETRY_LIMIT;
      await doc.ref.update({
        status: retry ? 'queued' :
          hasSuccess ? 'sent' : 'failed',
        leaseUntil: null,
        successCount: response.successCount,
        failureCount: response.failureCount,
        sentAt: hasSuccess ? Timestamp.fromDate(new Date()) : null,
      });
      processed++;
    } catch (error) {
      // A failed send remains retryable on the next run, with a bounded
      // attempt count and lease to prevent concurrent jobs from duplicating it.
      await doc.ref.update({
        status: event.attempts >= RETRY_LIMIT ? 'failed' : 'queued',
        leaseUntil: null,
        lastError: String(error?.message ?? error).slice(0, 160),
      });
    }
  }
  return {examined: snapshot.docs.length, processed};
}

async function runNoteReminderCycle({db, Timestamp, messaging, now = new Date()}) {
  const queued = await queueDueReminders({db, Timestamp, now});
  const delivered = await deliverQueuedReminders({
    db, Timestamp, messaging, now,
  });
  return {...queued, delivered};
}

module.exports = {
  asDate,
  nextOccurrence,
  reminderEventId,
  noteLocator,
  queueDueReminders,
  claimReminder,
  deliverQueuedReminders,
  runNoteReminderCycle,
};

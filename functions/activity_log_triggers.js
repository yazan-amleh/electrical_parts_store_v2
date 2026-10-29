'use strict';

const crypto = require('node:crypto');

function eventDocumentId(event) {
  const raw = typeof event?.id === 'string' && event.id.length > 0
    ? event.id
    : JSON.stringify({
        params: event?.params ?? {},
        time: event?.time ?? '',
      });
  return crypto.createHash('sha256').update(raw).digest('hex');
}

function currentSnapshot(event) {
  if (event?.data?.after) {
    return event.data.after.exists ? event.data.after : null;
  }
  return event?.data?.exists ? event.data : null;
}

function trustedTimestamp(data, event, Timestamp) {
  for (const key of ['postedAt', 'occurredAt', 'updatedAt', 'createdAt']) {
    const value = data?.[key];
    if (value && typeof value.toDate === 'function') {
      return value;
    }
  }
  const parsed = new Date(event?.time ?? '');
  if (!Number.isNaN(parsed.getTime())) {
    return Timestamp.fromDate(parsed);
  }
  return Timestamp.now();
}

function actorId(data) {
  for (const key of ['updatedBy', 'createdBy', 'postedBy', 'userId']) {
    const value = data?.[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  return null;
}

async function writeActivity({
  db,
  Timestamp,
  event,
  type,
  description,
  metadata = {},
}) {
  const storeId = event?.params?.storeId;
  if (typeof storeId !== 'string' || storeId.length === 0) {
    throw new Error('Activity event has no storeId.');
  }
  const snapshot = currentSnapshot(event);
  if (!snapshot) {
    return {skipped: true};
  }
  const data = snapshot.data() || {};
  if (data.storeId != null && data.storeId !== storeId) {
    throw new Error('Activity source belongs to another store.');
  }

  const activityId = eventDocumentId(event);
  const activityRef = db
    .collection('stores')
    .doc(storeId)
    .collection('activity_logs')
    .doc(activityId);
  const timestamp = trustedTimestamp(data, event, Timestamp);
  const userId = actorId(data);

  await activityRef.set({
    storeId,
    type,
    description:
      typeof description === 'function'
        ? description(data, event.params || {})
        : description,
    timestamp,
    userId,
    userName: null,
    metadata: {
      ...metadata,
      sourceId: snapshot.id,
    },
    eventId: event?.id ?? null,
    createdAt: timestamp,
  });

  return {
    skipped: false,
    activityId,
  };
}

module.exports = {
  eventDocumentId,
  writeActivity,
};

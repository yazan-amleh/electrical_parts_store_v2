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

function activitySnapshot(event) {
  const after = event?.data?.after;
  if (after) {
    if (after.exists) {
      return after;
    }
    const before = event?.data?.before;
    return before?.exists ? before : null;
  }

  const snapshot = event?.data;
  return snapshot?.exists ? snapshot : null;
}

function changeKind(event) {
  const before = event?.data?.before;
  const after = event?.data?.after;
  if (!before && !after) {
    return 'created';
  }

  const beforeExists = before?.exists === true;
  const afterExists = after?.exists === true;
  if (!beforeExists && afterExists) {
    return 'created';
  }
  if (beforeExists && !afterExists) {
    return 'deleted';
  }
  return 'updated';
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

  const snapshot = activitySnapshot(event);
  if (!snapshot) {
    return {skipped: true};
  }

  const data = snapshot.data() || {};
  if (data.storeId != null && data.storeId !== storeId) {
    throw new Error('Activity source belongs to another store.');
  }

  const operation = changeKind(event);
  const resolvedType = typeof type === 'function'
    ? type(data, event.params || {}, operation)
    : type;
  const resolvedDescription = typeof description === 'function'
    ? description(data, event.params || {}, operation)
    : description;

  if (typeof resolvedType !== 'string' || resolvedType.length === 0) {
    throw new Error('Activity event has no valid type.');
  }
  if (
    typeof resolvedDescription !== 'string' ||
    resolvedDescription.trim().length === 0
  ) {
    throw new Error('Activity event has no valid description.');
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
    type: resolvedType,
    description: resolvedDescription.trim(),
    timestamp,
    userId,
    userName: null,
    metadata: {
      ...metadata,
      sourceId: snapshot.id,
      operation,
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
  activitySnapshot,
  changeKind,
  eventDocumentId,
  writeActivity,
};

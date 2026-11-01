'use strict';

const {createHash} = require('node:crypto');

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return '[' + value.map(canonicalJson).join(',') + ']';
  }
  if (value && typeof value === 'object') {
    return '{' + Object.keys(value).sort().map((key) =>
      JSON.stringify(key) + ':' + canonicalJson(value[key])).join(',') + '}';
  }
  return JSON.stringify(value);
}

function fingerprint(value) {
  return createHash('sha256').update(canonicalJson(value)).digest('hex');
}

// Drafts do not touch ledgers. Approval alone invokes the canonical
// postPartyPaymentInTransaction within the SAME Firestore transaction.
function createVoucherDraftHandlers({
  db,
  FieldValue,
  HttpsError,
  parsePartyPaymentCommand,
  postPartyPaymentInTransaction,
}) {
  const authorRoles = new Set(['owner', 'admin', 'accountant']);
  const approvalRoles = new Set(['owner', 'admin']);

  function validatedIdentity(request) {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }
    const raw = request.data;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
      throw new HttpsError('invalid-argument', 'Request must be an object.');
    }
    const storeId = raw.storeId;
    const draftId = raw.draftId;
    for (const [label, id] of [['storeId', storeId], ['draftId', draftId]]) {
      if (typeof id !== 'string' || !id.trim() || id.includes('/')) {
        throw new HttpsError('invalid-argument', label + ' is invalid.');
      }
    }
    return {storeId, draftId, userId: request.auth.uid};
  }

  function refs(storeId, draftId, userId) {
    const store = db.collection('stores').doc(storeId);
    return {
      draft: store.collection('voucher_drafts').doc(draftId),
      member: store.collection('members').doc(userId),
    };
  }

  function authorize(snapshot, storeId, roles) {
    const data = snapshot.exists ? snapshot.data() : null;
    if (!data || data.isActive !== true ||
        (data.storeId && data.storeId !== storeId) ||
        !roles.has(data.role)) {
      throw new HttpsError('permission-denied', 'Voucher action is not allowed.');
    }
  }

  function conflict(message) {
    throw new HttpsError('failed-precondition', message);
  }

  // Canonicalize all fields from the same parser used by the posted command.
  function canonicalRequest(command) {
    return {
      storeId: command.storeId,
      payment: {
        ...command.payment,
        postedAt: command.payment.postedAt.toISOString(),
        dueDate: command.payment.dueDate?.toISOString() || null,
      },
      postingAccounts: {...command.accounts},
    };
  }

  async function save(request) {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Authentication is required.');
    }
    const command = parsePartyPaymentCommand(request.data);
    const {storeId, payment} = command;
    const draftId = payment.id;
    const {draft, member} = refs(storeId, draftId, request.auth.uid);
    const financialRequest = canonicalRequest(command);
    const requestFingerprint = fingerprint(financialRequest);
    return db.runTransaction(async (tx) => {
      const [membership, existing] = await Promise.all([
        tx.get(member),
        tx.get(draft),
      ]);
      authorize(membership, storeId, authorRoles);
      if (existing.exists) {
        const current = existing.data();
        if (current.createdBy === request.auth.uid &&
            current.requestFingerprint === requestFingerprint) {
          return {draftId, status: current.status};
        }
        conflict('Voucher draft id is already in use.');
      }
      tx.create(draft, {
        storeId,
        createdBy: request.auth.uid,
        status: 'draft',
        financialRequest,
        requestFingerprint,
        revision: 1,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {draftId, status: 'draft'};
    });
  }

  async function update(request) {
    const {storeId, draftId, userId} = validatedIdentity(request);
    const raw = request.data;
    if (!Number.isSafeInteger(raw.expectedRevision) ||
        raw.expectedRevision < 1) {
      throw new HttpsError('invalid-argument', 'Expected revision is invalid.');
    }
    const amount = raw.amountMinorUnits;
    if (!Number.isSafeInteger(amount) || amount <= 0) {
      throw new HttpsError('invalid-argument', 'Voucher amount must be positive.');
    }
    if (raw.description != null &&
        (typeof raw.description !== 'string' ||
          raw.description.length > 500)) {
      throw new HttpsError('invalid-argument', 'Description is too long.');
    }
    const {draft, member} = refs(storeId, draftId, userId);
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member),
        tx.get(draft),
      ]);
      authorize(membership, storeId, authorRoles);
      if (!snapshot.exists) conflict('Voucher draft was not found.');
      const data = snapshot.data();
      if (data.storeId !== storeId || data.createdBy !== userId) {
        throw new HttpsError('permission-denied', 'Only the creator can edit.');
      }
      if (data.status !== 'draft') {
        conflict('Only unsent voucher drafts can be edited.');
      }
      const revision = data.revision || 1;
      if (revision !== raw.expectedRevision) {
        conflict('Voucher draft was changed by another session.');
      }
      if (!data.financialRequest ||
          data.financialRequest.payment?.id !== draftId ||
          data.financialRequest.storeId !== storeId ||
          fingerprint(data.financialRequest) !== data.requestFingerprint) {
        conflict('Stored financial command is not valid.');
      }
      const candidate = {
        ...data.financialRequest,
        payment: {
          ...data.financialRequest.payment,
          amountMinorUnits: amount,
          description: raw.description?.trim() || null,
        },
      };
      const parsed = parsePartyPaymentCommand(candidate);
      const financialRequest = canonicalRequest(parsed);
      tx.update(draft, {
        financialRequest,
        requestFingerprint: fingerprint(financialRequest),
        revision: revision + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {draftId, status: 'draft', revision: revision + 1};
    });
  }

  async function submit(request) {
    const {storeId, draftId, userId} = validatedIdentity(request);
    const {draft, member} = refs(storeId, draftId, userId);
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member),
        tx.get(draft),
      ]);
      authorize(membership, storeId, authorRoles);
      if (!snapshot.exists) conflict('Voucher draft was not found.');
      const data = snapshot.data();
      if (data.storeId !== storeId || data.createdBy !== userId) {
        throw new HttpsError('permission-denied', 'Only the creator can submit.');
      }
      if (data.status === 'pendingApproval') {
        return {draftId, status: 'pendingApproval'};
      }
      if (data.status !== 'draft') {
        conflict('Only a draft can be submitted for approval.');
      }
      tx.update(draft, {
        status: 'pendingApproval',
        submittedBy: userId,
        submittedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {draftId, status: 'pendingApproval'};
    });
  }

  async function approve(request) {
    const {storeId, draftId, userId} = validatedIdentity(request);
    const {draft, member} = refs(storeId, draftId, userId);
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member),
        tx.get(draft),
      ]);
      authorize(membership, storeId, approvalRoles);
      if (!snapshot.exists) conflict('Voucher draft was not found.');
      const data = snapshot.data();
      if (data.storeId !== storeId) {
        throw new HttpsError('permission-denied', 'Voucher belongs to another store.');
      }
      if (data.status === 'posted') {
        return {draftId, status: 'posted', paymentId: draftId};
      }
      if (data.status !== 'pendingApproval') {
        conflict('Only submitted vouchers can be approved.');
      }
      if (!data.financialRequest ||
          data.financialRequest.payment?.id !== draftId ||
          data.financialRequest.storeId !== storeId) {
        conflict('Voucher identity or stored financial command has changed.');
      }
      if (fingerprint(data.financialRequest) !== data.requestFingerprint) {
        conflict('Financial command fingerprint does not match the draft.');
      }
      const financialCommand = parsePartyPaymentCommand(data.financialRequest);
      const posted = await postPartyPaymentInTransaction(
        tx, userId, financialCommand,
      );
      // No mutation is committed if posting fails. Firestore transaction
      // retries will replay the same original payment/idempotency key.
      tx.update(draft, {
        status: 'posted',
        approvedBy: userId,
        approvedAt: FieldValue.serverTimestamp(),
        selfApproved: userId === data.createdBy,
        paymentId: posted.paymentId,
        journalEntryId: posted.journalEntryId,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        draftId,
        status: 'posted',
        paymentId: posted.paymentId,
        journalEntryId: posted.journalEntryId,
      };
    });
  }

  async function reject(request) {
    const {storeId, draftId, userId} = validatedIdentity(request);
    const rawReason = request.data.reason;
    const reason = typeof rawReason === 'string' ? rawReason.trim() : '';
    if (!reason || reason.length > 500) {
      throw new HttpsError(
        'invalid-argument', 'A rejection reason up to 500 characters is required.',
      );
    }
    const {draft, member} = refs(storeId, draftId, userId);
    return db.runTransaction(async (tx) => {
      const [membership, snapshot] = await Promise.all([
        tx.get(member),
        tx.get(draft),
      ]);
      authorize(membership, storeId, approvalRoles);
      if (!snapshot.exists) conflict('Voucher draft was not found.');
      const data = snapshot.data();
      if (data.storeId !== storeId || data.status !== 'pendingApproval') {
        conflict('Only submitted vouchers can be rejected.');
      }
      tx.update(draft, {
        status: 'rejected',
        rejectedBy: userId,
        rejectedAt: FieldValue.serverTimestamp(),
        rejectionReason: reason,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {draftId, status: 'rejected'};
    });
  }

  return {save, update, submit, approve, reject};
}

module.exports = {createVoucherDraftHandlers};

'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {createVoucherDraftHandlers} = require('./voucher_drafts');

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function setup() {
  const documents = new Map();
  const ref = (path) => ({
    path,
    collection(name) {
      return ref(path + '/' + name);
    },
    doc(id) {
      return ref(path + '/' + id);
    },
  });
  const db = {
    collection(name) {
      return ref(name);
    },
    async runTransaction(operation) {
      const writes = [];
      const tx = {
        async get(target) {
          const data = documents.get(target.path);
          return {
            exists: !!data,
            data: () => (data == null ? undefined : structuredClone(data)),
          };
        },
        create(target, data) {
          writes.push({type: 'create', target, data});
        },
        update(target, data) {
          writes.push({type: 'update', target, data});
        },
      };
      const result = await operation(tx);
      for (const write of writes) {
        if (write.type === 'create') {
          if (documents.has(write.target.path)) throw Error('Already exists');
          documents.set(write.target.path, structuredClone(write.data));
        } else {
          documents.set(write.target.path, {
            ...documents.get(write.target.path),
            ...structuredClone(write.data),
          });
        }
      }
      return result;
    },
  };
  documents.set('stores/store-a/members/creator', {
    storeId: 'store-a', role: 'accountant', isActive: true,
  });
  documents.set('stores/store-a/members/approver', {
    storeId: 'store-a', role: 'owner', isActive: true,
  });
  documents.set('stores/store-a/members/outsider', {
    storeId: 'store-a', role: 'sales', isActive: true,
  });
  let postCount = 0;
  let shouldFailPosting = false;
  const handlers = createVoucherDraftHandlers({
    db,
    FieldValue: {serverTimestamp: () => 'now'},
    HttpsError,
    parsePartyPaymentCommand: (data) => {
      const p = data.payment;
      if (!p || !p.id || !p.idempotencyKey || p.amountMinorUnits <= 0) {
        throw new HttpsError('invalid-argument', 'Invalid financial data');
      }
      return {
        storeId: data.storeId,
        payment: {
          ...p,
          postedAt: new Date(p.postedAt),
          dueDate: p.dueDate ? new Date(p.dueDate) : null,
        },
        accounts: {...data.postingAccounts},
      };
    },
    postPartyPaymentInTransaction: async (_tx, userId, command) => {
      if (shouldFailPosting) throw new HttpsError('failed-precondition', 'Closed period');
      assert.equal(userId, 'approver');
      postCount++;
      return {
        status: 'posted',
        paymentId: command.payment.id,
        journalEntryId: command.payment.id + '-journal',
      };
    },
  });
  const request = (uid, data) => ({auth: {uid}, data});
  const command = {
    storeId: 'store-a',
    payment: {
      id: 'voucher-1',
      idempotencyKey: 'voucher-1',
      postedAt: '2026-10-26T12:00:00.000Z',
      partyType: 'customer',
      partyId: 'customer-1',
      paymentMethod: 'cash',
      amountMinorUnits: 1500,
      currency: 'ILS',
      description: 'Receipt',
      chequeNumber: null,
      bankName: null,
      dueDate: null,
    },
    postingAccounts: {
      settlementAccountId: '1110', partyAccountId: '1140',
    },
  };
  const key = 'stores/store-a/voucher_drafts/voucher-1';
  return {
    handlers, request, command, documents, key,
    get postCount() {return postCount;},
    set shouldFailPosting(value) {shouldFailPosting = value;},
  };
}

test('saving an unchanged draft is idempotent and never posts ledgers', async () => {
  const t = setup();
  await t.handlers.save(t.request('creator', t.command));
  const again = await t.handlers.save(t.request('creator', t.command));
  assert.equal(again.status, 'draft');
  assert.equal(t.postCount, 0);
  assert.equal(t.documents.get(t.key).status, 'draft');
  await assert.rejects(
    t.handlers.save(t.request('creator', {
      ...t.command,
      payment: {...t.command.payment, amountMinorUnits: 5000},
    })),
    (error) => error.code === 'failed-precondition',
  );
});

test('submission, approval, and replay are atomic and no duplicate posting', async () => {
  const t = setup();
  await t.handlers.save(t.request('creator', t.command));
  const identity = {storeId: 'store-a', draftId: 'voucher-1'};
  await assert.rejects(
    t.handlers.approve(t.request('approver', identity)),
    (error) => error.code === 'failed-precondition',
  );
  await t.handlers.submit(t.request('creator', identity));
  assert.equal(t.postCount, 0);
  await assert.rejects(
    t.handlers.approve(t.request('outsider', identity)),
    (error) => error.code === 'permission-denied',
  );
  const approved = await t.handlers.approve(t.request('approver', identity));
  assert.equal(approved.journalEntryId, 'voucher-1-journal');
  assert.equal(t.postCount, 1);
  assert.equal(t.documents.get(t.key).status, 'posted');
  await t.handlers.approve(t.request('approver', identity));
  assert.equal(t.postCount, 1);
  await assert.rejects(
    t.handlers.reject(t.request('approver', {...identity, reason: 'no'})),
    (error) => error.code === 'failed-precondition',
  );
});

test('failed financial posting does not mark a draft approved', async () => {
  const t = setup();
  const identity = {storeId: 'store-a', draftId: 'voucher-1'};
  await t.handlers.save(t.request('creator', t.command));
  await t.handlers.submit(t.request('creator', identity));
  t.shouldFailPosting = true;
  await assert.rejects(
    t.handlers.approve(t.request('approver', identity)),
    (error) => error.code === 'failed-precondition',
  );
  assert.equal(t.documents.get(t.key).status, 'pendingApproval');
  assert.equal(t.postCount, 0);
});

test('rejection preserves immutable financial data without journal entries', async () => {
  const t = setup();
  const identity = {storeId: 'store-a', draftId: 'voucher-1'};
  await t.handlers.save(t.request('creator', t.command));
  await t.handlers.submit(t.request('creator', identity));
  await t.handlers.reject(t.request('approver', {...identity, reason: 'Incorrect amount'}));
  assert.equal(t.documents.get(t.key).status, 'rejected');
  assert.equal(t.documents.get(t.key).financialRequest.payment.amountMinorUnits, 1500);
  assert.equal(t.postCount, 0);
  await assert.rejects(
    t.handlers.approve(t.request('approver', identity)),
    (error) => error.code === 'failed-precondition',
  );
});

test('editing an unsent draft increments revision without posting', async () => {
  const t = setup();
  const identity = {storeId: 'store-a', draftId: 'voucher-1'};
  await t.handlers.save(t.request('creator', t.command));
  const changed = await t.handlers.update(t.request('creator', {
    ...identity, expectedRevision: 1,
    amountMinorUnits: 2750, description: 'Corrected receipt',
  }));
  assert.equal(changed.revision, 2);
  assert.equal(t.documents.get(t.key).financialRequest.payment.amountMinorUnits, 2750);
  assert.equal(t.postCount, 0);
  await assert.rejects(
    t.handlers.update(t.request('creator', {
      ...identity, expectedRevision: 1,
      amountMinorUnits: 9000,
    })),
    (error) => error.code === 'failed-precondition',
  );
  await assert.rejects(
    t.handlers.update(t.request('approver', {
      ...identity, expectedRevision: 2, amountMinorUnits: 1000,
    })),
    (error) => error.code === 'permission-denied',
  );
  await t.handlers.submit(t.request('creator', identity));
  await assert.rejects(
    t.handlers.update(t.request('creator', {
      ...identity, expectedRevision: 2, amountMinorUnits: 1000,
    })),
    (error) => error.code === 'failed-precondition',
  );
});

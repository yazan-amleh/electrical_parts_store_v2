'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  setDoc,
} = require('firebase/firestore');
const {
  deleteObject,
  getBytes,
  ref: storageRef,
  uploadString,
} = require('firebase/storage');

const PROJECT_ID = 'demo-electrical-parts-v2-rules';
const STORE_ID = 'store-a';
const ROOM_ID = 'room-1';
const ATTACHMENT_PATH =
  'stores/store-a/chatRooms/room-1/attachments/sales-1/message.txt';

let testEnv;
let participantStorage;
let roomOwnerStorage;
let outsiderStorage;

describe('Storage security rules', function () {
  this.timeout(60000);

  before(async () => {
    const firestoreRules = fs.readFileSync(
      path.join(__dirname, '..', 'firestore.rules'),
      'utf8',
    );
    const storageRules = fs.readFileSync(
      path.join(__dirname, '..', 'storage.rules'),
      'utf8',
    );

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules: firestoreRules },
      storage: { rules: storageRules },
    });

    participantStorage = testEnv.authenticatedContext('sales-1').storage();
    roomOwnerStorage = testEnv.authenticatedContext('owner-1').storage();
    outsiderStorage = testEnv.authenticatedContext('outsider-1').storage();
  });

  beforeEach(async () => {
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(
        context.firestore(),
        'stores',
        STORE_ID,
        'chatRooms',
        ROOM_ID,
      ), {
        storeId: STORE_ID,
        participantIds: ['sales-1', 'owner-1'],
      });
    });
  });

  after(async () => {
    await testEnv.cleanup();
  });

  it('allows room participants to upload/read their chat attachments only', async () => {
    const participantRef = storageRef(participantStorage, ATTACHMENT_PATH);

    await assertSucceeds(uploadString(participantRef, 'hello'));
    await assertSucceeds(getBytes(
      storageRef(roomOwnerStorage, ATTACHMENT_PATH),
    ));
    await assertFails(getBytes(
      storageRef(outsiderStorage, ATTACHMENT_PATH),
    ));
    await assertFails(uploadString(
      storageRef(
        outsiderStorage,
        'stores/store-a/chatRooms/room-1/attachments/outsider-1/no.txt',
      ),
      'blocked',
    ));
    await assertFails(uploadString(
      storageRef(
        participantStorage,
        'stores/store-a/chatRooms/room-1/attachments/owner-1/spoof.txt',
      ),
      'blocked',
    ));
  });

  it('allows only the attachment owner to delete it', async () => {
    const participantRef = storageRef(participantStorage, ATTACHMENT_PATH);
    await assertSucceeds(uploadString(participantRef, 'hello'));
    await assertFails(
      deleteObject(storageRef(roomOwnerStorage, ATTACHMENT_PATH)),
    );
    await assertSucceeds(deleteObject(participantRef));
  });
});

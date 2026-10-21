const projectId = process.env.FIREBASE_PROJECT_ID || 'electrical-store-v2-prod';
const webApiKey = process.env.FIREBASE_WEB_API_KEY;
const email = process.env.SMOKE_TEST_EMAIL;
const password = process.env.SMOKE_TEST_PASSWORD;
const storeId = process.env.SMOKE_TEST_STORE_ID || 'v2-dev-store';
const region = process.env.FUNCTIONS_REGION || 'europe-west1';

if (!webApiKey || !email || !password) {
  throw new Error(
    'FIREBASE_WEB_API_KEY, SMOKE_TEST_EMAIL and SMOKE_TEST_PASSWORD are required.',
  );
}

async function readJson(response) {
  const body = await response.text();
  let parsed;
  try {
    parsed = body ? JSON.parse(body) : {};
  } catch {
    parsed = {raw: body};
  }
  if (!response.ok) {
    const detail = parsed?.error?.message || parsed?.error || parsed?.raw;
    throw new Error(`${response.status} ${response.statusText}: ${detail}`);
  }
  return parsed;
}

async function getFirestoreDocument(path, idToken) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`,
    {
      headers: {
        Authorization: `Bearer ${idToken}`,
      },
    },
  );
  return readJson(response);
}

async function main() {
  const authResponse = await readJson(
    await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${webApiKey}`,
      {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({
          email,
          password,
          returnSecureToken: true,
        }),
      },
    ),
  );

  const idToken = authResponse.idToken;
  if (!idToken) {
    throw new Error('Firebase Auth did not return an ID token.');
  }

  const store = await getFirestoreDocument(`stores/${storeId}`, idToken);
  const member = await getFirestoreDocument(
    `stores/${storeId}/members/${authResponse.localId}`,
    idToken,
  );
  if (!store.name || member.fields?.isActive?.booleanValue !== true) {
    throw new Error('Store or active membership smoke check failed.');
  }

  const functionResponse = await readJson(
    await fetch(
      `https://${region}-${projectId}.cloudfunctions.net/auditAccountingIntegrity`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${idToken}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({data: {storeId}}),
      },
    ),
  );
  const audit = functionResponse.data || functionResponse.result;
  if (!audit || audit.status !== 'healthy' || audit.issueCount !== 0) {
    throw new Error(
      `Accounting smoke check failed: ${JSON.stringify(audit)}`,
    );
  }

  console.log(JSON.stringify({
    status: 'passed',
    projectId,
    storeId,
    userId: authResponse.localId,
    function: 'auditAccountingIntegrity',
    auditStatus: audit.status,
    issueCount: audit.issueCount,
  }));
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});

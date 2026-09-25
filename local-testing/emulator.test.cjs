const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { assertLocalEnvironment, PROJECT } = require('./support.cjs');
assertLocalEnvironment(process.env);
const fromFunctions = createRequire(require.resolve('../functions/package.json'));
const { Firestore } = fromFunctions('firebase-admin/firestore');
const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const firestore = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
const callable = `http://127.0.0.1:5001/${PROJECT}/us-central1/fetchNearbyRestaurants`;

async function request(url, method = 'GET', body, token) {
  assert.ok(['http://127.0.0.1:8080', 'http://127.0.0.1:9099', 'http://127.0.0.1:5001'].includes(new URL(url).origin));
  const response = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30000),
  });
  const text = await response.text();
  return { status: response.status, data: text ? JSON.parse(text) : {} };
}
async function anonymousUser() {
  const response = await request('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-api-key', 'POST', { returnSecureToken: true });
  assert.equal(response.status, 200);
  return { uid: response.data.localId, token: response.data.idToken };
}
function month() {
  return new Date().toISOString().slice(0, 7);
}
beforeEach(async () => {
  const result = await request(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, 'DELETE');
  assert.equal(result.status, 200);
});
after(async () => {
  await db.terminate();
});

test('Auth emulator creates an anonymous identity; callable returns only fixtures without App Check', async () => {
  const user = await anonymousUser();
  assert.ok(user.uid);
  const response = await request(callable, 'POST', { data: { baseLat: 40, baseLon: -75 } }, user.token);
  assert.equal(response.status, 200);
  assert.equal(response.data.result.restaurants.length, 5);
  assert.ok(response.data.result.restaurants.every(r => r.id.startsWith('fixture-')));
  const usage = await db.collection('hereUsage').doc(response.data.result.usageMonth).get();
  assert.equal(usage.data().count, 4);
});

test('invalid callable input does not create a usage reservation', async () => {
  const response = await request(callable, 'POST', { data: {} });
  assert.equal(response.status, 400);
  assert.equal((await db.collection('hereUsage').get()).size, 0);
});

test('concurrent searches cannot both spend the final four calls', async () => {
  await db.collection('hereUsage').doc(month()).set({ count: 29496 });
  const responses = await Promise.all([1, 2].map(() => request(callable, 'POST', { data: { baseLat: 40, baseLon: -75 } })));
  assert.deepEqual(responses.map(r => r.status).sort(), [200, 429]);
  assert.equal((await db.collection('hereUsage').doc(month()).get()).data().count, 29500);
});

test('baseline rules: unauthenticated users can create, read, change and delete rooms', async () => {
  const url = `${firestore}/rooms/LOCAL1`;
  assert.equal((await request(url, 'PATCH', { fields: { creator: { stringValue: 'host' } } })).status, 200);
  assert.equal((await request(url)).status, 200);
  assert.equal((await request(url, 'PATCH', { fields: { creator: { stringValue: 'outsider' } } })).status, 200);
  assert.equal((await request(url, 'DELETE')).status, 200);
});

test('baseline rules: a different user can overwrite a ballot and repeated writes are allowed', async () => {
  const host = await anonymousUser();
  const outsider = await anonymousUser();
  const url = `${firestore}/rooms/LOCAL1/votes/${host.uid}/ballot/fixture-pizza`;
  assert.equal((await request(url, 'PATCH', { fields: { liked: { booleanValue: true } } }, host.token)).status, 200);
  assert.equal((await request(url, 'PATCH', { fields: { liked: { booleanValue: false } } }, outsider.token)).status, 200);
  const read = await request(url);
  assert.equal(read.status, 200);
  assert.equal(read.data.fields.liked.booleanValue, false);
});

test('baseline rules: client usage-counter access and unmatched paths are denied', async () => {
  const user = await anonymousUser();
  for (const token of [undefined, user.token]) {
    for (const path of [`hereUsage/${month()}`, 'private/example', 'rooms/LOCAL1/votes/example']) {
      assert.equal((await request(`${firestore}/${path}`, 'PATCH', { fields: {} }, token)).status, 403);
      assert.equal((await request(`${firestore}/${path}`, 'GET', undefined, token)).status, 403);
    }
  }
});

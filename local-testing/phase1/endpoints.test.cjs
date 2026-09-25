const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
const { Firestore, Timestamp } = createRequire(require.resolve('../../functions/package.json'))('firebase-admin/firestore');
const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const documents = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
async function request(url, body, token, method = 'POST') {
  assert.ok(['http://127.0.0.1:9099', 'http://127.0.0.1:8080', 'http://127.0.0.1:5001'].includes(new URL(url).origin));
  const response = await fetch(url, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30000) });
  return { status: response.status, data: await response.json() };
}
const auth = (action, body) => request(`http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:${action}?key=demo-api-key`, body);
const call = (name, data, user) => request(`http://127.0.0.1:5001/${PROJECT}/us-central1/${name}`, { data }, user?.token);
async function user(registered = false, verified = false) {
  const email = `${randomUUID()}@example.test`;
  const password = 'fictional-test-password';
  let result = await auth('signUp', { ...(registered ? { email, password } : {}), returnSecureToken: true });
  assert.equal(result.status, 200);
  if (verified) {
    await auth('sendOobCode', { requestType: 'VERIFY_EMAIL', idToken: result.data.idToken });
    const codes = await request(`http://127.0.0.1:9099/emulator/v1/projects/${PROJECT}/oobCodes`, undefined, undefined, 'GET');
    const code = codes.data.oobCodes.find(c => c.email === email && c.requestType === 'VERIFY_EMAIL').oobCode;
    assert.equal((await auth('update', { oobCode: code })).status, 200);
    result = await auth('signInWithPassword', { email, password, returnSecureToken: true });
  }
  return { uid: result.data.localId, token: result.data.idToken };
}
async function room(host) {
  const result = await call('phase1CreateRoom', { requestId: randomUUID() }, host);
  assert.equal(result.status, 200);
  return result.data.result.roomCode;
}
beforeEach(async () => {
  const response = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(response.status, 200);
});
after(() => db.terminate());
test('endpoints: verified host creates; guest joins, reads and votes; fixture search is host-only', async () => {
  const host = await user(true, true); const guest = await user(); const outsider = await user();
  const code = await room(host);
  assert.equal((await request(`${documents}/rooms/${code}`, undefined, guest.token, 'GET')).status, 403);
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, guest)).status, 200);
  assert.equal((await request(`${documents}/rooms/${code}`, undefined, guest.token, 'GET')).status, 200);
  assert.equal((await call('phase1Search', { roomCode: code }, guest)).status, 403);
  const generated = await call('phase1Search', { roomCode: code }, host);
  assert.equal(generated.status, 200); assert.equal(generated.data.result.candidateCount, 5);
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, guest)).status, 200);
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, outsider)).status, 403);
  const ballot = { writes: [{ update: { name: `projects/${PROJECT}/databases/(default)/documents/rooms/${code}/votes/${guest.uid}/ballot/fixture-pizza`, fields: { liked: { booleanValue: true } } }, updateTransforms: [{ fieldPath: 'at', setToServerValue: 'REQUEST_TIME' }] }] };
  assert.equal((await request(`${documents}:commit`, ballot, guest.token)).status, 200);
  assert.equal((await request(`${documents}:commit`, ballot, outsider.token)).status, 403);
  const email = `${randomUUID()}@example.test`;
  assert.equal((await auth('update', { idToken: guest.token, email, password: 'fictional-link-password', returnSecureToken: true })).status, 200);
  const linked = await auth('signInWithPassword', { email, password: 'fictional-link-password', returnSecureToken: true });
  assert.equal(linked.status, 200);
  assert.equal(linked.data.localId, guest.uid);
  assert.equal((await request(`${documents}/rooms/${code}/votes/${guest.uid}/ballot/fixture-pizza`, undefined, linked.data.idToken, 'GET')).status, 200);
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, { token: linked.data.idToken })).status, 200);
  assert.equal((await db.collection('hereUsage').get()).size, 0);
});
test('endpoints: anonymous, unverified and missing identities cannot create; supplied claims are rejected', async () => {
  assert.equal((await call('phase1CreateRoom', { requestId: randomUUID() })).status, 401);
  for (const actor of [await user(), await user(true)]) assert.equal((await call('phase1CreateRoom', { requestId: randomUUID() }, actor)).status, 403);
  const host = await user(true, true);
  assert.equal((await call('phase1CreateRoom', { requestId: randomUUID(), uid: 'victim', emailVerified: true }, host)).status, 400);
  const code = await room(host);
  const otherHost = await user(true, true);
  assert.equal((await call('phase1Search', { roomCode: code }, otherHost)).status, 403);
});
test('endpoints: concurrent retries preserve one room, one membership and one fixture deck', async () => {
  const host = await user(true, true); const requestId = randomUUID();
  const rooms = await Promise.all([1, 2].map(() => call('phase1CreateRoom', { requestId }, host)));
  assert.deepEqual(rooms.map(r => r.status), [200, 200]);
  const code = rooms[0].data.result.roomCode;
  assert.equal(rooms[1].data.result.roomCode, code);
  assert.equal((await db.collection('rooms').get()).size, 1);
  const guest = await user();
  const joins = await Promise.all([1, 2].map(() => call('phase1JoinRoom', { roomCode: code }, guest)));
  assert.deepEqual(joins.map(r => r.status), [200, 200]);
  assert.equal((await db.doc(`rooms/${code}`).get()).data().memberCount, 2);
  const searches = await Promise.all([1, 2].map(() => call('phase1Search', { roomCode: code }, host)));
  assert.deepEqual(searches.map(r => r.status), [200, 200]);
  assert.equal((await db.collection(`rooms/${code}/candidates`).get()).size, 5);
});
test('endpoints: join attempts are bounded; revoked and expired memberships cannot reconnect', async () => {
  const host = await user(true, true); const guest = await user(); const code = await room(host);
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, guest)).status, 200);
  await db.doc(`rooms/${code}/members/${guest.uid}`).update({ active: false });
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, guest)).status, 403);
  await db.doc(`rooms/${code}`).update({ expiresAt: Timestamp.fromMillis(0) });
  assert.equal((await call('phase1JoinRoom', { roomCode: code }, host)).status, 403);
  assert.equal((await call('phase1Search', { roomCode: code }, host)).status, 403);
  const attacker = await user();
  for (let i = 0; i < 10; i++) assert.equal((await call('phase1JoinRoom', { roomCode: 'A'.repeat(24) }, attacker)).status, 403);
  assert.equal((await call('phase1JoinRoom', { roomCode: 'A'.repeat(24) }, attacker)).status, 429);
});
test('endpoints: concurrent new members cannot exceed the room capacity', async () => {
  const host = await user(true, true); const code = await room(host);
  await db.doc(`rooms/${code}`).update({ memberCount: 39 });
  const guests = await Promise.all([user(), user()]);
  const results = await Promise.all(guests.map(guest => call('phase1JoinRoom', { roomCode: code }, guest)));
  assert.deepEqual(results.map(r => r.status).sort(), [200, 403]);
  assert.equal((await db.doc(`rooms/${code}`).get()).data().memberCount, 40);
});
test('preview status identifies the local candidate worker', async () => {
  const response = await call('phase1Status', {});
  assert.equal(response.status, 200);
  assert.deepEqual(response.data.result, { project: PROJECT, policy: 'phase1' });
});

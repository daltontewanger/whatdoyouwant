const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { createRequire } = require('node:module');
const { assertLocalEnvironment, PROJECT } = require('../support.cjs');
const { authorize } = require('./authorization.cjs');
assertLocalEnvironment(process.env);
const fromFunctions = createRequire(require.resolve('../../functions/package.json'));
const { Firestore, Timestamp, FieldValue } = fromFunctions('firebase-admin/firestore');
const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const base = `http://127.0.0.1:8080/v1/projects/${PROJECT}/databases/(default)/documents`;
// Unsigned claims are accepted ONLY by the emulator. They are not real logins.
function token(uid) {
  const encode = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ sub: uid, user_id: uid,
    aud: PROJECT, iss: `https://securetoken.google.com/${PROJECT}`, iat: Math.floor(Date.now()/1000),
    exp: Math.floor(Date.now()/1000)+3600, firebase: { sign_in_provider: 'anonymous' } })}.`;
}
async function request(path, method = 'GET', body, uid) {
  const response = await fetch(`${base}${path}`, { method,
    headers: { 'Content-Type': 'application/json', ...(uid ? { Authorization: `Bearer ${token(uid)}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(15000) });
  return response.status;
}
// Ballots must carry the room's expiry so TTL can remove them with the room.
let roomExpiry;
const expiryField = () => ({ expiresAt: { timestampValue: roomExpiry.toDate().toISOString() } });
async function ballot(uid, fields = { liked: { booleanValue: true }, ...expiryField() }, restaurant = 'pizza') {
  return request(':commit', 'POST', { writes: [{ update: {
    name: `projects/${PROJECT}/databases/(default)/documents/rooms/ROOM/votes/${uid}/ballot/${restaurant}`, fields },
    updateTransforms: [{ fieldPath: 'at', setToServerValue: 'REQUEST_TIME' }] }] }, uid);
}
beforeEach(async () => {
  const clear = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(clear.status, 200);
  roomExpiry = Timestamp.fromMillis(Date.now()+3600000);
  await db.doc('rooms/ROOM').set({ creator: 'host', status: 'voting', expiresAt: roomExpiry, deckId: 'DECK',
    votingEndsAt: Timestamp.fromMillis(Date.now()+600000) });
  for (const uid of ['host', 'guest', 'other']) await db.doc(`rooms/ROOM/members/${uid}`).set({ active: true });
  await db.doc('restaurantDecks/DECK').set({ ownerUid: 'host', targetType: 'room', targetId: 'ROOM',
    candidateIds: ['pizza'], candidates: [{ id: 'pizza', name: 'Fictional Pizza' }], expiresAt: roomExpiry });
});
after(() => db.terminate());

test('contract: only verified registered identities create and initiate host searches', () => {
  const room = { creator: 'host', status: 'lobby', expiresAt: Date.now()+10000 };
  for (const provider of ['password', 'google.com', 'apple.com']) {
    const host = { uid: 'host', provider, emailVerified: true };
    assert.equal(authorize('create', host), true);
    assert.equal(authorize('start', host, room, true), true);
    assert.equal(authorize('start', { ...host, uid: 'outsider' }, room, true), false);
    assert.equal(authorize('start', host, room, false), false);
    assert.equal(authorize('create', { ...host, emailVerified: false }), false);
  }
  for (const identity of [null, { uid: 'guest', provider: 'anonymous', emailVerified: true }, { uid: 'x', provider: 'custom', emailVerified: true }]) {
    assert.equal(authorize('create', identity), false);
    assert.equal(authorize('start', identity, room, true), false);
  }
});
test('contract: anonymous guests can join a live lobby; closed/expired rooms and missing identity fail', () => {
  const guest = { uid: 'guest', provider: 'anonymous' };
  const room = { status: 'lobby', expiresAt: Date.now()+10000 };
  assert.equal(authorize('join', guest, room), true);
  assert.equal(authorize('join', null, room), false);
  for (const status of ['voting', 'closed']) assert.equal(authorize('join', guest, { ...room, status }), false);
  assert.equal(authorize('join', guest, { ...room, expiresAt: 0 }), false);
  assert.equal(authorize('join', guest, { status: 'lobby' }), false);
  assert.equal(authorize('join', guest, { ...room, expiresAt: 'tomorrow' }), false);
});
test('members read their room and deck; outsiders and unauthenticated callers cannot', async () => {
  for (const uid of ['host', 'guest']) assert.equal(await request('/rooms/ROOM', 'GET', undefined, uid), 200);
  for (const uid of [undefined, 'outsider']) {
    assert.equal(await request('/rooms/ROOM', 'GET', undefined, uid), 403);
    assert.equal(await request('/restaurantDecks/DECK', 'GET', undefined, uid), 403);
  }
  assert.equal(await request('/restaurantDecks/DECK', 'GET', undefined, 'guest'), 200);
  assert.equal(await request('/restaurantDecks', 'GET', undefined, 'guest'), 403, 'decks cannot be listed');
  assert.equal(await request('/rooms', 'GET', undefined, 'guest'), 403);
  assert.equal(await request('/rooms', 'GET'), 403);
});
test('clients cannot create rooms, transfer ownership, close rooms, forge membership or modify ledgers', async () => {
  for (const uid of [undefined, 'host', 'guest', 'outsider']) {
    for (const path of ['/rooms/NEW', '/rooms/ROOM', '/rooms/ROOM/members/outsider', '/hereUsage/month', '/users/host', '/restaurantDecks/DECK', '/restaurantDecks/NEW']) {
      assert.equal(await request(path, 'PATCH', { fields: { creator: { stringValue: 'outsider' } } }, uid), 403);
      assert.equal(await request(path, 'DELETE', undefined, uid), 403);
    }
  }
});
test('quota, provider-usage and generation records are server-only, even for the person they count', async () => {
  const records = ['/config/liveSearch', '/usageWeeks/host_2026-10-05', '/usageMonths/here_2026-10',
    '/deckGenerations/room_ROOM', '/entitlements/host'];
  for (const path of records) await db.doc(path.slice(1)).set({ enabled: true, used: 0 });
  for (const uid of [undefined, 'host', 'guest']) {
    for (const path of records) {
      assert.equal(await request(path, 'GET', undefined, uid), 403, `${path} is not readable`);
      assert.equal(await request(path, 'PATCH', { fields: { used: { integerValue: '99' } } }, uid), 403);
      assert.equal(await request(path, 'DELETE', undefined, uid), 403);
    }
  }
});
test('a Quick Pick and its deck are readable only by their owner while they last', async () => {
  const later = Timestamp.fromMillis(Date.now() + 3600000);
  await db.doc('quickPicks/PICK').set({ ownerUid: 'host', deckId: 'QDECK', order: ['pizza'], position: 0,
    rerollsUsed: 0, expiresAt: later });
  await db.doc('restaurantDecks/QDECK').set({ ownerUid: 'host', targetType: 'quickPick', targetId: 'PICK',
    candidateIds: ['pizza'], candidates: [], expiresAt: later });
  for (const path of ['/quickPicks/PICK', '/restaurantDecks/QDECK']) {
    assert.equal(await request(path, 'GET', undefined, 'host'), 200);
    for (const uid of [undefined, 'guest']) assert.equal(await request(path, 'GET', undefined, uid), 403);
    assert.equal(await request(path, 'PATCH', { fields: { position: { integerValue: '3' } } }, 'host'), 403);
  }
  await db.doc('quickPicks/PICK').update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  await db.doc('restaurantDecks/QDECK').update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  for (const path of ['/quickPicks/PICK', '/restaurantDecks/QDECK']) {
    assert.equal(await request(path, 'GET', undefined, 'host'), 403, `${path} is gone once expired`);
  }
});
test('anonymous member can submit and read an own ballot, but cannot rewrite or delete it', async () => {
  assert.equal(await ballot('guest'), 200);
  assert.equal(await request('/rooms/ROOM/votes/guest/ballot/pizza', 'GET', undefined, 'guest'), 200);
  assert.equal(await ballot('guest'), 403);
  assert.equal(await request('/rooms/ROOM/votes/guest/ballot/pizza', 'DELETE', undefined, 'guest'), 403);
  for (const uid of ['host', 'other', 'outsider']) {
    assert.equal(await request('/rooms/ROOM/votes/guest/ballot/pizza', 'GET', undefined, uid), 403);
    assert.equal(await request('/rooms/ROOM/votes/guest/ballot/pizza', 'PATCH', { fields: { liked: { booleanValue: false } } }, uid), 403);
  }
  for (const fields of [{}, { liked: { stringValue: 'x'.repeat(100000) } }, { at: { stringValue: 'invalid' } }]) {
    assert.equal(await request('/rooms/ROOM/votes/guest/ballot/pizza', 'PATCH', { fields }, 'guest'), 403);
  }
});
test('ballots reject outsiders, unknown candidates, extra fields, missing fields, wrong types and a different expiry', async () => {
  assert.equal(await ballot('outsider'), 403);
  assert.equal(await ballot('guest', { liked: { booleanValue: true }, ...expiryField() }, 'unknown'), 403);
  const later = { expiresAt: { timestampValue: new Date(roomExpiry.toMillis() + 86400000).toISOString() } };
  for (const fields of [{}, { liked: { stringValue: 'true' }, ...expiryField() },
    { liked: { booleanValue: true }, admin: { booleanValue: true }, ...expiryField() },
    { liked: { booleanValue: true } }, { liked: { booleanValue: true }, ...later }]) {
    assert.equal(await ballot('guest', fields), 403);
  }
});
test('ballots are refused once the voting window has passed, before anyone closes the room', async () => {
  await db.doc('rooms/ROOM').update({ votingEndsAt: Timestamp.fromMillis(Date.now()-1000) });
  assert.equal(await ballot('guest'), 403);
  await db.doc('rooms/ROOM').update({ votingEndsAt: FieldValue.delete() });
  assert.equal(await ballot('guest'), 403);
  await db.doc('rooms/ROOM').update({ votingEndsAt: Timestamp.fromMillis(Date.now()+60000) });
  assert.equal(await ballot('guest'), 200);
});
test('decks are readable only while the room lives, and only by its active members', async () => {
  await db.doc('restaurantDecks/OTHER').set({ ownerUid: 'host', targetType: 'room', targetId: 'ELSEWHERE',
    candidateIds: ['pizza'], candidates: [], expiresAt: roomExpiry });
  assert.equal(await request('/restaurantDecks/OTHER', 'GET', undefined, 'guest'), 403, 'a deck for another room');
  await db.doc('restaurantDecks/QUICK').set({ ownerUid: 'guest', targetType: 'quickPick', targetId: 'ROOM',
    candidateIds: [], candidates: [], expiresAt: roomExpiry });
  assert.equal(await request('/restaurantDecks/QUICK', 'GET', undefined, 'guest'), 200, 'its owner reads a Quick Pick deck');
  assert.equal(await request('/restaurantDecks/QUICK', 'GET', undefined, 'host'), 403,
    'a Quick Pick deck is not shared with a room that happens to match its target ID');
  await db.doc('rooms/ROOM/members/guest').update({ active: false });
  assert.equal(await request('/restaurantDecks/DECK', 'GET', undefined, 'guest'), 403);
  await db.doc('rooms/ROOM').update({ expiresAt: Timestamp.fromMillis(0) });
  assert.equal(await request('/restaurantDecks/DECK', 'GET', undefined, 'host'), 403);
});
test('closed, lobby, expired and revoked membership prevent voting', async () => {
  for (const status of ['closed', 'lobby']) {
    await db.doc('rooms/ROOM').update({ status });
    assert.equal(await ballot('guest'), 403);
  }
  await db.doc('rooms/ROOM').update({ status: 'voting', expiresAt: Timestamp.fromMillis(0) });
  assert.equal(await ballot('guest'), 403);
  assert.equal(await request('/rooms/ROOM', 'GET', undefined, 'guest'), 403);
  await db.doc('rooms/ROOM').update({ expiresAt: Timestamp.fromMillis(Date.now()+10000) });
  await db.doc('rooms/ROOM/members/guest').update({ active: false });
  assert.equal(await ballot('guest'), 403);
  assert.equal(await request('/rooms/ROOM', 'GET', undefined, 'guest'), 403);
});

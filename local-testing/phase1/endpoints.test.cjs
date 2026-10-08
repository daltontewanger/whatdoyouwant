const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
const fromFunctions = createRequire(require.resolve('../../functions/package.json'));
const { Firestore, Timestamp, FieldValue } = fromFunctions('firebase-admin/firestore');
const { HttpsError } = fromFunctions('firebase-functions/v2/https');
const { createRoomHandlers } = require('../../rooms/handlers.js');
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
  return { uid: result.data.localId, token: result.data.idToken, refreshToken: result.data.refreshToken };
}
// Stands in for an app restart: the persisted refresh token is exchanged for a new ID token.
async function resume(session) {
  const result = await request(`http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=demo-api-key`,
    { grant_type: 'refresh_token', refresh_token: session.refreshToken });
  assert.equal(result.status, 200);
  return { uid: result.data.user_id, token: result.data.id_token };
}
// The Functions emulator accepts unsigned tokens, which lets a test present an old sign-in time.
function staleToken(uid, provider = 'password') {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const issued = Math.floor(Date.now() / 1000);
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ sub: uid, user_id: uid, aud: PROJECT,
    iss: `https://securetoken.google.com/${PROJECT}`, iat: issued, exp: issued + 3600, auth_time: issued - 3600,
    email_verified: true, firebase: { sign_in_provider: provider } })}.`;
}
async function room(host) {
  const result = await call('createRoom', { requestId: randomUUID() }, host);
  assert.equal(result.status, 200);
  return result.data.result;
}
const join = (joinCode, member) => call('joinRoom', { joinCode }, member);
const reconnect = (roomId, member) => call('joinRoom', { roomId }, member);
const expiryOf = async roomId => (await db.doc(`rooms/${roomId}`).get()).data().expiresAt;
const ballotPath = (roomId, uid, candidate) => `projects/${PROJECT}/databases/(default)/documents/rooms/${roomId}/votes/${uid}/ballot/${candidate}`;
async function vote(roomId, voter, candidate, liked = true) {
  const expiresAt = (await expiryOf(roomId)).toDate().toISOString();
  return request(`${documents}:commit`, { writes: [{ update: { name: ballotPath(roomId, voter.uid, candidate),
    fields: { liked: { booleanValue: liked }, expiresAt: { timestampValue: expiresAt } } },
    updateTransforms: [{ fieldPath: 'at', setToServerValue: 'REQUEST_TIME' }] }] }, voter.token);
}
const readRoom = (roomId, reader) => request(`${documents}/rooms/${roomId}`, undefined, reader.token, 'GET');
const readBallot = (roomId, uid, candidate, reader) =>
  request(`${documents}/rooms/${roomId}/votes/${uid}/ballot/${candidate}`, undefined, reader.token, 'GET');
const listBallots = (roomId, uid, reader) =>
  request(`${documents}/rooms/${roomId}/votes/${uid}/ballot`, undefined, reader.token, 'GET');
// A fictional spot; the fake provider places its demo restaurants around it.
const SEARCH = Object.freeze({ origin: { lat: 38.5, lng: -98.5 }, radius: { value: 5, unit: 'mi' }, deckSize: 5 });
const start = (roomId, host, search = SEARCH) => call('startRoom', { roomId, search }, host);
const deckOf = async roomId => {
  const { deckId } = (await db.doc(`rooms/${roomId}`).get()).data();
  return (await db.doc(`restaurantDecks/${deckId}`).get()).data();
};
beforeEach(async () => {
  const response = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(response.status, 200);
});
after(() => db.terminate());

test('rooms: verified host creates with a short code; guest joins, reads and votes; start is host-only', async () => {
  const host = await user(true, true); const guest = await user(); const outsider = await user();
  const { roomId, joinCode } = await room(host);
  assert.match(roomId, /^[A-F0-9]{24}$/);
  assert.match(joinCode, /^[A-HJKMNP-Z2-9]{6}$/);
  const expiresIn = (await expiryOf(roomId)).toMillis() - Date.now();
  assert.ok(expiresIn > 23.9 * 3600000 && expiresIn <= 24 * 3600000, 'rooms live for 24 hours');
  assert.equal((await readRoom(roomId, guest)).status, 403);
  // Codes are typed by people, so case, spaces and hyphens are forgiven.
  const typed = `${joinCode.slice(0, 3).toLowerCase()}-${joinCode.slice(3)}`;
  assert.equal((await join(typed, guest)).data.result.roomId, roomId);
  assert.equal((await readRoom(roomId, guest)).status, 200);
  assert.equal((await start(roomId, guest)).status, 403);
  const started = await start(roomId, host);
  assert.equal(started.status, 200); assert.equal(started.data.result.candidateCount, 5);
  const D = (await deckOf(roomId)).candidateIds;
  const deckLife = (await deckOf(roomId)).expiresAt.toMillis() - Date.now();
  assert.ok(deckLife > 59 * 60000 && deckLife <= 60 * 60000, 'a deck lives 30 minutes past the voting window');
  assert.equal(started.data.result.deckId, (await db.doc(`rooms/${roomId}`).get()).data().deckId);
  // The code stops working once voting starts; members reconnect with the room ID.
  assert.equal((await db.doc(`roomCodes/${joinCode}`).get()).exists, false);
  assert.equal((await join(joinCode, outsider)).status, 403);
  assert.equal((await reconnect(roomId, guest)).status, 200);
  assert.equal((await vote(roomId, guest, D[0])).status, 200);
  assert.equal((await vote(roomId, outsider, D[0])).status, 403);
  assert.equal((await db.collection('hereUsage').get()).size, 0);
});

test('rooms: the internal room ID reconnects members but never admits new ones', async () => {
  const host = await user(true, true); const stranger = await user();
  const { roomId } = await room(host);
  assert.equal((await reconnect(roomId, stranger)).status, 403);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 1);
});

test('rooms: other members, the host and a switched-in account cannot read private ballots', async () => {
  const host = await user(true, true); const first = await user(); const second = await user();
  const { roomId, joinCode } = await room(host);
  for (const guest of [first, second]) assert.equal((await join(joinCode, guest)).status, 200);
  assert.equal((await start(roomId, host)).status, 200);
  const D = (await deckOf(roomId)).candidateIds;
  assert.equal((await vote(roomId, first, D[0])).status, 200);
  assert.equal((await readBallot(roomId, first.uid, D[0], first)).status, 200);
  for (const reader of [second, host]) {
    assert.equal((await readBallot(roomId, first.uid, D[0], reader)).status, 403);
    assert.equal((await listBallots(roomId, first.uid, reader)).status, 403);
    assert.equal((await vote(roomId, { uid: first.uid, token: reader.token }, D[1])).status, 403);
  }
  const switched = await user();
  assert.equal((await readRoom(roomId, switched)).status, 403);
  assert.equal((await readBallot(roomId, first.uid, D[0], switched)).status, 403);
  assert.equal((await reconnect(roomId, switched)).status, 403);
});

test('rooms: a restarted or linked session keeps membership, its ballots and the ability to vote', async () => {
  const host = await user(true, true); const guest = await user();
  const { roomId, joinCode } = await room(host);
  assert.equal((await join(joinCode, guest)).status, 200);
  assert.equal((await start(roomId, host)).status, 200);
  const D = (await deckOf(roomId)).candidateIds;
  assert.equal((await vote(roomId, guest, D[0])).status, 200);
  const restarted = await resume(guest);
  assert.equal(restarted.uid, guest.uid);
  assert.equal((await reconnect(roomId, restarted)).status, 200);
  assert.equal((await readBallot(roomId, guest.uid, D[0], restarted)).status, 200);
  assert.equal((await vote(roomId, restarted, D[0], false)).status, 403);
  assert.equal((await vote(roomId, restarted, D[1], false)).status, 200);
  assert.equal((await start(roomId, await resume(host))).status, 200);
  const email = `${randomUUID()}@example.test`;
  const link = await auth('update', { idToken: restarted.token, email, password: 'fictional-link-password', returnSecureToken: true });
  assert.equal(link.status, 200);
  const linked = await resume({ refreshToken: link.data.refreshToken });
  assert.equal(linked.uid, guest.uid);
  assert.equal((await vote(roomId, linked, D[2])).status, 200);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 2);
  assert.equal((await call('createRoom', { requestId: randomUUID() }, linked)).status, 403);
});

test('rooms: anonymous, unverified and missing identities cannot create; supplied claims are rejected', async () => {
  assert.equal((await call('createRoom', { requestId: randomUUID() })).status, 401);
  for (const actor of [await user(), await user(true)]) {
    assert.equal((await call('createRoom', { requestId: randomUUID() }, actor)).status, 403);
  }
  const host = await user(true, true);
  assert.equal((await call('createRoom', { requestId: randomUUID(), uid: 'victim', emailVerified: true }, host)).status, 400);
  const { roomId } = await room(host);
  assert.equal((await start(roomId, await user(true, true))).status, 403);
});

test('decks: start accepts only the search contract; thin pools store nothing; decks keep no origin', async () => {
  const host = await user(true, true); const guest = await user(); const outsider = await user();
  const { roomId, joinCode } = await room(host);
  assert.equal((await join(joinCode, guest)).status, 200);
  for (const data of [{ roomId }, { roomId, search: { ...SEARCH, radiusMeters: 99999 } },
    { roomId, search: { ...SEARCH, radius: { value: 4, unit: 'mi' } } }, { roomId, search: { ...SEARCH, deckSize: 20 } },
    { roomId, search: { ...SEARCH, origin: { lat: 200, lng: 0 } } }, { roomId, search: SEARCH, uid: guest.uid },
    { roomId, search: { ...SEARCH, includedCuisineIds: ['101-000'] } }]) {
    assert.equal((await call('startRoom', data, host)).status, 400, JSON.stringify(data));
  }
  const thin = await start(roomId, host, { ...SEARCH, origin: { lat: 0, lng: 0 } });
  assert.equal(thin.status, 400);
  assert.equal(thin.data.error.status, 'FAILED_PRECONDITION');
  assert.deepEqual(thin.data.error.details, { reason: 'too-few-results', eligible: 0, minimum: 5 });
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().status, 'lobby', 'the host can try again');
  assert.equal((await db.collection('restaurantDecks').get()).size, 0);

  assert.equal((await start(roomId, host, { ...SEARCH, excludedCuisineIds: ['pizza'] })).status, 200);
  const deck = await deckOf(roomId);
  assert.equal(deck.ownerUid, host.uid);
  assert.deepEqual([deck.targetType, deck.targetId, deck.provider, deck.source], ['room', roomId, 'fake', 'provider']);
  assert.deepEqual(deck.filterSummary, { radius: { value: 5, unit: 'mi' }, radiusMeters: 8047, includedCuisineIds: [],
    excludedCuisineIds: ['pizza'], openNowPreferred: false, deckSize: 5 });
  assert.ok(!JSON.stringify(deck).includes('"origin"'), 'the search origin is never stored');
  assert.deepEqual(deck.candidateIds, deck.candidates.map(candidate => candidate.id));
  assert.ok(deck.candidates.every(c => Number.isInteger(c.distanceMeters) && c.distanceMeters <= 8047 &&
    !c.cuisineIds.includes('pizza') && c.chainId === undefined));
  assert.ok(deck.expiresAt.toMillis() < (await expiryOf(roomId)).toMillis(), 'decks go well before their room');
  const deckPath = `${documents}/restaurantDecks/${(await db.doc(`rooms/${roomId}`).get()).data().deckId}`;
  assert.equal((await request(deckPath, undefined, guest.token, 'GET')).status, 200);
  assert.equal((await request(deckPath, undefined, outsider.token, 'GET')).status, 403);
});

test('rooms: concurrent retries preserve one room, one code, one membership and one deck', async () => {
  const host = await user(true, true); const requestId = randomUUID();
  const created = await Promise.all([1, 2].map(() => call('createRoom', { requestId }, host)));
  assert.deepEqual(created.map(r => r.status), [200, 200]);
  assert.deepEqual(created[1].data.result, created[0].data.result);
  const { roomId, joinCode } = created[0].data.result;
  assert.equal((await db.collection('rooms').get()).size, 1);
  assert.equal((await db.collection('roomCodes').get()).size, 1);
  const guest = await user();
  const joins = await Promise.all([1, 2].map(() => join(joinCode, guest)));
  assert.deepEqual(joins.map(r => r.status), [200, 200]);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 2);
  const starts = await Promise.all([1, 2].map(() => start(roomId, host)));
  assert.deepEqual(starts.map(r => r.status), [200, 200]);
  assert.deepEqual(starts[1].data.result, starts[0].data.result, 'both answers name the one stored deck');
  assert.equal((await db.collection('restaurantDecks').get()).size, 1);
});

test('rooms: join attempts are bounded; revoked and expired memberships cannot reconnect', async () => {
  const host = await user(true, true); const guest = await user();
  const { roomId, joinCode } = await room(host);
  assert.equal((await join(joinCode, guest)).status, 200);
  await db.doc(`rooms/${roomId}/members/${guest.uid}`).update({ active: false });
  assert.equal((await join(joinCode, guest)).status, 403);
  await db.doc(`rooms/${roomId}`).update({ expiresAt: Timestamp.fromMillis(0) });
  assert.equal((await reconnect(roomId, host)).status, 403);
  assert.equal((await start(roomId, host)).status, 403);
  const attacker = await user();
  for (let i = 0; i < 10; i++) assert.equal((await join('ZZZZZZ', attacker)).status, 403);
  assert.equal((await join('ZZZZZZ', attacker)).status, 429);
  assert.equal((await call('joinRoom', { joinCode: 'O0I1L5' }, await user())).status, 400);
});

test('rooms: concurrent new members cannot exceed the room capacity', async () => {
  const host = await user(true, true); const { roomId, joinCode } = await room(host);
  await db.doc(`rooms/${roomId}`).update({ memberCount: 14 });
  const guests = await Promise.all([user(), user()]);
  const results = await Promise.all(guests.map(guest => join(joinCode, guest)));
  assert.deepEqual(results.map(r => r.status).sort(), [200, 400]);
  const full = results.find(r => r.status === 400).data.error;
  assert.deepEqual([full.status, full.details], ['FAILED_PRECONDITION', { reason: 'room-full', capacity: 15 }]);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 15);
  assert.equal((await join('ZZZZZZ', await user())).status, 403, 'a wrong code still reveals nothing');
  const member = guests[results.findIndex(r => r.status === 200)];
  assert.equal((await reconnect(roomId, member)).status, 200, 'members already in can reconnect');
});

test('results: the room closes once every member has voted; only totals are shared', async () => {
  const host = await user(true, true); const guest = await user(); const outsider = await user();
  const { roomId, joinCode } = await room(host);
  assert.equal((await join(joinCode, guest)).status, 200);
  assert.equal((await call('roomResults', { roomId }, guest)).data.result.status, 'lobby');
  assert.equal((await start(roomId, host)).status, 200);
  const D = (await deckOf(roomId)).candidateIds;
  // Host likes the 2nd and 3rd cards; guest likes the 3rd and 4th. The 3rd wins,
  // and the 2nd beats the 4th for backup because it is earlier in the deck.
  const likes = { [host.uid]: [D[1], D[2]], [guest.uid]: [D[2], D[3]] };
  for (const candidate of D) assert.equal((await vote(roomId, host, candidate, likes[host.uid].includes(candidate))).status, 200);
  const pending = await call('roomResults', { roomId }, guest);
  assert.equal(pending.data.result.status, 'voting');
  assert.equal(pending.data.result.results, null);
  assert.equal(pending.data.result.voters, 1);
  for (const candidate of D) assert.equal((await vote(roomId, guest, candidate, likes[guest.uid].includes(candidate))).status, 200);
  assert.equal((await call('roomResults', { roomId }, outsider)).status, 403);
  const final = await call('roomResults', { roomId }, guest);
  assert.equal(final.data.result.status, 'closed');
  const { winnerCard, backupCard, ...totals } = final.data.result.results;
  assert.deepEqual(totals, {
    likes: { [D[0]]: 0, [D[1]]: 1, [D[2]]: 2, [D[3]]: 1, [D[4]]: 0 },
    winner: D[2], backup: D[1], voters: 2,
  });
  const deck = await deckOf(roomId);
  const cardOf = id => deck.candidates.find(candidate => candidate.id === id);
  for (const [card, id] of [[winnerCard, D[2]], [backupCard, D[1]]]) {
    const { id: cardId, name, address, distanceMeters, latitude, longitude, phone, website } = cardOf(id);
    assert.deepEqual(card, { id: cardId, name, address, distanceMeters, latitude, longitude, phone, website },
      'the room keeps just enough of the winner and backup to outlive the deck');
  }
  assert.ok(deck.expiresAt.toMillis() <= Date.now() + 15 * 60000, 'the deck goes about 15 minutes after closing');
  const stored = (await readRoom(roomId, host)).data.fields;
  assert.equal(stored.status.stringValue, 'closed');
  assert.ok(!JSON.stringify(stored).includes(guest.uid), 'results never name voters');
  assert.equal((await readBallot(roomId, guest.uid, D[2], host)).status, 403);
});

test('results: the voting window closes an incomplete room; the host can close early', async () => {
  const host = await user(true, true); const guest = await user();
  const first = await room(host);
  assert.equal((await join(first.joinCode, guest)).status, 200);
  assert.equal((await start(first.roomId, host)).status, 200);
  const D = (await deckOf(first.roomId)).candidateIds;
  assert.equal((await vote(first.roomId, guest, D[4])).status, 200);
  await db.doc(`rooms/${first.roomId}`).update({ votingEndsAt: Timestamp.fromMillis(Date.now() - 1000) });
  const timedOut = await call('roomResults', { roomId: first.roomId }, guest);
  assert.equal(timedOut.data.result.status, 'closed');
  assert.equal(timedOut.data.result.results.winner, D[4]);
  assert.equal((await vote(first.roomId, guest, D[0])).status, 403, 'closed rooms take no ballots');

  const second = await room(host);
  assert.equal((await join(second.joinCode, guest)).status, 200);
  assert.equal((await call('closeRoom', { roomId: second.roomId }, guest)).status, 403);
  const closed = await call('closeRoom', { roomId: second.roomId }, host);
  assert.equal(closed.data.result.status, 'closed');
  assert.equal(closed.data.result.results, null, 'closing before the deck starts has no results');
  assert.equal((await db.doc(`roomCodes/${second.joinCode}`).get()).exists, false);
  assert.equal((await start(second.roomId, host)).data.result.candidateCount, 0);
});

test('sweep: closes rooms whose voting ran out unattended and deletes expired decks', async () => {
  const sweeper = createRoomHandlers({ db, FieldValue, Timestamp, HttpsError, deleteAuthUser: async () => {} });
  const host = await user(true, true); const guest = await user();
  const stale = await room(host);
  const live = await room(host);
  assert.equal((await join(stale.joinCode, guest)).status, 200);
  for (const target of [stale, live]) assert.equal((await start(target.roomId, host)).status, 200);
  const D = (await deckOf(stale.roomId)).candidateIds;
  assert.equal((await vote(stale.roomId, guest, D[3])).status, 200);
  await db.doc(`rooms/${stale.roomId}`).update({ votingEndsAt: Timestamp.fromMillis(Date.now() - 1000) });
  await db.doc('restaurantDecks/old').set({ ownerUid: host.uid, targetType: 'room', targetId: 'GONE',
    candidateIds: [], candidates: [], expiresAt: Timestamp.fromMillis(Date.now() - 1000) });

  const first = await sweeper.sweep();
  assert.deepEqual(first, { roomsClosed: 1, decksDeleted: 1 });
  const closed = (await db.doc(`rooms/${stale.roomId}`).get()).data();
  assert.equal(closed.status, 'closed');
  assert.equal(closed.results.winner, D[3]);
  assert.equal(closed.results.winnerCard.id, D[3]);
  assert.equal((await db.doc(`rooms/${live.roomId}`).get()).data().status, 'voting', 'open votes are left alone');
  assert.equal((await db.doc('restaurantDecks/old').get()).exists, false);
  assert.equal((await db.collection('restaurantDecks').get()).size, 2, 'decks still in use are kept');

  const staleDeck = (await db.doc(`rooms/${stale.roomId}`).get()).data().deckId;
  await db.doc(`restaurantDecks/${staleDeck}`).update({ expiresAt: Timestamp.fromMillis(Date.now() - 1000) });
  assert.deepEqual(await sweeper.sweep(), { roomsClosed: 0, decksDeleted: 1 }, 'repeat runs are harmless');
  assert.equal((await readRoom(stale.roomId, guest)).status, 200, 'the result outlives the deck');
});

test('host controls: revoke removes a member; codes rotate only in the lobby', async () => {
  const host = await user(true, true); const guest = await user(); const late = await user();
  const { roomId, joinCode } = await room(host);
  assert.equal((await join(joinCode, guest)).status, 200);
  assert.equal((await call('revokeMember', { roomId, memberUid: host.uid }, guest)).status, 403);
  assert.equal((await call('revokeMember', { roomId, memberUid: host.uid }, host)).status, 403);
  assert.equal((await call('revokeMember', { roomId, memberUid: guest.uid }, host)).status, 200);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 1);
  assert.equal((await readRoom(roomId, guest)).status, 403);
  assert.equal((await join(joinCode, guest)).status, 403);

  assert.equal((await call('rotateJoinCode', { roomId }, guest)).status, 403);
  const rotated = await call('rotateJoinCode', { roomId }, host);
  assert.equal(rotated.status, 200);
  const fresh = rotated.data.result.joinCode;
  assert.notEqual(fresh, joinCode);
  assert.equal((await join(joinCode, late)).status, 403, 'the old code is dead');
  assert.equal((await join(fresh, late)).status, 200);
  assert.equal((await start(roomId, host)).status, 200);
  assert.equal((await call('rotateJoinCode', { roomId }, host)).status, 403);
});

test('account deletion removes memberships, ballots, hosted rooms, receipts and the Auth user', async () => {
  const host = await user(true, true); const guest = await user(); const other = await user();
  const hosted = await room(host);
  const voting = await room(host);
  assert.equal((await start(voting.roomId, host)).status, 200);
  const otherHost = await user(true, true);
  const { roomId, joinCode } = await room(otherHost);
  for (const member of [guest, other]) assert.equal((await join(joinCode, member)).status, 200);
  assert.equal((await join(hosted.joinCode, guest)).status, 200);
  assert.equal((await start(roomId, otherHost)).status, 200);
  assert.equal((await vote(roomId, guest, (await deckOf(roomId)).candidateIds[0])).status, 200);

  // Guests can delete without re-entering a password.
  assert.equal((await call('deleteAccount', null, guest)).status, 200);
  assert.equal((await db.doc(`rooms/${roomId}/members/${guest.uid}`).get()).exists, false);
  assert.equal((await db.collection(`rooms/${roomId}/votes/${guest.uid}/ballot`).get()).size, 0);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 2);
  assert.equal((await db.doc(`rooms/${hosted.roomId}/members/${guest.uid}`).get()).exists, false);
  assert.equal((await auth('lookup', { idToken: guest.token })).status, 400);
  assert.equal((await readRoom(roomId, other)).status, 200, 'other members are unaffected');

  // Registered accounts must have signed in recently.
  assert.equal((await call('deleteAccount', {}, { token: staleToken(host.uid) })).status, 400);
  assert.equal((await db.doc(`rooms/${hosted.roomId}`).get()).data().status, 'lobby');
  assert.equal((await call('deleteAccount', {}, host)).status, 200);
  const decks = await db.collection('restaurantDecks').get();
  assert.deepEqual(decks.docs.map(deck => deck.data().ownerUid), [otherHost.uid], 'the host decks are gone');
  const closed = (await db.doc(`rooms/${hosted.roomId}`).get()).data();
  assert.equal(closed.status, 'closed');
  assert.ok(closed.expiresAt.toMillis() <= Date.now(), 'hosted rooms expire immediately');
  assert.equal((await db.doc(`roomCodes/${hosted.joinCode}`).get()).exists, false);
  assert.equal((await db.collection('_requests').where('uidHash', '!=', '').get()).docs
    .filter(receipt => receipt.data().roomId === hosted.roomId).length, 0);
  assert.equal((await auth('lookup', { idToken: host.token })).status, 400);
  assert.equal((await call('deleteAccount', {}, { token: staleToken(other.uid, 'anonymous') })).status, 200,
    'guests have no password to re-enter');
});

test('account deletion is safe to repeat after a partial failure', async () => {
  const host = await user(true, true); const guest = await user(); const other = await user();
  const { roomId, joinCode } = await room(host);
  for (const member of [guest, other]) assert.equal((await join(joinCode, member)).status, 200);
  // A deletion that removed the membership and fixed the count, then stopped before the Auth user.
  await db.doc(`rooms/${roomId}/members/${guest.uid}`).delete();
  await db.doc(`rooms/${roomId}`).update({ memberCount: 2 });
  assert.equal((await call('deleteAccount', {}, guest)).status, 200);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 2, 'no second decrement');
  assert.equal((await auth('lookup', { idToken: guest.token })).status, 400);
  // Repeating once everything is gone still reports success.
  assert.equal((await call('deleteAccount', {}, guest)).status, 200);
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().memberCount, 2);
  assert.equal((await readRoom(roomId, other)).status, 200);
});

test('preview status identifies the local room worker', async () => {
  const response = await call('roomsStatus', {});
  assert.equal(response.status, 200);
  assert.deepEqual(response.data.result, { project: PROJECT, policy: 'rooms' });
});

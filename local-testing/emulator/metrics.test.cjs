// Usage counts and the owner's insights report through the real handlers and
// the Firestore emulator, with a controllable clock. No network beyond the
// loopback emulator.
const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID, createHash } = require('node:crypto');
const { createRequire } = require('node:module');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
const fromRooms = createRequire(require.resolve('../../rooms/package.json'));
const { Firestore, Timestamp, FieldValue } = fromRooms('firebase-admin/firestore');
const { HttpsError } = fromRooms('firebase-functions/v2/https');
const { createRoomHandlers } = require('../../rooms/handlers.js');
const { createFakeProvider } = require('../../rooms/search/fake-provider.js');
const { monthOf } = require('../../rooms/metrics.js');

const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const SEARCH = Object.freeze({ origin: { lat: 38.5, lng: -98.5 }, radius: { value: 5, unit: 'mi' }, deckSize: 5 });
const OWNER = 'Owner@Example.test';
const DAY = 24 * 3600000;

let clock;
const handlersWith = () => createRoomHandlers({ db, FieldValue, Timestamp, HttpsError, provider: createFakeProvider(),
  now: () => clock, deleteAuthUser: async () => {},
  insightsOwners: [createHash('sha256').update(OWNER.toLowerCase()).digest('hex')] });
const caller = (uid, provider = 'password', verified = true, email = `${uid}@example.test`) => ({ auth: { uid,
  token: { firebase: { sign_in_provider: provider }, email_verified: verified, email,
    auth_time: Math.floor(clock / 1000) } } });
const guest = uid => caller(uid, 'anonymous', false, undefined);
const owner = () => caller('owner1', 'google.com', true, OWNER);
const configure = fields => db.doc('config/liveSearch').set({ enabled: true, weeklyCaps: { free: 3 },
  monthlyCallStop: 100, ...fields });
const fails = (promise, code) => assert.rejects(promise, error => error.code === code);
const today = () => new Date(clock).toISOString().slice(0, 10);

// One day's totals, added up across its shards.
async function totals(day = today()) {
  const shards = await db.collection('metrics').where('day', '==', day).get();
  const sum = {};
  for (const shard of shards.docs) {
    for (const [name, value] of Object.entries(shard.data().counts)) sum[name] = (sum[name] ?? 0) + value;
  }
  return sum;
}

async function lobbyWithGuest(handlers, host, member) {
  const { roomId, joinCode } = await handlers.createRoom({ ...caller(host), data: { requestId: randomUUID() } });
  await handlers.joinRoom({ ...guest(member), data: { joinCode } });
  return roomId;
}

async function vote(roomId, uid, candidateId, liked) {
  const room = (await db.doc(`rooms/${roomId}`).get()).data();
  await db.doc(`rooms/${roomId}/votes/${uid}/ballot/${candidateId}`).set({ liked,
    at: Timestamp.fromMillis(clock), expiresAt: room.expiresAt });
}

beforeEach(async () => {
  const response = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(response.status, 200);
  clock = Date.parse('2026-11-06T15:00:00Z');
});
after(() => db.terminate());

test('a room counts its creation, join, search and how it ended; the winner counts toward local favorites', async () => {
  await configure();
  const handlers = handlersWith();
  const roomId = await lobbyWithGuest(handlers, 'host1', 'guest1');
  const started = await handlers.startRoom({ ...caller('host1'), data: { roomId, search: SEARCH,
    lists: { favorites: true, never: false } } });
  clock += 3 * 60000;
  for (const id of started.candidates.map(candidate => candidate.id)) {
    await vote(roomId, 'host1', id, id === started.candidates[1].id);
    await vote(roomId, 'guest1', id, id === started.candidates[1].id);
  }
  const closed = await handlers.roomResults({ ...guest('guest1'), data: { roomId } });
  assert.equal(closed.status, 'closed');
  // Asking again changes nothing.
  await handlers.roomResults({ ...caller('host1'), data: { roomId } });
  const counts = await totals();
  assert.equal(counts.roomsCreated, 1);
  assert.equal(counts.roomJoins, 1);
  assert.equal(counts.roomJoinsGuest, 1);
  assert.equal(counts.searchesRoom, 1);
  assert.equal(counts.roomsWithFavorites, 1);
  assert.equal(counts.roomsWithNever, undefined);
  assert.equal(counts.radius_5mi, 1);
  assert.equal(counts.roomsCompleted, 1);
  assert.equal(counts.roomsUnanimous, 1);
  assert.equal(counts.roomVoters_two, 1);
  assert.equal(counts.decided_twoTo5m, 1);
  assert.equal(counts.ballotsCast, 10);
  assert.equal(counts.ballotsLiked, 2);
  assert.ok(counts.providerCalls >= 1);
  const winner = started.candidates[1].id;
  const stats = (await db.doc(`placeStats/${winner}`).get()).data();
  assert.equal(stats.wins[monthOf(clock)], 1);
  assert.equal(stats.voters[monthOf(clock)], 2);
  assert.ok(!JSON.stringify(stats).includes('host1') && !JSON.stringify(stats).includes(roomId),
    'a place\'s wins never say who or which room');
  const everything = JSON.stringify((await db.collection('metrics').get()).docs.map(doc => doc.data()));
  for (const secret of ['host1', 'guest1', roomId, winner, '38.5']) {
    assert.ok(!everything.includes(secret), `${secret} stays out of the counts`);
  }
});

test('local favorites stay off until switched on, then mark places past both bars', async () => {
  const handlers = handlersWith();
  const pick = async () => handlers.createQuickPick({ ...caller('host2'), data: { requestId: randomUUID(),
    search: { ...SEARCH, deckSize: 10 } } });
  await configure();
  const first = await pick();
  const deck = async id => (await db.doc(`restaurantDecks/${id}`).get()).data();
  const ids = (await deck(first.deckId)).candidateIds;
  await db.doc(`placeStats/${ids[0]}`).set({ wins: { [monthOf(clock)]: 6 }, voters: { [monthOf(clock)]: 20 } });
  await db.doc(`placeStats/${ids[1]}`).set({ wins: { [monthOf(clock)]: 6 }, voters: { [monthOf(clock)]: 4 } });
  const off = await deck((await pick()).deckId);
  assert.ok(off.candidates.every(candidate => candidate.popular === undefined), 'the switch is off');
  await configure({ hotPicks: { enabled: true } });
  const on = await deck((await pick()).deckId);
  const popular = on.candidates.filter(candidate => candidate.popular).map(candidate => candidate.id);
  assert.deepEqual(popular, on.candidates.some(candidate => candidate.id === ids[0]) ? [ids[0]] : []);
  assert.ok(!popular.includes(ids[1]), 'a few people picking it often is not enough');
});

test('weekly cap and failed searches are counted', async () => {
  await configure({ weeklyCaps: { free: 1 } });
  const handlers = handlersWith();
  const pick = () => handlers.createQuickPick({ ...caller('host3'), data: { requestId: randomUUID(), search: SEARCH } });
  await pick();
  await fails(pick(), 'resource-exhausted');
  const counts = await totals();
  assert.equal(counts.searchesQuickPick, 1);
  assert.equal(counts.weeklyCapHits, 1);
  const rerolls = await handlers.createQuickPick({ ...caller('host4'), data: { requestId: randomUUID(), search: SEARCH } });
  await handlers.rerollQuickPick({ ...caller('host4'), data: { quickPickId: rerolls.quickPickId, from: 0 } });
  await handlers.rerollQuickPick({ ...caller('host4'), data: { quickPickId: rerolls.quickPickId, from: 0 } });
  assert.equal((await totals()).quickPickRerolls, 1, 'a retried reroll counts once');
});

test('app opens count once a day per session, with day-1, 7 and 30 returns', async () => {
  const handlers = handlersWith();
  const open = (who, platform = 'android') => handlers.appStatus({ ...who, data: { build: 51, platform } });
  const first = today();
  await open(guest('g1'));
  await open(guest('g1'));
  await open(caller('a1'), 'web');
  let counts = await totals();
  assert.equal(counts.activeGuests, 1);
  assert.equal(counts.newGuests, 1);
  assert.equal(counts.activeAccounts, 1);
  assert.equal(counts.newAccounts, 1);
  assert.equal(counts.activeOn_android, 1);
  assert.equal(counts.activeOn_web, 1);
  assert.equal(counts.activeBuild_51, 2);
  // The guest signs up later that day: an upgrade, not a second active session.
  await open(caller('g1'));
  counts = await totals();
  assert.equal(counts.guestsUpgraded, 1);
  assert.equal(counts.activeGuests, 1);
  clock += DAY;
  await open(caller('g1'));
  clock += 7 * DAY;
  await open(caller('g1'));
  const cohort = await totals(first);
  assert.equal(cohort.returned_d1, 1);
  assert.equal(cohort.accountReturned_d1, 1);
  assert.equal(cohort.returned_d7, 1);
  const record = (await db.doc('userActivity/g1').get()).data();
  assert.deepEqual(Object.keys(record).sort(), ['accountDay', 'expiresAt', 'firstDay', 'lastDay', 'registered', 'returned']);
  for (const data of [{ build: 1, platform: 'windows' }, { build: 1, platform: 'web', uid: 'x' }]) {
    await fails(handlers.appStatus({ ...guest('g1'), data }), 'invalid-argument');
  }
  // Deleting the account removes its activity record.
  await handlers.deleteAccount({ ...caller('g1'), data: {} });
  assert.equal((await db.doc('userActivity/g1').get()).exists, false);
  assert.equal((await totals()).accountsDeleted, 1);
});

test('the app may count only the fixed taps', async () => {
  const handlers = handlersWith();
  await handlers.countEvent({ ...guest('g2'), data: { name: 'resultDirections' } });
  await handlers.countEvent({ ...caller('a2'), data: { name: 'introSkipped' } });
  for (const data of [{ name: 'somethingElse' }, { name: 'toString' }, { name: 'resultMap', place: 'x' }, {},
    { name: 'tap_resultMap' }]) {
    await fails(handlers.countEvent({ ...guest('g2'), data }), 'invalid-argument');
  }
  await fails(handlers.countEvent({ data: { name: 'resultMap' } }), 'unauthenticated');
  const counts = await totals();
  assert.equal(counts.tap_resultDirections, 1);
  assert.equal(counts.tap_introSkipped, 1);
  assert.equal(Object.keys(counts).length, 2);
});

test('only the owner\'s Google sign-in reads the insights report', async () => {
  await configure({ weeklyCaps: { free: 4 }, monthlyCallStop: 300 });
  const handlers = handlersWith();
  await handlers.countEvent({ ...guest('g3'), data: { name: 'resultMap' } });
  clock += DAY;
  await handlers.countEvent({ ...guest('g3'), data: { name: 'resultMap' } });
  await handlers.countEvent({ ...guest('g3'), data: { name: 'resultPhone' } });
  await db.doc(`usageMonths/fake_${monthOf(clock)}`).set({ callsCompleted: 7, callsReserved: 0, generationsCompleted: 5 });
  const range = { from: '2026-11-01', to: '2026-11-07' };
  const report = await handlers.insightsReport({ ...owner(), data: range });
  assert.deepEqual(report.days, { '2026-11-06': { tap_resultMap: 1 }, '2026-11-07': { tap_resultMap: 1, tap_resultPhone: 1 } });
  assert.deepEqual(report.months, { '2026-11': { providerCalls: 7, decks: 5 } });
  assert.deepEqual(report.live, { enabled: true, weeklyCap: 4, monthlyCallStop: 300, provider: 'fake' });
  for (const who of [caller('owner1', 'password', true, OWNER), caller('owner1', 'google.com', false, OWNER),
    caller('someone', 'google.com', true, 'someone@example.test'), guest('g3'), caller('a3')]) {
    await fails(handlers.insightsReport({ ...who, data: range }), 'permission-denied');
  }
  for (const data of [{}, { from: '2026-11-07', to: '2026-11-01' }, { from: '2025-01-01', to: '2026-11-07' },
    { ...range, uid: 'x' }]) {
    await fails(handlers.insightsReport({ ...owner(), data }), 'invalid-argument');
  }
});

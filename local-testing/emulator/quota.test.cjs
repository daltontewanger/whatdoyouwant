// Live-search limits through the real handlers and the Firestore emulator, with
// a controllable clock and provider. No network beyond the loopback emulator.
const { test, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { createRequire } = require('node:module');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
const fromRooms = createRequire(require.resolve('../../rooms/package.json'));
const { Firestore, Timestamp, FieldValue } = fromRooms('firebase-admin/firestore');
const { HttpsError } = fromRooms('firebase-functions/v2/https');
const { createRoomHandlers } = require('../../rooms/handlers.js');
const { createFakeProvider, EMPTY_ORIGIN } = require('../../rooms/search/fake-provider.js');
const { ProviderUnavailable } = require('../../rooms/search/provider.js');
const { weekOf, monthOf } = require('../../rooms/quota.js');
const { LEASE_MS } = require('../../rooms/generation.js');

const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const SEARCH = Object.freeze({ origin: { lat: 38.5, lng: -98.5 }, radius: { value: 5, unit: 'mi' }, deckSize: 5 });

let clock;
function handlersWith(provider = createFakeProvider(), log = () => {}, extra = {}) {
  return createRoomHandlers({ db, FieldValue, Timestamp, HttpsError, provider, now: () => clock,
    deleteAuthUser: async () => {}, log, ...extra });
}
const caller = (uid, provider = 'password', verified = true) => ({ auth: { uid, token: {
  firebase: { sign_in_provider: provider }, email_verified: verified, auth_time: Math.floor(clock / 1000) } } });
async function lobby(handlers, uid) {
  return (await handlers.createRoom({ ...caller(uid), data: { requestId: randomUUID() } })).roomId;
}
// A start's answer without the cards a fresh start also returns.
const pointer = ({ candidates, ...rest }) => rest;
const start = (handlers, uid, roomId, search = SEARCH) => handlers.startRoom({ ...caller(uid), data: { roomId, search } });
const configure = fields => db.doc('config/liveSearch').set({ enabled: true, weeklyCaps: { free: 3 },
  monthlyCallStop: 100, ...fields });
const week = async uid => (await db.doc(`usageWeeks/${uid}_${weekOf(clock).key}`).get()).data();
const month = async (provider = 'fake') => (await db.doc(`usageMonths/${provider}_${monthOf(clock)}`).get()).data();
const fails = (promise, code, reason) => assert.rejects(promise,
  error => error.code === code && (reason === undefined || error.details?.reason === reason));

// A provider that waits until the test lets it answer.
function heldProvider(base = createFakeProvider()) {
  let release;
  let entered;
  const gate = new Promise(resolve => { release = resolve; });
  const reached = new Promise(resolve => { entered = resolve; });
  let calls = 0;
  return {
    provider: { ...base, async searchNearby(request) { calls++; entered(); await gate; return base.searchNearby(request); } },
    release, reached, calls: () => calls,
  };
}

beforeEach(async () => {
  const response = await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(response.status, 200);
  clock = Date.parse('2026-10-08T15:00:00Z');
});
after(() => db.terminate());

test('a start uses one weekly search and the calls it made; asking again costs nothing', async () => {
  await configure();
  const handlers = handlersWith();
  const roomId = await lobby(handlers, 'host1');
  const started = await start(handlers, 'host1', roomId);
  assert.deepEqual(await start(handlers, 'host1', roomId), pointer(started), 'a repeat returns the same deck');
  const stored = (await db.doc(`restaurantDecks/${started.deckId}`).get()).data();
  assert.deepEqual(started.candidates, stored.candidates, 'a fresh start returns the stored cards');
  assert.deepEqual([(await week('host1')).used, (await week('host1')).reserved], [1, 0]);
  const ledger = await month();
  assert.deepEqual([ledger.callsCompleted, ledger.callsReserved, ledger.generationsCompleted], [1, 0, 1]);
  const lease = (await db.doc(`deckGenerations/room_${roomId}`).get()).data();
  assert.deepEqual([lease.status, lease.deckId], ['completed', started.deckId]);
  assert.equal(lease.uid, undefined, 'the lease keeps only a hash of the UID');
});

test('the weekly cap is per account and resets Monday 00:00 UTC', async () => {
  await configure({ weeklyCaps: { free: 2 } });
  const handlers = handlersWith();
  clock = Date.parse('2026-10-11T23:58:00Z'); // Sunday
  for (let i = 0; i < 2; i++) await start(handlers, 'host2', await lobby(handlers, 'host2'));
  const third = await lobby(handlers, 'host2');
  await assert.rejects(start(handlers, 'host2', third), error => error.code === 'resource-exhausted' &&
    error.details.reason === 'weekly-cap' && error.details.resetsAt === '2026-10-12T00:00:00.000Z');
  assert.deepEqual(await handlers.liveSearchStatus({ ...caller('host2'), data: {} }), { eligible: true,
    weeklyCap: 2, used: 2, remaining: 0, resetsAt: '2026-10-12T00:00:00.000Z', newAccount: false, paused: false });
  await start(handlers, 'other2', await lobby(handlers, 'other2'));

  clock = Date.parse('2026-10-12T00:00:01Z'); // Monday
  await start(handlers, 'host2', third);
  assert.equal((await handlers.liveSearchStatus({ ...caller('host2'), data: {} })).remaining, 1);
});

test('an entitlement can raise the cap without a code change', async () => {
  await configure({ weeklyCaps: { free: 1, plus: 2 } });
  await db.doc('entitlements/host3').set({ entitlement: 'plus' });
  const handlers = handlersWith();
  for (let i = 0; i < 2; i++) await start(handlers, 'host3', await lobby(handlers, 'host3'));
  await fails(start(handlers, 'host3', await lobby(handlers, 'host3')), 'resource-exhausted', 'weekly-cap');
});

test('the kill switch and a missing config pause live search before any provider call', async () => {
  const held = heldProvider();
  held.release();
  const handlers = handlersWith(held.provider);
  const roomId = await lobby(handlers, 'host4');
  await fails(start(handlers, 'host4', roomId), 'unavailable', 'live-search-paused');
  await configure({ enabled: false, pausedReason: 'manual' });
  await fails(start(handlers, 'host4', roomId), 'unavailable', 'live-search-paused');
  await configure({ monthlyCallStop: 'lots' });
  await fails(start(handlers, 'host4', roomId), 'unavailable', 'live-search-paused');
  assert.equal(held.calls(), 0);
  assert.equal(await week('host4'), undefined, 'nothing was charged');
  assert.equal((await handlers.liveSearchStatus({ ...caller('host4'), data: {} })).paused, true);

  await configure();
  const started = await start(handlers, 'host4', roomId);
  await configure({ enabled: false });
  assert.deepEqual(await start(handlers, 'host4', roomId), pointer(started), 'a room that has its deck still opens');
});

test('the monthly stop is per provider, counts the worst case, and resets with the month', async () => {
  await configure({ monthlyCallStop: 2 });
  const fake = handlersWith(createFakeProvider({ simulatedCalls: 1 }));
  for (let i = 0; i < 2; i++) await start(fake, `host5-${i}`, await lobby(fake, `host5-${i}`));
  await fails(start(fake, 'host5-2', await lobby(fake, 'host5-2')), 'unavailable', 'live-search-paused');

  const here = handlersWith({ ...createFakeProvider({ simulatedCalls: 2 }), id: 'here' });
  await start(here, 'host5-3', await lobby(here, 'host5-3'));
  assert.equal((await month('here')).callsCompleted, 2, 'each provider has its own ledger');
  await fails(start(here, 'host5-4', await lobby(here, 'host5-4')), 'unavailable', 'live-search-paused');

  clock = Date.parse('2026-11-01T00:00:01Z');
  await start(fake, 'host5-2', await lobby(fake, 'host5-2'));
});

test('usage logs a warning once at half and again at 80% of the monthly stop', async () => {
  await configure({ monthlyCallStop: 10, weeklyCaps: { free: 20 } });
  const logged = [];
  const handlers = handlersWith(createFakeProvider({ simulatedCalls: 1 }), entry => logged.push(entry));
  for (let i = 0; i < 9; i++) await start(handlers, `host8-${i}`, await lobby(handlers, `host8-${i}`));
  const warnings = logged.filter(entry => entry.event === 'live_search_usage');
  assert.deepEqual(warnings.map(entry => [entry.share, entry.calls, entry.stop]), [[0.5, 5, 10], [0.8, 8, 10]]);
  assert.ok(warnings.every(entry => entry.uid === undefined && entry.month === monthOf(clock)));
});

test('failed searches are refunded, but provider calls that happened still count', async () => {
  await configure();
  const failing = (providerCalls) => ({ ...createFakeProvider({ simulatedCalls: 3 }), async searchNearby() {
    throw providerCalls === undefined ? new Error('timeout') : new ProviderUnavailable('down', { providerCalls });
  } });
  let handlers = handlersWith(failing(1));
  const roomId = await lobby(handlers, 'host6');
  await fails(start(handlers, 'host6', roomId), 'unavailable');
  assert.deepEqual([(await week('host6')).used, (await week('host6')).reserved], [0, 0]);
  assert.deepEqual([(await month()).callsCompleted, (await month()).callsReserved], [1, 0]);
  assert.equal((await db.doc(`deckGenerations/room_${roomId}`).get()).data().status, 'failed');

  handlers = handlersWith(failing(undefined));
  await fails(start(handlers, 'host6', roomId), 'unavailable');
  assert.equal((await month()).callsCompleted, 4, 'an unknown outcome counts the worst case');

  handlers = handlersWith();
  await fails(start(handlers, 'host6', roomId, { ...SEARCH, origin: EMPTY_ORIGIN }), 'failed-precondition',
    'too-few-results');
  assert.deepEqual([(await week('host6')).used, (await month()).callsCompleted], [0, 5]);
  await start(handlers, 'host6', roomId);
  assert.equal((await week('host6')).used, 1, 'only the deck that was made is charged');
});

test('a second start while one is running is turned away and nothing is charged twice', async () => {
  await configure();
  const held = heldProvider();
  const handlers = handlersWith(held.provider);
  const roomId = await lobby(handlers, 'host7');
  const first = start(handlers, 'host7', roomId);
  await held.reached;
  await fails(start(handlers, 'host7', roomId), 'aborted', 'in-progress');
  held.release();
  const started = await first;
  assert.deepEqual(await start(handlers, 'host7', roomId), pointer(started));
  assert.equal(held.calls(), 1);
  assert.equal((await week('host7')).used, 1);
});

test('the sweep settles a generation whose call never finished; a late answer is discarded', async () => {
  await configure();
  const held = heldProvider();
  const handlers = handlersWith(held.provider);
  const roomId = await lobby(handlers, 'host8');
  const stuck = start(handlers, 'host8', roomId);
  await held.reached;
  clock += LEASE_MS + 1000;
  const swept = await handlers.sweep();
  assert.equal(swept.leasesSettled, 1);
  assert.deepEqual([(await week('host8')).used, (await week('host8')).reserved], [0, 0]);
  assert.deepEqual([(await month()).callsCompleted, (await month()).callsReserved], [1, 0]);
  assert.equal((await handlers.sweep()).leasesSettled, 0, 'repeat sweeps are harmless');

  held.release();
  await fails(stuck, 'unavailable');
  assert.equal((await db.doc(`rooms/${roomId}`).get()).data().status, 'lobby', 'the late deck was not used');
  assert.equal((await db.collection('restaurantDecks').get()).size, 0);
  await start(handlersWith(), 'host8', roomId);
  assert.equal((await week('host8')).used, 1);
});

test('guests and unverified accounts cannot search or see an allowance', async () => {
  await configure();
  const handlers = handlersWith();
  const roomId = await lobby(handlers, 'host9');
  for (const who of [caller('guest9', 'anonymous', false), caller('host9', 'password', false)]) {
    assert.deepEqual(await handlers.liveSearchStatus({ ...who, data: {} }), { eligible: false });
    await fails(handlers.startRoom({ ...who, data: { roomId, search: SEARCH } }), 'permission-denied');
  }
  await fails(handlers.liveSearchStatus({ ...caller('host9'), data: { uid: 'someone-else' } }), 'invalid-argument');
});

test('old app builds are told to update; the minimum is optional', async () => {
  const handlers = handlersWith();
  const ask = build => handlers.appStatus({ ...caller('guest12', 'anonymous', false), data: { build } });
  assert.deepEqual(await ask(1), { updateRequired: false }, 'no config means no minimum');
  await configure({ minimumClientBuild: 5 });
  assert.deepEqual(await ask(4), { updateRequired: true });
  assert.deepEqual(await ask(5), { updateRequired: false });
  for (const data of [{}, { build: '5' }, { build: 1.5 }, { build: 5, uid: 'x' }]) {
    await fails(handlers.appStatus({ ...caller('guest12', 'anonymous', false), data }), 'invalid-argument');
  }
  await fails(handlers.appStatus({ data: { build: 5 } }), 'unauthenticated');
});

test('deleting an account removes its usage records but not the provider ledger', async () => {
  await configure();
  const handlers = handlersWith();
  const roomId = await lobby(handlers, 'host10');
  await start(handlers, 'host10', roomId);
  await handlers.deleteAccount({ ...caller('host10'), data: {} });
  assert.equal(await week('host10'), undefined);
  assert.equal((await db.doc(`deckGenerations/room_${roomId}`).get()).exists, false);
  assert.equal((await month()).generationsCompleted, 1);
});

const quickPick = (handlers, uid, requestId = randomUUID(), search = SEARCH) =>
  handlers.createQuickPick({ ...caller(uid), data: { requestId, search } });
const reroll = (handlers, uid, quickPickId, from) =>
  handlers.rerollQuickPick({ ...caller(uid), data: { quickPickId, from } });

test('a Quick Pick spends one search; retrying it and rerolling cost nothing', async () => {
  await configure();
  const handlers = handlersWith();
  const requestId = randomUUID();
  const pick = await quickPick(handlers, 'qp1', requestId);
  assert.match(pick.quickPickId, /^[a-f0-9]{24}$/);
  assert.equal(pick.position, 0);
  assert.equal(pick.rerollsLeft, 4, 'a five-card deck allows four rerolls');
  assert.deepEqual(await quickPick(handlers, 'qp1', requestId), pick, 'a retry returns the same pick');
  const deck = (await db.doc(`restaurantDecks/${pick.deckId}`).get()).data();
  assert.equal(deck.targetType, 'quickPick');
  assert.ok(deck.candidateIds.includes(pick.candidateId));
  assert.ok(deck.expiresAt.toMillis() <= clock + 60 * 60000, 'a Quick Pick deck lasts an hour');

  const seen = [pick.candidateId];
  let current = pick;
  while (current.rerollsLeft > 0) {
    current = await reroll(handlers, 'qp1', pick.quickPickId, current.position);
    seen.push(current.candidateId);
  }
  assert.equal(new Set(seen).size, 5, 'every reroll shows a card not seen yet');
  assert.deepEqual(seen, deck.candidateIds, 'cards come in deck order, so preferred cuisines come first');
  assert.deepEqual(await reroll(handlers, 'qp1', pick.quickPickId, current.position - 1), current,
    'a retried reroll does not skip a card');
  await fails(reroll(handlers, 'qp1', pick.quickPickId, current.position), 'failed-precondition', 'no-rerolls');
  assert.equal((await week('qp1')).used, 1);
});

test('rerolls stop at five, and only the owner of a live pick can reroll', async () => {
  await configure();
  const handlers = handlersWith();
  let pick = await quickPick(handlers, 'qp2', randomUUID(), { ...SEARCH, deckSize: 25 });
  assert.equal(pick.rerollsLeft, 5);
  await fails(reroll(handlers, 'someone', pick.quickPickId, 0), 'permission-denied');
  for (let i = 0; i < 5; i++) pick = await reroll(handlers, 'qp2', pick.quickPickId, pick.position);
  await fails(reroll(handlers, 'qp2', pick.quickPickId, pick.position), 'failed-precondition', 'no-rerolls');
  clock += 60 * 60000;
  await fails(reroll(handlers, 'qp2', pick.quickPickId, pick.position), 'permission-denied');
  await fails(handlers.rerollQuickPick({ ...caller('qp2'), data: { quickPickId: pick.quickPickId, from: '1' } }),
    'invalid-argument');
});

test('Quick Pick and Group Room share one weekly cap; guests cannot Quick Pick', async () => {
  await configure({ weeklyCaps: { free: 2 } });
  const handlers = handlersWith();
  await start(handlers, 'qp3', await lobby(handlers, 'qp3'));
  await quickPick(handlers, 'qp3');
  await fails(quickPick(handlers, 'qp3'), 'resource-exhausted', 'weekly-cap');
  await fails(start(handlers, 'qp3', await lobby(handlers, 'qp3')), 'resource-exhausted', 'weekly-cap');
  await fails(handlers.createQuickPick({ ...caller('guest3', 'anonymous', false),
    data: { requestId: randomUUID(), search: SEARCH } }), 'permission-denied');
  await fails(quickPick(handlers, 'qp4', randomUUID(), { ...SEARCH, origin: EMPTY_ORIGIN }), 'failed-precondition',
    'too-few-results');
  assert.equal((await week('qp4')).used, 0);
});

test('deleting an account removes its Quick Picks and their decks', async () => {
  await configure();
  const handlers = handlersWith();
  const pick = await quickPick(handlers, 'qp5');
  await handlers.deleteAccount({ ...caller('qp5'), data: {} });
  assert.equal((await db.doc(`quickPicks/${pick.quickPickId}`).get()).exists, false);
  assert.equal((await db.doc(`restaurantDecks/${pick.deckId}`).get()).exists, false);
});

test('a budget notification at the pause point switches live search off until someone turns it on', async () => {
  const { createBudgetGuard } = require('../../rooms/budget.js');
  const guard = createBudgetGuard({ db, FieldValue });
  await configure();
  const handlers = handlersWith();
  const roomId = await lobby(handlers, 'host11');
  const notice = (costAmount, budgetAmount = 10) => ({ budgetDisplayName: 'staging', costAmount, budgetAmount,
    alertThresholdExceeded: 0.5, currencyType: 'USD' });

  assert.deepEqual(await guard(notice(4.99)), { paused: false });
  assert.deepEqual(await guard({ costAmount: 'n/a' }), { paused: false });
  assert.equal((await db.doc('config/liveSearch').get()).data().enabled, true);

  await db.doc('config/liveSearch').update({ budgetPauseAt: 0.5 });
  assert.deepEqual(await guard(notice(5)), { paused: true });
  const config = (await db.doc('config/liveSearch').get()).data();
  assert.deepEqual([config.enabled, config.pausedReason], [false, 'budget']);
  await fails(start(handlers, 'host11', roomId), 'unavailable', 'live-search-paused');
  assert.deepEqual(await guard(notice(1)), { paused: false }, 'a later, lower notification does not turn it back on');
  assert.equal((await db.doc('config/liveSearch').get()).data().enabled, false);

  await db.doc('config/liveSearch').delete();
  assert.deepEqual(await guard(notice(20)), { paused: true });
  assert.equal(require('../../rooms/quota.js').liveSearchConfig(
    (await db.doc('config/liveSearch').get()).data()).enabled, false, 'still paused with no other settings');
});

test('a new account gets 3 searches in its first 48 hours, then the weekly cap', async () => {
  await configure({ weeklyCaps: { free: 10 } });
  const created = clock - 3600000;
  const handlers = handlersWith(createFakeProvider(), () => {}, { accountCreatedAt: async () => created });
  const status = await handlers.liveSearchStatus({ ...caller('new1'), data: {} });
  assert.deepEqual([status.weeklyCap, status.remaining, status.newAccount], [3, 3, true]);
  assert.equal(status.resetsAt, new Date(created + 48 * 3600000).toISOString());
  await quickPick(handlers, 'new1');
  await start(handlers, 'new1', await lobby(handlers, 'new1'));
  await quickPick(handlers, 'new1');
  await assert.rejects(quickPick(handlers, 'new1'), error => error.code === 'resource-exhausted' &&
    error.details?.reason === 'new-account-cap' && error.details.resetsAt === new Date(created + 48 * 3600000).toISOString());
  // The same week, once the account is two days old: the rest of the weekly 10.
  clock = created + 48 * 3600000 + 1;
  const later = await handlers.liveSearchStatus({ ...caller('new1'), data: {} });
  assert.deepEqual([later.weeklyCap, later.used, later.remaining, later.newAccount], [10, 3, 7, false]);
  await quickPick(handlers, 'new1');
  // Config can switch the rule off.
  await configure({ weeklyCaps: { free: 10 }, newAccounts: { enabled: false } });
  assert.equal((await handlersWith(createFakeProvider(), () => {}, { accountCreatedAt: async () => clock })
    .liveSearchStatus({ ...caller('new2'), data: {} })).weeklyCap, 10);
});

test('when Auth cannot say how old an account is, it gets the normal allowance', async () => {
  await configure({ weeklyCaps: { free: 10 } });
  const logs = [];
  const handlers = handlersWith(createFakeProvider(), entry => logs.push(entry),
    { accountCreatedAt: async () => { throw new Error('auth unavailable'); } });
  for (let i = 0; i < 4; i++) await quickPick(handlers, 'unknown1');
  assert.ok(logs.some(entry => entry.event === 'account_age_unknown'));
});

const from = (network, request = {}) => ({ ...request, rawRequest: { headers: { 'x-forwarded-for': `9.9.9.9, ${network}` } } });

test('network limits: a flood from one network is turned away before any work, whatever the account', async () => {
  const handlers = handlersWith(createFakeProvider(), () => {}, { networkLimits: 'enforce' });
  // No sign-in: each call fails in the handler, but still counts for its network.
  for (let i = 0; i < 120; i++) {
    await assert.rejects(handlers.joinRoom(from('203.0.113.5', { data: {} })), error => error.code === 'unauthenticated');
  }
  await fails(handlers.joinRoom(from('203.0.113.5', { data: {} })), 'resource-exhausted');
  await fails(handlers.joinRoom(from('203.0.113.6', { data: {} })), 'unauthenticated');
  clock += 60000;
  await fails(handlers.joinRoom(from('203.0.113.5', { data: {} })), 'unauthenticated');
});

test('network limits: join attempts are counted per network across fresh guest accounts', async () => {
  const handlers = handlersWith(createFakeProvider(), () => {}, { networkLimits: 'enforce' });
  for (let i = 0; i < 100; i++) {
    await fails(handlers.joinRoom(from('198.51.100.20', { ...caller(`g${i}`, 'anonymous', false),
      data: { joinCode: 'ZZZZZZ' } })), 'permission-denied');
    if (i % 50 === 49) clock += 60000; // stay under the in-memory per-minute window
  }
  await fails(handlers.joinRoom(from('198.51.100.20', { ...caller('g100', 'anonymous', false),
    data: { joinCode: 'ZZZZZZ' } })), 'resource-exhausted');
  // Another network is unaffected, and the count is a hashed record, not the address.
  await fails(handlers.joinRoom(from('198.51.100.21', { ...caller('g101', 'anonymous', false),
    data: { joinCode: 'ZZZZZZ' } })), 'permission-denied');
  const limits = await db.collection('_limits').get();
  assert.ok(limits.docs.every(doc => !doc.id.includes('198.51') && !JSON.stringify(doc.data()).includes('198.51')));
});

test('network limits in log mode never refuse; they log a short hash and what would be refused', async () => {
  const logs = [];
  const handlers = handlersWith(createFakeProvider(), entry => logs.push(entry), { networkLimits: 'log' });
  for (let i = 0; i < 125; i++) {
    await assert.rejects(handlers.joinRoom(from('203.0.113.7', { data: {} })), error => error.code === 'unauthenticated');
  }
  const seen = logs.filter(entry => entry.event === 'network_seen');
  assert.equal(seen.length, 1, 'once a minute per action');
  assert.equal(seen[0].forwardedEntries, 2);
  assert.match(seen[0].networkHash, /^[0-9a-f]{12}$/);
  assert.ok(!JSON.stringify(logs).includes('203.0.113'), 'the address itself is never logged');
  assert.deepEqual(logs.filter(entry => entry.event === 'network_limit_reached'),
    [{ event: 'network_limit_reached', action: 'joinRoom', scope: 'minute', mode: 'log' }]);
});

test('network limits are off by default and ignore calls with no address', async () => {
  const handlers = handlersWith();
  for (let i = 0; i < 130; i++) {
    await assert.rejects(handlers.joinRoom(from('203.0.113.8', { data: {} })), error => error.code === 'unauthenticated');
  }
  const enforcing = handlersWith(createFakeProvider(), () => {}, { networkLimits: 'enforce' });
  for (let i = 0; i < 130; i++) {
    await assert.rejects(enforcing.joinRoom({ data: {} }), error => error.code === 'unauthenticated');
  }
  assert.throws(() => handlersWith(createFakeProvider(), () => {}, { networkLimits: 'sometimes' }), /Unknown network limit mode/);
});

test('network limits leave scheduled work alone: the sweep runs with no caller', async () => {
  for (const networkLimits of ['enforce', 'log']) {
    const handlers = handlersWith(createFakeProvider(), () => {}, { networkLimits });
    await handlers.sweep();
  }
});

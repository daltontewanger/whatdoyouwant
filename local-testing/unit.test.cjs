const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createSearchHandler } = require('../functions/search');
const { assertLocalEnvironment, discover } = require('./support.cjs');
const { installHttpGuard } = require('./network-guard.cjs');

test('local worker rejects accidental external HTTP before making a request', () => {
  const restore = installHttpGuard();
  try {
    assert.throws(() => require('node:https').get('https://discover.search.hereapi.com/'), /External HTTP/);
    assert.throws(() => require('node:http').request({ hostname: 'example.com' }), /External HTTP/);
    assert.throws(() => require('node:http').request('http://localhost/', { hostname: 'example.com' }), /External HTTP/);
    assert.throws(() => fetch('https://example.com/'), /External HTTP/);
  } finally { restore(); }
});

test('production callable still rejects missing App Check before running search', async () => {
  const fn = require('../functions/index').fetchNearbyRestaurants;
  assert.deepEqual(fn.__endpoint.secretEnvironmentVariables.map(secret => secret.key), ['HERE_API_KEY']);
  const fromFunctions = require('node:module').createRequire(require.resolve('../functions/package.json'));
  const express = fromFunctions('express');
  const app = express();
  app.use(express.json());
  app.post('/', fn);
  const server = require('node:http').createServer(app);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { baseLat: 40, baseLon: -75 } }),
    });
    assert.equal(response.status, 401);
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});

const safe = {
  GCLOUD_PROJECT: 'demo-whatdoyouwant', FUNCTIONS_EMULATOR: 'true',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
};

test('local mode rejects production IDs, remote endpoints, missing emulator flags and credentials', () => {
  assert.doesNotThrow(() => assertLocalEnvironment(safe));
  for (const change of [
    { GCLOUD_PROJECT: 'what-do-you-want-8a404' }, { FUNCTIONS_EMULATOR: '' },
    { FIRESTORE_EMULATOR_HOST: 'example.com:8080' }, { FIREBASE_AUTH_EMULATOR_HOST: '' },
    { GOOGLE_APPLICATION_CREDENTIALS: 'not-a-real-file' }, { HERE_API_KEY: 'dummy' },
  ]) assert.throws(() => assertLocalEnvironment({ ...safe, ...change }));
});

function setup(count = 0, provider = discover) {
  let stored = count;
  let calls = 0;
  const handler = createSearchHandler({
    db: {
      collection: () => ({ doc: () => ({}) }),
      runTransaction: async fn => fn({
        get: async () => ({ exists: true, data: () => ({ count: stored }) }),
        set: (_ref, data) => { stored = data.count; },
      }),
    },
    serverTimestamp: () => 'test-time',
    discover: async params => { calls++; return provider(params); },
  });
  return { handler, count: () => stored, calls: () => calls };
}
const request = { data: { baseLat: 40, baseLon: -75 } };

test('invalid request does not reserve usage or invoke the provider', async () => {
  const state = setup();
  await assert.rejects(state.handler({ data: {} }), { code: 'invalid-argument' });
  assert.equal(state.count(), 0);
  assert.equal(state.calls(), 0);
});
test('four fixture requests reserve four calls and deduplicate repeated results', async () => {
  const state = setup();
  const result = await state.handler(request);
  assert.equal(state.count(), 4);
  assert.equal(state.calls(), 4);
  assert.equal(result.restaurants.length, 5);
  assert.equal(result.restaurants[0].distance, 400 * 0.000621371);
});
test('monthly cap blocks the provider before any request', async () => {
  const state = setup(29497);
  await assert.rejects(state.handler(request), { code: 'resource-exhausted' });
  assert.equal(state.count(), 29497);
  assert.equal(state.calls(), 0);
});
test('characterization: failed HERE request currently retains all four reserved calls', async () => {
  const state = setup(0, async () => { throw new Error('simulated provider failure'); });
  await assert.rejects(state.handler(request), /simulated provider failure/);
  assert.equal(state.count(), 4);
  assert.equal(state.calls(), 1);
});

test('app error reports are scrubbed, shape-checked and rate limited per caller', () => {
  const { createClientErrorReporter, scrub, LIMIT_PER_HOUR } = require('../rooms/client-errors.js');
  let clock = 0;
  const logged = [];
  const invalid = () => { throw new Error('invalid'); };
  const report = createClientErrorReporter({ now: () => clock, log: entry => logged.push(entry), invalid });

  report('u1', { message: 'Bad state for pat@example.com near 38.50123,-98.51234', build: 7,
    stack: 'at main (https://getwhatdoyouwant.app/app/main.dart.js?v=1#x:10:5)' });
  assert.deepEqual(logged[0], { event: 'client_error', build: 7, fatal: false,
    message: 'Bad state for [email] near [number],[number]',
    stack: 'at main (https://getwhatdoyouwant.app/app/main.dart.js)' });
  assert.equal(logged[0].uid, undefined);
  assert.equal(scrub('x'.repeat(900), 500).length, 500);

  for (const bad of [null, [], { message: '', build: 1 }, { message: 'x', build: -1 }, { message: 'x', build: 1, uid: 'u' },
    { message: 'x', build: 1, fatal: 'yes' }, { message: 1, build: 1 }]) {
    assert.throws(() => report('u1', bad), /invalid/, JSON.stringify(bad));
  }

  for (let i = 1; i < LIMIT_PER_HOUR; i++) assert.equal(report('u1', { message: 'again', build: 7 }).accepted, true);
  assert.equal(report('u1', { message: 'again', build: 7 }).accepted, false, 'the hourly limit holds');
  assert.equal(report('u2', { message: 'other', build: 7 }).accepted, true, 'callers are limited separately');
  clock += 60 * 60 * 1000;
  assert.equal(report('u1', { message: 'later', build: 7 }).accepted, true, 'the limit resets after an hour');
});

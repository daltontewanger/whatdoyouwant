const { test } = require('node:test');
const assert = require('node:assert/strict');
const { assertLocalEnvironment } = require('./support.cjs');
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

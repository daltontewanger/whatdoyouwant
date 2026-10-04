// Checks the deployable rooms entry without contacting any cloud project.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { createRequire } = require('node:module');
const path = require('node:path');

const entry = path.join(__dirname, '../rooms/index.js');
const load = env => spawnSync(process.execPath, ['-e', `require(${JSON.stringify(entry)})`], {
  env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, ...env }, encoding: 'utf8',
});

test('rooms entry refuses to load for any project other than staging', () => {
  for (const env of [{ GCLOUD_PROJECT: 'what-do-you-want-8a404' }, { GCLOUD_PROJECT: 'demo-whatdoyouwant' }, {},
    { FIREBASE_CONFIG: JSON.stringify({ projectId: 'what-do-you-want-8a404' }) }]) {
    const result = load(env);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /deploys only to whatdoyouwant-staging/);
  }
  assert.equal(load({ GCLOUD_PROJECT: 'whatdoyouwant-staging' }).status, 0);
});

test('every staging callable runs as the scoped identity and requires App Check', async () => {
  process.env.GCLOUD_PROJECT = 'whatdoyouwant-staging';
  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const rooms = require(entry);
  const { CALLABLES } = require('../rooms/handlers.js');
  assert.deepEqual(Object.keys(rooms).sort(), [...CALLABLES, 'cleanUpIdleGuests'].sort());
  const cleanup = rooms.cleanUpIdleGuests.__endpoint;
  assert.equal(cleanup.serviceAccountEmail, 'rooms-runtime@whatdoyouwant-staging.iam.gserviceaccount.com');
  assert.equal(cleanup.scheduleTrigger.schedule, 'every monday 04:00');
  assert.equal(cleanup.maxInstances, 1);
  for (const name of CALLABLES) {
    const endpoint = rooms[name].__endpoint;
    assert.equal(endpoint.serviceAccountEmail, 'rooms-runtime@whatdoyouwant-staging.iam.gserviceaccount.com', name);
    assert.deepEqual(endpoint.region, ['us-central1'], name);
    assert.ok(endpoint.callableTrigger, name);
    assert.equal(endpoint.maxInstances, 5, name);
  }
  const express = createRequire(require.resolve('../rooms/package.json'))('express');
  const app = express();
  app.use(express.json());
  app.post('/', rooms.joinRoom);
  const server = require('node:http').createServer(app);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  // A missing sign-in also yields 401, but from the handler ("Sign in first.").
  // The framework's own App Check refusal happens before the handler runs.
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { joinCode: 'ABCDEF' } }),
    });
    assert.equal(response.status, 401);
    assert.equal((await response.json()).error.message, 'Unauthenticated');
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
});

test('idle guests are removed; registered and recently active accounts are kept', async () => {
  const { createGuestCleanup } = require('../rooms/cleanup.js');
  const day = 24 * 60 * 60 * 1000;
  const now = Date.parse('2026-10-03T00:00:00Z');
  const at = days => new Date(now - days * day).toUTCString();
  const users = [
    { uid: 'old-guest', providerData: [], metadata: { creationTime: at(90), lastRefreshTime: at(45) } },
    { uid: 'fresh-guest', providerData: [], metadata: { creationTime: at(90), lastRefreshTime: at(2) } },
    { uid: 'new-guest', providerData: [], metadata: { creationTime: at(1) } },
    { uid: 'old-email', providerData: [{ providerId: 'password' }], metadata: { lastRefreshTime: at(400) } },
    { uid: 'old-google', providerData: [{ providerId: 'google.com' }], metadata: { lastSignInTime: at(400) } },
    { uid: 'never-refreshed-guest', providerData: [], metadata: { creationTime: at(31) } },
  ];
  const deleted = [];
  const logs = [];
  const auth = {
    // Two pages, to cover pagination.
    listUsers: async (max, token) => token
      ? { users: users.slice(3) }
      : { users: users.slice(0, 3), pageToken: 'next' },
    deleteUsers: async uids => { deleted.push(...uids); return { successCount: uids.length, failureCount: 0 }; },
  };
  const result = await createGuestCleanup({ auth, now: () => now, log: entry => logs.push(entry) })();
  assert.deepEqual(deleted, ['old-guest', 'never-refreshed-guest']);
  assert.deepEqual(result, { scanned: 6, deleted: 2, failed: 0 });
  assert.deepEqual(logs, [{ event: 'idle_guests_removed', scanned: 6, deleted: 2, failed: 0, idleDays: 30 }]);
  assert.ok(!JSON.stringify(logs).includes('guest"'), 'no UIDs are logged');
});


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
  assert.deepEqual(Object.keys(rooms).sort(), [...CALLABLES].sort());
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

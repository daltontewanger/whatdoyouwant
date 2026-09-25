const { test } = require('node:test');
const assert = require('node:assert/strict');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
const base = 'http://127.0.0.1:9099';
async function auth(action, body) {
  const response = await fetch(`${base}/identitytoolkit.googleapis.com/v1/accounts:${action}?key=demo-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(15000),
  });
  return { status: response.status, data: await response.json() };
}
async function code(email, type) {
  const response = await fetch(`${base}/emulator/v1/projects/${PROJECT}/oobCodes`);
  assert.equal(response.status, 200);
  const codes = (await response.json()).oobCodes;
  const match = codes.filter(c => c.email === email && c.requestType === type).at(-1);
  assert.ok(match, 'Expected a local emulator action code');
  return match.oobCode;
}
test('Auth emulator: link preserves UID; verify, reset, restore and delete account', async () => {
  const email = `lifecycle-${Date.now()}@example.test`;
  const guest = await auth('signUp', { returnSecureToken: true });
  assert.equal(guest.status, 200);
  const linked = await auth('update', { idToken: guest.data.idToken, email, password: 'fictional-test-pass-1', returnSecureToken: true });
  assert.equal(linked.status, 200);
  assert.equal(linked.data.localId, guest.data.localId);
  let session = await auth('signInWithPassword', { email, password: 'fictional-test-pass-1', returnSecureToken: true });
  assert.equal(session.status, 200);
  assert.equal((await auth('sendOobCode', { requestType: 'VERIFY_EMAIL', idToken: session.data.idToken })).status, 200);
  assert.equal((await auth('update', { oobCode: await code(email, 'VERIFY_EMAIL') })).status, 200);
  const lookup = await auth('lookup', { idToken: session.data.idToken });
  assert.equal(lookup.data.users[0].emailVerified, true);
  const refresh = await fetch(`${base}/securetoken.googleapis.com/v1/token?key=demo-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: session.data.refreshToken }),
  });
  assert.equal(refresh.status, 200);
  const renewed = await refresh.json();
  const claims = JSON.parse(Buffer.from(renewed.id_token.split('.')[1], 'base64url').toString());
  assert.equal(claims.email_verified, true);
  assert.equal(claims.sub, guest.data.localId);
  assert.equal((await auth('sendOobCode', { requestType: 'PASSWORD_RESET', email })).status, 200);
  assert.equal((await auth('resetPassword', { oobCode: await code(email, 'PASSWORD_RESET'), newPassword: 'fictional-test-pass-2' })).status, 200);
  assert.equal((await auth('signInWithPassword', { email, password: 'fictional-test-pass-1', returnSecureToken: true })).status, 400);
  session = await auth('signInWithPassword', { email, password: 'fictional-test-pass-2', returnSecureToken: true });
  assert.equal(session.status, 200);
  assert.equal(session.data.localId, guest.data.localId);
  assert.equal((await auth('delete', { idToken: session.data.idToken })).status, 200);
  assert.equal((await auth('signInWithPassword', { email, password: 'fictional-test-pass-2', returnSecureToken: true })).status, 400);
});
test('Auth emulator: duplicate email linking cannot take over another identity', async () => {
  const email = `collision-${Date.now()}@example.test`;
  const existing = await auth('signUp', { email, password: 'fictional-test-pass-1', returnSecureToken: true });
  const guest = await auth('signUp', { returnSecureToken: true });
  assert.equal(existing.status, 200); assert.equal(guest.status, 200);
  const conflict = await auth('update', { idToken: guest.data.idToken, email, password: 'fictional-test-pass-2', returnSecureToken: true });
  assert.equal(conflict.status, 400);
  const lookup = await auth('lookup', { idToken: guest.data.idToken });
  assert.equal(lookup.status, 200);
  assert.equal(lookup.data.users[0].localId, guest.data.localId);
  assert.ok(!lookup.data.users[0].email);
  for (const session of [guest, existing]) assert.equal((await auth('delete', { idToken: session.data.idToken })).status, 200);
});

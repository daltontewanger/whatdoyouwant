// Emulator-only server boundary. Never imported by the production Functions source.
const { createRequire } = require('node:module');
const { randomBytes, createHash } = require('node:crypto');
const { PROJECT, assertLocalEnvironment, discover } = require('../support.cjs');
assertLocalEnvironment(process.env);
require('../network-guard.cjs').installHttpGuard();
const fromFunctions = createRequire(require.resolve('../../functions/package.json'));
const { Firestore, Timestamp, FieldValue } = fromFunctions('firebase-admin/firestore');
const { onCall, HttpsError } = fromFunctions('firebase-functions/v2/https');
const { authorize } = require('./authorization.cjs');
const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
const options = { enforceAppCheck: false, cors: [/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/] };
exports.phase1Status = onCall(options, async () => ({ project: PROJECT, policy: 'phase1' }));
const deny = () => { throw new HttpsError('permission-denied', 'Room action unavailable.'); };
function identity(request) {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  return { uid: request.auth.uid, provider: request.auth.token.firebase?.sign_in_provider,
    emailVerified: request.auth.token.email_verified === true };
}
function data(request, key, pattern) {
  const value = request.data;
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).length !== 1 || typeof value[key] !== 'string' || !pattern.test(value[key])) {
    throw new HttpsError('invalid-argument', 'Invalid request.');
  }
  return value[key];
}
const digest = value => createHash('sha256').update(value).digest('hex');
async function limit(uid, action, maximum, period) {
  const bucket = Math.floor(Date.now() / period);
  const ref = db.doc(`_phase1Limits/${digest(`${uid}:${action}:${bucket}`)}`);
  await db.runTransaction(async tx => {
    const previous = await tx.get(ref);
    const count = previous.exists ? previous.data().count : 0;
    if (count >= maximum) throw new HttpsError('resource-exhausted', 'Please wait before trying again.');
    tx.set(ref, { count: count + 1, expiresAt: Timestamp.fromMillis((bucket + 2) * period) });
  });
}
exports.phase1CreateRoom = onCall(options, async request => {
  const actor = identity(request);
  if (!authorize('create', actor)) deny();
  const requestId = data(request, 'requestId', /^[A-Za-z0-9_-]{16,64}$/);
  await limit(actor.uid, 'create', 10, 3600000);
  const receipt = db.doc(`_phase1Requests/${digest(`${actor.uid}:${requestId}`)}`);
  const roomCode = randomBytes(12).toString('hex').toUpperCase();
  return db.runTransaction(async tx => {
    const old = await tx.get(receipt);
    if (old.exists) return { roomCode: old.data().roomCode };
    const room = db.doc(`rooms/${roomCode}`);
    tx.create(room, { creator: actor.uid, status: 'lobby', memberCount: 1,
      createdAt: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(Date.now() + 72 * 3600000) });
    tx.create(room.collection('members').doc(actor.uid), { active: true });
    tx.create(receipt, { roomCode });
    return { roomCode };
  });
});
exports.phase1JoinRoom = onCall(options, async request => {
  const actor = identity(request);
  // Failed attempts also count; missing/closed/revoked rooms use one response.
  await limit(actor.uid, 'join', 10, 60000);
  const roomCode = data(request, 'roomCode', /^[A-F0-9]{24}$/);
  return db.runTransaction(async tx => {
    const room = db.doc(`rooms/${roomCode}`);
    const member = room.collection('members').doc(actor.uid);
    const [snapshot, membership] = await Promise.all([tx.get(room), tx.get(member)]);
    if (!snapshot.exists) deny();
    const state = { ...snapshot.data(), expiresAt: snapshot.data().expiresAt.toMillis() };
    if (state.expiresAt <= Date.now()) deny();
    if (membership.exists) {
      if (membership.data().active !== true) deny();
      return { roomCode }; // Existing member may reconnect after voting starts.
    }
    if (!authorize('join', actor, state) || state.memberCount >= 40) deny();
    tx.create(member, { active: true });
    tx.update(room, { memberCount: state.memberCount + 1 });
    return { roomCode };
  });
});
exports.phase1Search = onCall(options, async request => {
  const actor = identity(request);
  if (!authorize('create', actor)) deny();
  const roomCode = data(request, 'roomCode', /^[A-F0-9]{24}$/);
  await limit(actor.uid, 'search', 10, 60000);
  // Fictional bounded data only. No HERE credentials or HTTP requests.
  const candidates = (await discover()).data.items;
  return db.runTransaction(async tx => {
    const room = db.doc(`rooms/${roomCode}`);
    const [snapshot, membership] = await Promise.all([tx.get(room), tx.get(room.collection('members').doc(actor.uid))]);
    if (!snapshot.exists) deny();
    const state = { ...snapshot.data(), expiresAt: snapshot.data().expiresAt.toMillis() };
    const active = membership.exists && membership.data().active === true;
    if (state.creator !== actor.uid || !active || state.expiresAt <= Date.now()) deny();
    if (state.status === 'voting') return { roomCode, candidateCount: state.candidateCount };
    if (!authorize('search', actor, state, active)) deny();
    for (const candidate of candidates) tx.create(room.collection('candidates').doc(candidate.id), { title: candidate.title });
    tx.update(room, { status: 'voting', candidateCount: candidates.length, startedAt: FieldValue.serverTimestamp() });
    return { roomCode, candidateCount: candidates.length };
  });
});

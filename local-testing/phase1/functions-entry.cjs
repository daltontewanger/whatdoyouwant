// Emulator-only wiring of the room callables in rooms/handlers.js. Never deployed:
// it disables App Check and talks to the loopback emulators.
const { createRequire } = require('node:module');
const { PROJECT, assertLocalEnvironment } = require('../support.cjs');
assertLocalEnvironment(process.env);
require('../network-guard.cjs').installHttpGuard();
const fromFunctions = createRequire(require.resolve('../../functions/package.json'));
const { Firestore, Timestamp, FieldValue } = fromFunctions('firebase-admin/firestore');
const { initializeApp } = fromFunctions('firebase-admin/app');
const { getAuth } = fromFunctions('firebase-admin/auth');
const { onCall, HttpsError } = fromFunctions('firebase-functions/v2/https');
const { createRoomHandlers, CALLABLES } = require('../../rooms/handlers.js');

const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
// FIREBASE_AUTH_EMULATOR_HOST routes Admin Auth to the emulator without credentials.
const auth = getAuth(initializeApp({ projectId: PROJECT }, 'rooms-local'));
const handlers = createRoomHandlers({
  db, FieldValue, Timestamp, HttpsError,
  deleteAuthUser: async uid => {
    await auth.revokeRefreshTokens(uid);
    await auth.deleteUser(uid);
  },
});
// Live search fails closed without its config; the emulators start with a
// generous one so the app can be tried straight away.
db.doc('config/liveSearch').create({ enabled: true, weeklyCaps: { free: 20 }, monthlyCallStop: 3500 })
  .catch(() => {});
const options = { enforceAppCheck: false, cors: [/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/] };

exports.roomsStatus = onCall(options, async () => ({ project: PROJECT, policy: 'rooms' }));
for (const name of CALLABLES) exports[name] = onCall(options, handlers[name]);

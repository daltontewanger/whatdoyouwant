// Only the generated emulator codebase loads this entry. Production never imports it.
const { createRequire } = require('node:module');
const fromFunctions = createRequire(require.resolve('../functions/package.json'));
const { PROJECT, discover } = require('./support.cjs');
if (process.env.GCLOUD_PROJECT !== PROJECT) {
  throw new Error('The local Functions entry requires demo-whatdoyouwant.');
}
require('./network-guard.cjs').installHttpGuard();
// Explicit addresses prevent cloud database access. No Admin app or secrets are needed.
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.GCE_METADATA_HOST = '127.0.0.1:9';
const { Firestore, FieldValue } = fromFunctions('firebase-admin/firestore');
const { onCall } = fromFunctions('firebase-functions/v2/https');
const { createSearchHandler } = require('../functions/search');
const db = new Firestore({ projectId: PROJECT, host: '127.0.0.1:8080', ssl: false });
exports.fetchNearbyRestaurants = onCall({
  enforceAppCheck: false,
  cors: [/^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/],
}, createSearchHandler({
  db,
  serverTimestamp: () => FieldValue.serverTimestamp(),
  discover,
}));

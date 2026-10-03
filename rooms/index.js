// Deployed room callables. This codebase targets staging only; loading it for any
// other project fails, so CLI discovery stops before anything reaches production.
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const logger = require('firebase-functions/logger');
const { createRoomHandlers, CALLABLES } = require('./handlers');
const { createGuestCleanup } = require('./cleanup');

const STAGING = 'whatdoyouwant-staging';
const project = process.env.GCLOUD_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId;
if (project !== STAGING) {
  throw new Error(`The rooms codebase deploys only to ${STAGING}; refusing to load for ${project || 'an unknown project'}.`);
}

initializeApp();
const auth = getAuth();
const handlers = createRoomHandlers({
  db: getFirestore(), FieldValue, Timestamp, HttpsError,
  deleteAuthUser: async uid => {
    await auth.revokeRefreshTokens(uid);
    await auth.deleteUser(uid);
  },
  log: entry => logger.info(entry),
});

const options = {
  region: 'us-central1',
  // Least-privilege runtime identity instead of the project's default compute account.
  serviceAccount: `rooms-runtime@${STAGING}.iam.gserviceaccount.com`,
  enforceAppCheck: true,
  cors: ['https://whatdoyouwant-staging.web.app', 'https://whatdoyouwant-staging.firebaseapp.com',
    /^http:\/\/localhost:\d+$/],
  maxInstances: 5,
  timeoutSeconds: 30,
};

for (const name of CALLABLES) exports[name] = onCall(options, handlers[name]);

// Daily removal of idle guest accounts. The schedule needs no App Check or CORS;
// it runs as the same scoped identity, which can manage Auth users.
exports.cleanUpIdleGuests = onSchedule({
  schedule: 'every day 04:00',
  timeZone: 'Etc/UTC',
  region: options.region,
  serviceAccount: options.serviceAccount,
  maxInstances: 1,
  timeoutSeconds: 540,
  retryCount: 0,
}, createGuestCleanup({ auth, log: entry => logger.info(entry) }));

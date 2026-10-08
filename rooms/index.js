// Deployed room callables. This codebase targets staging only; loading it for any
// other project fails, so CLI discovery stops before anything reaches production.
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue, Timestamp } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onMessagePublished } = require('firebase-functions/v2/pubsub');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const { createRoomHandlers, CALLABLES } = require('./handlers');
const { createGuestCleanup } = require('./cleanup');
const { createBudgetGuard } = require('./budget');
const { createHereProvider, createHereTransport } = require('./search/here-provider');

const STAGING = 'whatdoyouwant-staging';
const project = process.env.GCLOUD_PROJECT || JSON.parse(process.env.FIREBASE_CONFIG || '{}').projectId;
if (project !== STAGING) {
  throw new Error(`The rooms codebase deploys only to ${STAGING}; refusing to load for ${project || 'an unknown project'}.`);
}

initializeApp();
const auth = getAuth();
const db = getFirestore();

// Live search runs on HERE behind the weekly cap, the monthly stop and the
// config/liveSearch switch. The key comes from Secret Manager and is read only
// when a search runs, so loading or deploying this file never touches it.
const hereKey = defineSecret('HERE_API_KEY');
let hereTransport;
const provider = createHereProvider({
  transport: call => (hereTransport ??= createHereTransport({ apiKey: hereKey.value() }))(call),
});
// Only these callables can search, so only they can read the key.
const SEARCHING = ['startRoom', 'createQuickPick'];
const handlers = createRoomHandlers({
  db, FieldValue, Timestamp, HttpsError, provider,
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

for (const name of CALLABLES) {
  exports[name] = onCall(SEARCHING.includes(name) ? { ...options, secrets: [hereKey] } : options, handlers[name]);
}

// Weekly removal of idle guest accounts; staging gains few guests, so weekly is
// plenty. No App Check or CORS: it runs as the scoped identity, which can manage
// Auth users.
exports.cleanUpIdleGuests = onSchedule({
  schedule: 'every monday 04:00',
  timeZone: 'Etc/UTC',
  region: options.region,
  serviceAccount: options.serviceAccount,
  maxInstances: 1,
  timeoutSeconds: 540,
  retryCount: 0,
}, createGuestCleanup({ auth, log: entry => logger.info(entry) }));

// Closes rooms whose voting time ran out unattended and removes decks soon
// after they are no longer needed.
exports.sweepRooms = onSchedule({
  schedule: 'every 15 minutes',
  timeZone: 'Etc/UTC',
  region: options.region,
  serviceAccount: options.serviceAccount,
  maxInstances: 1,
  timeoutSeconds: 120,
  retryCount: 0,
}, () => handlers.sweep());

// The project's billing budget publishes to this topic; reaching the pause
// point switches live search off until someone turns it back on.
const guardBudget = createBudgetGuard({ db, FieldValue, log: entry => logger.info(entry) });
exports.pauseLiveSearchOnBudget = onMessagePublished({
  topic: 'live-search-budget',
  region: options.region,
  serviceAccount: options.serviceAccount,
  maxInstances: 1,
  timeoutSeconds: 60,
  retry: false,
}, event => guardBudget(event.data.message.json));

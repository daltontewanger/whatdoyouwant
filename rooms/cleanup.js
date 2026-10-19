// Removes guest (anonymous) Auth users nobody has used for a while, and email
// accounts whose address was never verified. Neither can host, so their room
// data expires within a day of each room and they own nothing by the time they
// are removed; only the Auth record would otherwise accumulate. That also keeps
// sign-ups with made-up addresses from piling up.
const IDLE_DAYS = 30;
const PAGE = 1000;
// Bounds one run so a large backlog is worked through over several runs.
const MAX_PER_RUN = 10000;

function lastActive(user) {
  const { lastRefreshTime, lastSignInTime, creationTime } = user.metadata ?? {};
  return Date.parse(lastRefreshTime || lastSignInTime || creationTime) || 0;
}

// A guest has no linked sign-in provider; linking email or Google adds one.
const isGuest = user => (user.providerData ?? []).length === 0;

// Signed up with email and password only, and never clicked the link. Google
// accounts arrive verified, so any other provider means a real account.
const isUnverifiedEmail = user => {
  const providers = (user.providerData ?? []).map(info => info.providerId);
  return providers.length > 0 && providers.every(id => id === 'password') && user.emailVerified !== true;
};

function createGuestCleanup({ auth, now = () => Date.now(), log = () => {}, idleDays = IDLE_DAYS }) {
  return async function cleanUpIdleGuests() {
    const cutoff = now() - idleDays * 24 * 60 * 60 * 1000;
    let scanned = 0;
    let deleted = 0;
    let unverified = 0;
    let failed = 0;
    let pageToken;
    do {
      const page = await auth.listUsers(PAGE, pageToken);
      pageToken = page.pageToken;
      scanned += page.users.length;
      const idle = page.users
        .filter(user => (isGuest(user) || isUnverifiedEmail(user)) && lastActive(user) < cutoff)
        .slice(0, MAX_PER_RUN - deleted);
      unverified += idle.filter(isUnverifiedEmail).length;
      if (idle.length) {
        const result = await auth.deleteUsers(idle.map(user => user.uid));
        deleted += result.successCount;
        failed += result.failureCount;
      }
    } while (pageToken && deleted < MAX_PER_RUN);
    // Counts only: no UIDs or other identifiers in the record.
    log({ event: 'idle_guests_removed', scanned, deleted, unverified, failed, idleDays });
    return { scanned, deleted, unverified, failed };
  };
}

module.exports = { createGuestCleanup, IDLE_DAYS };

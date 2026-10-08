// Cloud Billing budget notifications arrive on a Pub/Sub topic several times a
// day. Once spend reaches the pause point, live search is switched off; only a
// person turns it back on. Notifications below the pause point change nothing.
const DEFAULT_PAUSE_AT = 1;

function createBudgetGuard({ db, FieldValue, log = () => {} }) {
  const configRef = db.doc('config/liveSearch');

  return async function onBudgetNotification(notification) {
    const cost = Number(notification?.costAmount);
    const budget = Number(notification?.budgetAmount);
    if (!Number.isFinite(cost) || !Number.isFinite(budget) || budget <= 0) {
      log({ event: 'budget_notification_ignored', reason: 'unreadable' });
      return { paused: false };
    }
    return db.runTransaction(async tx => {
      const config = await tx.get(configRef);
      const pauseAt = Number(config.data()?.budgetPauseAt);
      const share = Number.isFinite(pauseAt) && pauseAt > 0 ? pauseAt : DEFAULT_PAUSE_AT;
      if (cost < budget * share) return { paused: false };
      if (config.exists && config.data().enabled === false) return { paused: true };
      // set with merge, so a missing config still ends up paused rather than failing.
      tx.set(configRef, { enabled: false, pausedReason: 'budget', pausedAt: FieldValue.serverTimestamp() },
        { merge: true });
      log({ event: 'live_search_paused', reason: 'budget', share });
      return { paused: true };
    });
  };
}

module.exports = { createBudgetGuard, DEFAULT_PAUSE_AT };

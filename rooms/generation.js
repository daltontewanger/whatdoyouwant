// The one path every live deck takes, for a Group Room or a Quick Pick: reserve
// the person's weekly search and the provider budget, search outside any
// transaction, then commit the deck and settle. Anything that ends without a
// committed deck refunds the search; provider calls that happened always count.
const { randomBytes, createHash } = require('node:crypto');
const { buildDeck } = require('./search/deck');
const { deckDocument } = require('./decks');
const { weekOf, monthOf, liveSearchConfig, weeklyCapFor, DAY_MS, WEEK_MS } = require('./quota');

// Longer than the callable timeout, so a lease only expires once its call is gone.
const LEASE_MS = 90 * 1000;
const RECONCILE_BATCH = 200;

const digest = value => createHash('sha256').update(value).digest('hex');

/**
 * A target is the room or Quick Pick a deck is for:
 *   check(tx)  reads only; returns { done: view } when the target already has a
 *              deck, { ready: context } when one may be made, or throws to refuse.
 *   commit(tx, deck, built, context)  writes the target and returns
 *              { view, expiresAt } (the deck's expiry).
 */
function createGeneration({ db, FieldValue, Timestamp, HttpsError, provider, now, newSeed, log,
  retryTransient }) {
  const configRef = db.doc('config/liveSearch');
  const leaseRef = (mode, targetId) => db.doc(`deckGenerations/${mode}_${targetId}`);
  const weekRef = (uid, week) => db.doc(`usageWeeks/${uid}_${week.key}`);
  // Each provider has its own ledger, so the fake provider never spends HERE's budget.
  const monthRef = month => db.doc(`usageMonths/${provider.id}_${month}`);
  const paused = () => new HttpsError('unavailable', 'Live search is paused.', { reason: 'live-search-paused' });
  const owns = (snapshot, reservation) => snapshot.exists && snapshot.data().status === 'executing' &&
    snapshot.data().token === reservation.token;

  async function reserve({ uid, mode, targetId, target }) {
    const lease = leaseRef(mode, targetId);
    const token = randomBytes(8).toString('hex');
    return db.runTransaction(async tx => {
      const at = now();
      const week = weekOf(at);
      const month = monthOf(at);
      const [checked, config, usage, ledger, entitlement, running] = await Promise.all([
        target.check(tx), tx.get(configRef), tx.get(weekRef(uid, week)), tx.get(monthRef(month)),
        tx.get(db.doc(`entitlements/${uid}`)), tx.get(lease)]);
      // A target that already has its deck costs nothing, paused or not.
      if (checked.done) return { done: checked.done };
      if (running.exists && running.data().status === 'executing' && running.data().leaseExpiresAt.toMillis() > at) {
        throw new HttpsError('aborted', 'Already starting.', { reason: 'in-progress' });
      }
      const settings = liveSearchConfig(config.exists ? config.data() : null);
      if (!settings.enabled) {
        log({ event: 'live_search_paused', reason: settings.pausedReason });
        throw paused();
      }
      const cap = weeklyCapFor(settings, entitlement.data()?.entitlement ?? 'free');
      const taken = (usage.data()?.used ?? 0) + (usage.data()?.reserved ?? 0);
      if (taken >= cap) {
        log({ event: 'weekly_cap_reached', cap });
        throw new HttpsError('resource-exhausted', 'No live searches left this week.',
          { reason: 'weekly-cap', resetsAt: new Date(week.resetsAt).toISOString() });
      }
      const calls = provider.maxCallsPerSearch;
      const spent = (ledger.data()?.callsReserved ?? 0) + (ledger.data()?.callsCompleted ?? 0);
      if (spent + calls > settings.monthlyCallStop) {
        log({ event: 'live_search_paused', reason: 'monthly-stop', provider: provider.id });
        throw paused();
      }
      const updatedAt = FieldValue.serverTimestamp();
      tx.set(weekRef(uid, week), { uidHash: digest(uid), weekStartsAt: Timestamp.fromMillis(week.startsAt),
        resetsAt: Timestamp.fromMillis(week.resetsAt), used: FieldValue.increment(0),
        reserved: FieldValue.increment(1), updatedAt, expiresAt: Timestamp.fromMillis(week.resetsAt + WEEK_MS) }, { merge: true });
      tx.set(monthRef(month), { provider: provider.id, month, callsReserved: FieldValue.increment(calls), updatedAt },
        { merge: true });
      tx.set(lease, { token, status: 'executing', uidHash: digest(uid), mode, targetId,
        weekPath: weekRef(uid, week).path, monthPath: monthRef(month).path, provider: provider.id,
        callsReserved: calls, leaseExpiresAt: Timestamp.fromMillis(at + LEASE_MS),
        createdAt: updatedAt, expiresAt: Timestamp.fromMillis(at + DAY_MS) });
      return { reservation: { token, lease, week: weekRef(uid, week), month: monthRef(month), calls } };
    });
  }

  // Moves a reservation to its outcome. Runs after the transaction's reads.
  function settleInto(tx, reservation, { charged, calls, status, deckId = null }) {
    const updatedAt = FieldValue.serverTimestamp();
    tx.update(reservation.week, { reserved: FieldValue.increment(-1),
      ...(charged ? { used: FieldValue.increment(1) } : {}), updatedAt });
    tx.update(reservation.month, { callsReserved: FieldValue.increment(-reservation.calls),
      callsCompleted: FieldValue.increment(calls),
      ...(charged ? { generationsCompleted: FieldValue.increment(1) } : {}), updatedAt });
    tx.update(reservation.lease, { status, callsCompleted: calls, deckId, settledAt: updatedAt });
  }

  async function refund(reservation, calls, status) {
    await retryTransient(() => db.runTransaction(async tx => {
      // Already settled by the sweep after the lease expired: nothing left to give back.
      if (!owns(await tx.get(reservation.lease), reservation)) return;
      settleInto(tx, reservation, { charged: false, calls, status });
    }));
  }

  async function generateDeck({ uid, mode, targetId, search, target }) {
    // Wall-clock stage timings for the log; the injected clock is for limits.
    const began = Date.now();
    const reserved = await reserve({ uid, mode, targetId, target });
    if (reserved.done) return reserved.done;
    const { reservation } = reserved;
    const reservedAt = Date.now();

    let result;
    try {
      result = await provider.searchNearby(search);
    } catch (error) {
      // When a provider cannot say how many calls went out, assume the worst case.
      const calls = Number.isInteger(error?.providerCalls) ? error.providerCalls : reservation.calls;
      await refund(reservation, calls, 'failed');
      log({ event: 'search_failed', provider: provider.id, providerCalls: calls });
      throw new HttpsError('unavailable', 'Restaurant search is unavailable.');
    }
    const calls = result.providerCalls;
    const searchedAt = Date.now();
    const seed = newSeed();
    const built = buildDeck(result.restaurants, search, { seed });
    // Nothing is stored or charged for a pool too thin to use; the person is
    // asked to widen the search instead.
    if (!built.pool.sufficient) {
      await refund(reservation, calls, 'too-few-results');
      throw new HttpsError('failed-precondition', 'Too few restaurants match.',
        { reason: 'too-few-results', eligible: built.pool.eligible, minimum: built.pool.minimum });
    }

    const deck = db.doc(`restaurantDecks/${randomBytes(12).toString('hex')}`);
    let outcome;
    try {
      outcome = await db.runTransaction(async tx => {
        const [lease, checked] = await Promise.all([tx.get(reservation.lease), target.check(tx)]);
        if (!owns(lease, reservation)) return { lost: true, done: checked.done ?? null };
        if (checked.done) {
          settleInto(tx, reservation, { charged: false, calls, status: 'superseded' });
          return { done: checked.done };
        }
        const { view, expiresAt } = target.commit(tx, deck, built, checked.ready);
        tx.create(deck, deckDocument({ ownerUid: uid, targetType: mode, targetId, provider, result, request: search,
          built, seed, expiresAt, generatedAt: FieldValue.serverTimestamp() }));
        settleInto(tx, reservation, { charged: true, calls, status: 'completed', deckId: deck.id });
        return { view };
      });
    } catch (error) {
      await refund(reservation, calls, 'failed');
      throw error;
    }
    // Counts only: no UID, location or restaurant names.
    log({ event: 'deck_created', mode, provider: provider.id, providerCalls: calls, eligible: built.pool.eligible,
      selected: built.pool.selected, kept: Boolean(outcome.view), reserveMs: reservedAt - began,
      providerMs: searchedAt - reservedAt, commitMs: Date.now() - searchedAt });
    if (outcome.view) return outcome.view;
    if (outcome.done) return outcome.done;
    throw new HttpsError('unavailable', 'Please try again.');
  }

  // Leases whose call never settled (a crash or timeout). The provider outcome
  // is unknown, so the reserved calls count as used and the search is refunded.
  async function reconcile() {
    const stale = await db.collection('deckGenerations').where('status', '==', 'executing')
      .where('leaseExpiresAt', '<=', Timestamp.fromMillis(now())).limit(RECONCILE_BATCH).get();
    let settled = 0;
    for (const snapshot of stale.docs) {
      settled += await retryTransient(() => db.runTransaction(async tx => {
        const current = await tx.get(snapshot.ref);
        const lease = current.data();
        if (lease?.status !== 'executing' || lease.leaseExpiresAt.toMillis() > now()) return 0;
        settleInto(tx, { lease: snapshot.ref, week: db.doc(lease.weekPath), month: db.doc(lease.monthPath),
          calls: lease.callsReserved }, { charged: false, calls: lease.callsReserved, status: 'expired' });
        return 1;
      }));
    }
    return settled;
  }

  // What the app shows: searches left this week, when they reset, and whether
  // live search is paused. Read-only.
  async function allowance(uid) {
    const at = now();
    const week = weekOf(at);
    const [config, usage, entitlement, ledger] = await Promise.all([configRef.get(), weekRef(uid, week).get(),
      db.doc(`entitlements/${uid}`).get(), monthRef(monthOf(at)).get()]);
    const settings = liveSearchConfig(config.exists ? config.data() : null);
    const cap = weeklyCapFor(settings, entitlement.data()?.entitlement ?? 'free');
    const used = (usage.data()?.used ?? 0) + (usage.data()?.reserved ?? 0);
    const spent = (ledger.data()?.callsReserved ?? 0) + (ledger.data()?.callsCompleted ?? 0);
    return {
      weeklyCap: cap,
      used: Math.min(used, cap),
      remaining: Math.max(0, cap - used),
      resetsAt: new Date(week.resetsAt).toISOString(),
      paused: !settings.enabled || spent + provider.maxCallsPerSearch > settings.monthlyCallStop,
    };
  }

  return { generateDeck, reconcile, allowance, digest };
}

module.exports = { createGeneration, LEASE_MS };

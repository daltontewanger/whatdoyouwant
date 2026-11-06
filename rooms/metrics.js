// Aggregate usage counts for the owner's insights page. Every value is a
// plain daily total: no user, room, place or location is ever part of a
// counter's name or value, so nothing here can be traced back to a person.
const { CUISINE_IDS } = require('./search/cuisines');

// Each day's totals are spread over a few documents so a busy evening never
// queues writes on one document; the report adds them back together.
const SHARDS = 4;
const NAME = /^[a-z][A-Za-z0-9_]{0,63}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const DAY_MS = 24 * 3600000;
const MAX_REPORT_DAYS = 400;

// What the app may count on its own: taps the server never sees. Fixed names
// only, never free text.
const CLIENT_EVENTS = [
  'resultMap', 'resultDirections', 'resultWebsite', 'resultPhone', 'resultShare',
  'ownResultMap', 'ownResultDirections',
  'introFinished', 'introSkipped',
  'demoStarted', 'demoFinished', 'signUpAfterDemo',
  'quickPickChosen', 'joinWithCode', 'joinWithLink', 'shareRoomCode',
  'openedFromSite',
];

const PLATFORMS = ['web', 'android', 'ios'];

// Local favorites: a place's wins in the last three calendar months. Shown
// only past both bars, so no badge can point at one group's choice.
const HOT_PICK_MONTHS = 3;
const HOT_PICK_WINS = 5;
const HOT_PICK_VOTERS = 15;
const PLACE_STATS_MS = 120 * DAY_MS;

const dayOf = at => new Date(at).toISOString().slice(0, 10);
const monthOf = at => new Date(at).toISOString().slice(0, 7);

function bucket(value, edges) {
  for (const [limit, name] of edges) if (value <= limit) return name;
  return edges.at(-1)[1];
}

// Drops anything that is not a whole positive count under a known-safe name.
function cleanCounts(counts) {
  const clean = {};
  for (const [name, value] of Object.entries(counts ?? {})) {
    if (NAME.test(name) && Number.isInteger(value) && value > 0) clean[name] = (clean[name] ?? 0) + value;
  }
  return clean;
}

// What one finished live search says about how people search. Settings only,
// never the place searched from.
function searchCounts({ mode, search, pool, candidates, providerCalls, providerMs, at }) {
  const radius = `radius_${String(search.radius.value).replace('.', '_')}${search.radius.unit}`;
  const included = search.includedCuisineIds ?? [];
  const small = pool.eligible < search.deckSize;
  return {
    [mode === 'room' ? 'searchesRoom' : 'searchesQuickPick']: 1,
    providerCalls,
    candidatesShown: candidates,
    poolEligible: pool.eligible,
    [radius]: 1,
    [`deckSize_${search.deckSize}`]: 1,
    ...(search.openNowPreferred ? { openNowOn: 1 } : {}),
    [`cuisinesIncluded_${bucket(included.length, [[0, 'none'], [1, 'one'], [3, 'twoToThree'], [Infinity, 'fourPlus']])}`]: 1,
    ...((search.excludedCuisineIds ?? []).length ? { cuisinesExcludedUsed: 1 } : {}),
    ...Object.fromEntries(included.filter(id => CUISINE_IDS.includes(id)).map(id => [`cuisinePicked_${id}`, 1])),
    ...(small ? { smallPools: 1, [`smallPool_${radius}`]: 1, ...(search.openNowPreferred ? { smallPool_openNow: 1 } : {}),
      ...(included.length ? { smallPool_withCuisines: 1 } : {}) } : {}),
    [`providerTime_${bucket(providerMs, [[1000, 'under1s'], [3000, 'oneTo3s'], [Infinity, 'over3s']])}`]: 1,
    [`hourUtc_${new Date(at).getUTCHours()}`]: 1,
  };
}

// A search that found too little to make a deck, by the settings that made it thin.
function tooFewCounts(search) {
  const radius = `radius_${String(search.radius.value).replace('.', '_')}${search.radius.unit}`;
  return { searchesTooFew: 1, [`tooFew_${radius}`]: 1,
    ...(search.openNowPreferred ? { tooFew_openNow: 1 } : {}),
    ...((search.includedCuisineIds ?? []).length ? { tooFew_withCuisines: 1 } : {}) };
}

// How a room ended. `stats` comes from the tally; `startedAt` and `at` are millis.
function roomCounts({ outcome, stats, startedAt, at, winner }) {
  if (!outcome) return { roomsClosedUnstarted: 1 };
  const { voters, likes } = outcome.results;
  const winnerLikes = outcome.results.winner ? likes[outcome.results.winner] ?? 0 : 0;
  const result = voters === 0 ? 'roomsNoVotes' : winnerLikes === 0 ? 'roomsNoMatch'
    : winnerLikes === voters ? 'roomsUnanimous' : 'roomsMajority';
  const minutes = startedAt ? (at - startedAt) / 60000 : null;
  const cuisine = winner?.cuisineIds?.find(id => CUISINE_IDS.includes(id));
  return {
    roomsCompleted: 1,
    [result]: 1,
    [`roomVoters_${bucket(voters, [[1, 'one'], [2, 'two'], [4, 'threeToFour'], [Infinity, 'fivePlus']])}`]: 1,
    ...(minutes === null ? {} : { [`decided_${bucket(minutes, [[2, 'under2m'], [5, 'twoTo5m'], [10, 'fiveTo10m'], [Infinity, 'over10m']])}`]: 1 }),
    ballotsCast: stats.ballots,
    ballotsLiked: stats.liked,
    ballotsTimedOut: stats.timedOut,
    ...(cuisine && voters > 0 && winnerLikes > 0 ? { [`winnerCuisine_${cuisine}`]: 1 } : {}),
    ...(winner?.userEntered ? { ownListRoomsCompleted: 1 } : {}),
  };
}

// The once-a-day activity record for one session, and the counts it adds.
// `previous` is the stored record or null; returns null when today is
// already counted.
function activity({ previous, registered, platform, build, at }) {
  const today = dayOf(at);
  if (previous?.lastDay === today && (previous.registered === true || !registered)) return null;
  const type = registered ? 'Account' : 'Guest';
  const today_ = {};
  const cohorts = {};
  const record = {
    firstDay: previous?.firstDay ?? today,
    lastDay: today,
    registered: registered || previous?.registered === true,
    accountDay: previous?.accountDay ?? (registered ? today : null),
    returned: { ...(previous?.returned ?? {}) },
  };
  if (previous?.lastDay !== today) {
    today_[`active${type}s`] = 1;
    if (PLATFORMS.includes(platform)) today_[`activeOn_${platform}`] = 1;
    if (Number.isInteger(build)) today_[`activeBuild_${build}`] = 1;
  }
  if (!previous) today_[registered ? 'newAccounts' : 'newGuests'] = 1;
  else if (registered && previous.registered !== true) today_.guestsUpgraded = 1;
  // Returning: counted on the first day's totals, so each cohort reads as a share.
  const credit = (from, prefix) => {
    if (!from || from === today) return;
    const days = Math.round((Date.parse(today) - Date.parse(from)) / DAY_MS);
    for (const [key, low, high] of [['d1', 1, 1], ['d7', 7, 13], ['d30', 30, 59]]) {
      const flag = `${prefix}${key}`;
      if (days >= low && days <= high && !record.returned[flag]) {
        record.returned[flag] = true;
        (cohorts[from] ??= {})[`${prefix ? 'accountReturned' : 'returned'}_${key}`] = 1;
      }
    }
  };
  credit(record.firstDay, '');
  credit(record.accountDay, 'a');
  // Guests left idle are removed weekly, so their record need not outlast that.
  record.expiresAt = at + (record.registered ? 400 : 60) * DAY_MS;
  return { record, today: today_, cohorts };
}

// Whether a place's recent wins make it a local favorite.
function isHotPick(stats, at) {
  if (!stats) return false;
  const months = new Set();
  const date = new Date(at);
  for (let back = 0; back < HOT_PICK_MONTHS; back++) {
    months.add(new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() - back, 1)).toISOString().slice(0, 7));
  }
  const sum = field => Object.entries(stats[field] ?? {}).filter(([month]) => months.has(month))
    .reduce((total, [, value]) => total + (Number.isInteger(value) ? value : 0), 0);
  return sum('wins') >= HOT_PICK_WINS && sum('voters') >= HOT_PICK_VOTERS;
}

function createMetrics({ db, FieldValue, Timestamp, now, logError = () => {}, random = Math.random }) {
  const shardRef = (day, shard) => db.doc(`metrics/${day}-${shard}`);

  // Best effort: a counting problem is logged and never fails the action.
  // `byDay` maps a day to its counts; most calls add only to today.
  async function addByDay(byDay) {
    const writes = Object.entries(byDay).map(([day, counts]) => [day, cleanCounts(counts)])
      .filter(([day, counts]) => DAY.test(day) && Object.keys(counts).length);
    if (!writes.length) return;
    try {
      const batch = db.batch();
      for (const [day, counts] of writes) {
        batch.set(shardRef(day, Math.floor(random() * SHARDS)), { day,
          counts: Object.fromEntries(Object.entries(counts).map(([name, value]) => [name, FieldValue.increment(value)])) },
        { merge: true });
      }
      await batch.commit();
    } catch (error) {
      logError({ event: 'metrics_failed', code: error?.code ?? null });
    }
  }

  const add = counts => addByDay({ [dayOf(now())]: counts });

  // The day's activity record for this session, read and written in one go.
  async function recordActivity({ uid, registered, platform, build }) {
    const ref = db.doc(`userActivity/${uid}`);
    let counted = null;
    try {
      counted = await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        const previous = snapshot.exists ? snapshot.data() : null;
        const next = activity({ previous, registered, platform, build, at: now() });
        if (!next) return null;
        tx.set(ref, { ...next.record, expiresAt: Timestamp.fromMillis(next.record.expiresAt) });
        return next;
      });
    } catch (error) {
      logError({ event: 'metrics_failed', code: error?.code ?? null });
      return;
    }
    if (counted) await addByDay({ ...counted.cohorts, [dayOf(now())]: counted.today });
  }

  // A room's winning live place, for local favorites. Only a real group
  // agreeing counts: two or more people liked it.
  async function recordWin({ cardId, voters, likes }) {
    if (!/^c[a-f0-9]{20}$/.test(cardId ?? '') || voters < 2 || likes < 2) return;
    const at = now();
    const month = monthOf(at);
    try {
      await db.doc(`placeStats/${cardId}`).set({
        wins: { [month]: FieldValue.increment(1) },
        voters: { [month]: FieldValue.increment(voters) },
        expiresAt: Timestamp.fromMillis(at + PLACE_STATS_MS),
      }, { merge: true });
    } catch (error) {
      logError({ event: 'metrics_failed', code: error?.code ?? null });
    }
  }

  // Which of these card IDs are local favorites right now.
  async function hotPicks(cardIds) {
    const ids = [...new Set(cardIds.filter(id => /^c[a-f0-9]{20}$/.test(id)))];
    if (!ids.length) return new Set();
    const at = now();
    const stats = await db.getAll(...ids.map(id => db.doc(`placeStats/${id}`)));
    return new Set(stats.filter(doc => doc.exists && isHotPick(doc.data(), at)).map(doc => doc.id));
  }

  // Totals per day between two dates, inclusive.
  async function report(from, to) {
    const start = Date.parse(from);
    const end = Date.parse(to);
    const days = [];
    for (let at = start; at <= end; at += DAY_MS) days.push(dayOf(at));
    const snapshots = days.length
      ? await db.getAll(...days.flatMap(day => Array.from({ length: SHARDS }, (_, shard) => shardRef(day, shard))))
      : [];
    const totals = {};
    for (const snapshot of snapshots) {
      if (!snapshot.exists) continue;
      const { day, counts } = snapshot.data();
      const into = (totals[day] ??= {});
      for (const [name, value] of Object.entries(counts ?? {})) {
        if (Number.isFinite(value)) into[name] = (into[name] ?? 0) + value;
      }
    }
    return totals;
  }

  return { add, addByDay, recordActivity, recordWin, hotPicks, report };
}

// A report range: two ISO dates, oldest first, at most MAX_REPORT_DAYS apart.
function parseRange(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
    Object.keys(value).sort().join() !== 'from,to' || !DAY.test(value.from) || !DAY.test(value.to)) return null;
  const from = Date.parse(value.from);
  const to = Date.parse(value.to);
  if (!Number.isFinite(from) || !Number.isFinite(to) || dayOf(from) !== value.from || dayOf(to) !== value.to ||
    from > to || (to - from) / DAY_MS >= MAX_REPORT_DAYS) return null;
  return { from: value.from, to: value.to };
}

module.exports = { createMetrics, cleanCounts, searchCounts, tooFewCounts, roomCounts, activity, isHotPick,
  parseRange, bucket, dayOf, monthOf, CLIENT_EVENTS, PLATFORMS, SHARDS, MAX_REPORT_DAYS,
  HOT_PICK_WINS, HOT_PICK_VOTERS };

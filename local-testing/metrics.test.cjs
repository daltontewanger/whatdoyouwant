const test = require('node:test');
const assert = require('node:assert/strict');
const { cleanCounts, searchCounts, tooFewCounts, roomCounts, activity, isHotPick, parseRange, CLIENT_EVENTS,
  HOT_PICK_WINS, HOT_PICK_VOTERS } = require('../rooms/metrics');

const DAY = 24 * 3600000;
const at = Date.parse('2026-11-06T18:30:00Z');
const SEARCH = { radius: { value: 1.5, unit: 'mi' }, radiusMeters: 2414, includedCuisineIds: ['thai', 'pizza'],
  excludedCuisineIds: [], openNowPreferred: true, deckSize: 10, origin: { lat: 38.5, lng: -98.5 } };

test('counts: only whole positive numbers under plain names survive', () => {
  assert.deepEqual(cleanCounts({ roomsCreated: 1, 'a.b': 1, bad: -1, half: 0.5, zero: 0, 'tap_resultMap': 2,
    __proto__x: 1, Upper: 1 }), { roomsCreated: 1, tap_resultMap: 2 });
});

test('a finished search counts its settings and never where it searched from', () => {
  const counts = searchCounts({ mode: 'room', search: SEARCH, pool: { eligible: 7 }, candidates: 7,
    providerCalls: 1, providerMs: 1400, at });
  assert.deepEqual(counts, {
    searchesRoom: 1, providerCalls: 1, candidatesShown: 7, poolEligible: 7, radius_1_5mi: 1, deckSize_10: 1,
    openNowOn: 1, cuisinesIncluded_twoToThree: 1, cuisinePicked_thai: 1, cuisinePicked_pizza: 1,
    smallPools: 1, smallPool_radius_1_5mi: 1, smallPool_openNow: 1, smallPool_withCuisines: 1,
    providerTime_oneTo3s: 1, hourUtc_18: 1,
  });
  const text = JSON.stringify(counts);
  assert.ok(!text.includes('38.5') && !text.includes('98.5') && !text.includes('2414'));
  const plain = searchCounts({ mode: 'quickPick', search: { ...SEARCH, includedCuisineIds: [], openNowPreferred: false,
    excludedCuisineIds: ['thai'] }, pool: { eligible: 30 }, candidates: 10, providerCalls: 2, providerMs: 300, at });
  assert.equal(plain.searchesQuickPick, 1);
  assert.equal(plain.cuisinesIncluded_none, 1);
  assert.equal(plain.cuisinesExcludedUsed, 1);
  assert.equal(plain.smallPools, undefined);
  assert.equal(plain.providerTime_under1s, 1);
  assert.deepEqual(tooFewCounts(SEARCH), { searchesTooFew: 1, tooFew_radius_1_5mi: 1, tooFew_openNow: 1,
    tooFew_withCuisines: 1 });
});

test('a room close counts how it ended, its size, speed and ballots', () => {
  const outcome = (likes, voters, winner = 'c1') => ({ results: { likes, voters, winner } });
  const stats = { ballots: 12, liked: 7, timedOut: 2 };
  const base = { stats, startedAt: at - 4 * 60000, at, winner: { id: 'c1', cuisineIds: ['thai'] } };
  assert.deepEqual(roomCounts({ ...base, outcome: outcome({ c1: 3, c2: 1 }, 3) }), {
    roomsCompleted: 1, roomsUnanimous: 1, roomVoters_threeToFour: 1, decided_twoTo5m: 1, ballotsCast: 12,
    ballotsLiked: 7, ballotsTimedOut: 2, winnerCuisine_thai: 1 });
  assert.equal(roomCounts({ ...base, outcome: outcome({ c1: 2 }, 5) }).roomsMajority, 1);
  const none = roomCounts({ ...base, outcome: outcome({ c1: 0 }, 2) });
  assert.equal(none.roomsNoMatch, 1);
  assert.equal(none.winnerCuisine_thai, undefined, 'nobody liked it, so it says nothing about taste');
  assert.equal(roomCounts({ ...base, outcome: outcome({}, 0, null) }).roomsNoVotes, 1);
  assert.deepEqual(roomCounts({ outcome: null }), { roomsClosedUnstarted: 1 });
});

test('activity: once a day, with new, upgraded and returning sessions', () => {
  const first = activity({ previous: null, registered: false, platform: 'web', build: 42, at });
  assert.deepEqual(first.today, { activeGuests: 1, activeOn_web: 1, activeBuild_42: 1, newGuests: 1 });
  assert.equal(first.record.firstDay, '2026-11-06');
  assert.equal(first.record.accountDay, null);
  assert.equal(activity({ previous: first.record, registered: false, at: at + 3600000 }), null, 'same day');

  // The guest signs up the same day: counted as an upgrade, not as active twice.
  const upgraded = activity({ previous: first.record, registered: true, platform: 'web', build: 42, at: at + 7200000 });
  assert.deepEqual(upgraded.today, { guestsUpgraded: 1 });
  assert.equal(upgraded.record.accountDay, '2026-11-06');

  // Back the next day: both the first-day and account-day cohorts get a day-1 return.
  const next = activity({ previous: upgraded.record, registered: true, platform: 'android', at: at + DAY });
  assert.deepEqual(next.today, { activeAccounts: 1, activeOn_android: 1 });
  assert.deepEqual(next.cohorts, { '2026-11-06': { returned_d1: 1, accountReturned_d1: 1 } });

  // Day 9 falls in the day-7 window; a second visit in it counts nothing more.
  const week = activity({ previous: next.record, registered: true, at: at + 9 * DAY });
  assert.deepEqual(week.cohorts, { '2026-11-06': { returned_d7: 1, accountReturned_d7: 1 } });
  const again = activity({ previous: week.record, registered: true, at: at + 10 * DAY });
  assert.deepEqual(again.cohorts, {});
  const month = activity({ previous: again.record, registered: true, at: at + 45 * DAY });
  assert.deepEqual(month.cohorts, { '2026-11-06': { returned_d30: 1, accountReturned_d30: 1 } });
  assert.equal(month.record.expiresAt, at + 45 * DAY + 400 * DAY);
  assert.equal(first.record.expiresAt, at + 30 * DAY, 'guests go sooner');
  const text = JSON.stringify(month);
  assert.ok(!/uid|email|room/i.test(text));
});

test('local favorites need enough wins and enough people within three months', () => {
  const stats = { wins: { '2026-11': 3, '2026-09': 2, '2026-07': 9 }, voters: { '2026-11': 10, '2026-10': 0, '2026-09': 6 } };
  assert.equal(isHotPick(stats, at), true);
  assert.equal(isHotPick({ ...stats, wins: { '2026-11': HOT_PICK_WINS - 1, '2026-07': 9 } }, at), false,
    'old wins do not count');
  assert.equal(isHotPick({ ...stats, voters: { '2026-11': HOT_PICK_VOTERS - 1 } }, at), false,
    'a few people winning it often is not enough');
  assert.equal(isHotPick(null, at), false);
});

test('report ranges are plain dates, oldest first, under 400 days', () => {
  assert.deepEqual(parseRange({ from: '2026-10-01', to: '2026-11-06' }), { from: '2026-10-01', to: '2026-11-06' });
  for (const bad of [null, [], {}, { from: '2026-11-06' }, { from: '2026-11-07', to: '2026-11-06' },
    { from: '2026-02-30', to: '2026-03-01' }, { from: '2025-01-01', to: '2026-11-06' },
    { from: '2026-11-01', to: '2026-11-06', extra: 1 }, { from: 20261101, to: '2026-11-06' }]) {
    assert.equal(parseRange(bad), null, JSON.stringify(bad));
  }
});

test('app taps are a fixed list of plain names', () => {
  for (const name of CLIENT_EVENTS) assert.match(name, /^[a-z][A-Za-z]{1,39}$/);
  assert.equal(new Set(CLIENT_EVENTS).size, CLIENT_EVENTS.length);
});

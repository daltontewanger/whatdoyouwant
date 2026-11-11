// Input checks and config parsing for the room callables: pure functions, no emulators.
const test = require('node:test');
const assert = require('node:assert/strict');

const { parseOwnList, InvalidList, MAX_SPOTS } = require('../rooms/own-list');

test('own list: text is tidied and empty optional fields are left out', () => {
  assert.deepEqual(parseOwnList({ spots: [{ id: 'a-1', name: ' Pho\n Real ', address: '', note: ' get\tthe #4 ' }] }),
    [{ id: 'a-1', name: 'Pho Real', note: 'get the #4' }]);
});

test('own list: shape, size and lengths are enforced', () => {
  for (const bad of [null, [], { spots: 'x' }, { spots: [], extra: 1 }, { spots: [null] },
    { spots: [{ id: 'a', name: 5 }] }, { spots: [{ id: 'a', name: 'Ok', address: 7 }] },
    { spots: Array.from({ length: MAX_SPOTS + 1 }, (_, i) => ({ id: `s${i}`, name: 'x' })) }]) {
    assert.throws(() => parseOwnList(bad), InvalidList, JSON.stringify(bad)?.slice(0, 40));
  }
  assert.equal(parseOwnList({ spots: [{ id: 'a', name: 'x'.repeat(80), address: 'y'.repeat(120) }] }).length, 1);
});

const { parseNickname, InvalidNickname, BlockedNickname } = require('../rooms/nickname');

test('nickname: ordinary names in any language are kept, tidied', () => {
  for (const [raw, kept] of [['Dalton', 'Dalton'], ['  Winner   Dinner ', 'Winner Dinner'], ['Rando1122', 'Rando1122'],
    ['J.R.', 'J.R.'], ["O'Brien", "O'Brien"], ['Mary-Kate_2', 'Mary-Kate_2'], ['Zoë', 'Zoë'],
    ['José María', 'José María'], ['Nguyễn', 'Nguyễn'], ['李小龙', '李小龙'],
    ['Ｆｕｌｌ', 'Full'], ['Dickens', 'Dickens'], ['Hancock', 'Hancock'], ['Cassie', 'Cassie'],
    ['Glass', 'Glass'], ['Blue Tit', 'Blue Tit'], ['Sussex Sexton', 'Sussex Sexton'], ['Analise', 'Analise'], ['Swanky', 'Swanky'], ['Nigel', 'Nigel'], ['Fukuoka', 'Fukuoka']]) {
    assert.equal(parseNickname(raw), kept, raw);
  }
  assert.equal(parseNickname('tab\tand\nline'), 'tab and line', 'breaks become plain spaces');
  assert.equal(parseNickname('   '), '', 'empty clears the nickname');
});

test('nickname: nothing that could carry a link, markup or hidden text', () => {
  for (const bad of ['<b>hi</b>', '<script>', 'evil.com', 'x.co', 'https://x', 'a@b', 'tom&jerry', '"quote"', 'back`tick',
    '{name}', 'semi;colon', 'slash/name', 'back\\slash', 'a‮b', 'zero​width', 'nul\u0000l',
    'á̀̂b', '\u{1F4A9}\u{1F4A9}', '...', '--', 'a', 'x'.repeat(21), 5, null, undefined, 'x'.repeat(201)]) {
    assert.throws(() => parseNickname(bad), InvalidNickname, JSON.stringify(bad));
  }
  assert.equal(parseNickname('y'.repeat(20)).length, 20);
});

test('nickname: common profanity and slurs are turned down, disguised or not', () => {
  for (const bad of ['fuck', 'FUUUCK', 'f.u.c.k', 'f u c k', 'sh1t', 'Bull Shit', '\u{1D41F}\u{1D42E}\u{1D41C}\u{1D424}',
    'n1gg3r', 'ass', 'a s s', 'asses', 'Big Dick', 'Dick', 'www', 'bitch4u', 'Nazi', 'Host', 'GUEST', 'admin', 'You']) {
    assert.throws(() => parseNickname(bad), BlockedNickname, bad);
  }
});

const { parseReport, reportable, activeFlags, InvalidReport } = require('../rooms/place-reports');

const CARD = `c${'0'.repeat(20)}`;
const ROOM = 'A'.repeat(24);
const PICK = 'a'.repeat(24);

test('reports: a card, a kind, and the room or pick it was shown in', () => {
  assert.deepEqual(parseReport({ cardId: CARD, kind: 'closed', roomId: ROOM }),
    { cardId: CARD, kind: 'closed', from: 'room', targetId: ROOM });
  assert.deepEqual(parseReport({ cardId: CARD, kind: 'location', quickPickId: PICK }),
    { cardId: CARD, kind: 'location', from: 'quickPick', targetId: PICK });
  for (const bad of [null, [], {}, { cardId: CARD, kind: 'closed' }, { cardId: CARD, kind: 'closed', roomId: PICK },
    { cardId: CARD, kind: 'closed', quickPickId: ROOM }, { cardId: CARD, kind: 'toString', roomId: ROOM },
    { cardId: 'ChIJprovider', kind: 'closed', roomId: ROOM }, { cardId: CARD, kind: 'closed', roomId: ROOM, uid: 'x' },
    { cardId: CARD, kind: 'closed', roomId: ROOM, quickPickId: PICK }]) {
    assert.throws(() => parseReport(bad), InvalidReport, JSON.stringify(bad));
  }
});

test('reports: only searched places, and wrong buttons only when the card had them', () => {
  const card = { id: CARD, name: 'Demo Taco', website: 'https://example.test', phone: null };
  assert.equal(reportable(card, 'closed'), true);
  assert.equal(reportable(card, 'website'), true);
  assert.equal(reportable(card, 'phone'), false);
  assert.equal(reportable({ ...card, userEntered: true }, 'closed'), false, 'a typed spot');
  assert.equal(reportable({ ...card, id: 'own-1' }, 'closed'), false);
  assert.equal(reportable(null, 'closed'), false);
});

test('reports: only hiding that has not run out applies', () => {
  const at = millis => ({ toMillis: () => millis });
  assert.deepEqual(activeFlags({ closedUntil: at(2000), websiteUntil: at(500) }, 1000),
    { closed: true, website: false, phone: false });
  assert.deepEqual(activeFlags(undefined, 1000), { closed: false, website: false, phone: false });
});

const { parsePlaces, parseRoomLists, detailsExpireAt, withoutStaleDetails, InvalidPlaces, MAX_PLACES,
  DETAILS_MS } = require('../rooms/place-lists');

const NOW = Date.parse('2026-10-30T12:00:00Z');
const id = n => `c${String(n).padStart(20, '0')}`;
const lists = (fields = {}) => ({ favorites: [], never: [], useFavorites: true, useNever: true, ...fields });

test('places: favorites keep tidied details with when they were seen; never keeps a name', () => {
  assert.deepEqual(parsePlaces(lists({
    favorites: [{ id: id(1), name: ' Demo\n Taco ', address: '19 Example St', seenAt: NOW - 1000 }, { id: id(2) }],
    never: [{ id: id(3), name: 'Demo Fish Shack' }, { id: id(4) }],
    useFavorites: false,
  }), NOW), {
    favorites: [{ id: id(1), name: 'Demo Taco', address: '19 Example St', seenAt: NOW - 1000 }, { id: id(2) }],
    never: [{ id: id(3), name: 'Demo Fish Shack' }, { id: id(4) }],
    useFavorites: false,
    useNever: true,
  });
});

test('places: details older than 30 days are dropped; a clock ahead is clamped', () => {
  const parsed = parsePlaces(lists({ favorites: [
    { id: id(1), name: 'Old', seenAt: NOW - DETAILS_MS },
    { id: id(2), name: 'Ahead', seenAt: NOW + 60000 },
  ] }), NOW);
  assert.deepEqual(parsed.favorites, [{ id: id(1) }, { id: id(2), name: 'Ahead', seenAt: NOW }]);
  assert.equal(detailsExpireAt(parsed.favorites), NOW + DETAILS_MS);
  assert.equal(detailsExpireAt([{ id: id(1) }]), null);
  assert.deepEqual(withoutStaleDetails(parsed.favorites, NOW + DETAILS_MS), [{ id: id(1) }, { id: id(2) }]);
});

test('places: shape, IDs, sizes and lengths are enforced', () => {
  const many = Array.from({ length: MAX_PLACES + 1 }, (_, n) => ({ id: id(n) }));
  for (const bad of [null, [], {}, lists({ extra: 1 }), lists({ useNever: 'yes' }),
    lists({ favorites: [{ id: 'ChIJ-provider-id' }] }), lists({ favorites: [{ id: id(1), name: 'No date' }] }),
    lists({ favorites: [{ id: id(1), name: 'Far ahead', seenAt: NOW + 3600000 }] }),
    lists({ favorites: [{ id: id(1), name: 'x'.repeat(121), seenAt: NOW }] }),
    lists({ favorites: [{ id: id(1), note: 'not a field' }] }),
    lists({ favorites: [{ id: id(1) }], never: [{ id: id(1) }] }),
    lists({ never: [{ id: id(1) }, { id: id(1) }] }), lists({ never: [{ id: id(1), address: 'x' }] }),
    lists({ favorites: many })]) {
    assert.throws(() => parsePlaces(bad, NOW), InvalidPlaces, JSON.stringify(bad)?.slice(0, 60));
  }
});

test('places: closed places keep a name, are optional, and sit on one list only', () => {
  assert.equal(parsePlaces(lists(), NOW).closed, undefined, 'an older app sends none');
  assert.deepEqual(parsePlaces(lists({ closed: [{ id: id(1), name: ' Gone ' }, { id: id(2) }] }), NOW).closed,
    [{ id: id(1), name: 'Gone' }, { id: id(2) }]);
  for (const bad of [lists({ closed: [{ id: id(1) }], never: [{ id: id(1) }] }), lists({ closed: [{ id: 'x' }] }),
    lists({ closed: [{ id: id(1), seenAt: NOW }] }), lists({ closed: {} })]) {
    assert.throws(() => parsePlaces(bad, NOW), InvalidPlaces, JSON.stringify(bad).slice(0, 60));
  }
});

test('room lists: card IDs only, no repeats, bounded', () => {
  assert.deepEqual(parseRoomLists({ roomId: 'R', favorites: [id(1)], never: [id(2), id(3)] }),
    { roomId: 'R', favorites: [id(1)], never: [id(2), id(3)], closed: [] });
  assert.deepEqual(parseRoomLists({ roomId: 'R', favorites: [], never: [], closed: [id(4)] }).closed, [id(4)]);
  for (const bad of [{ roomId: 'R', favorites: [] }, { roomId: 'R', favorites: [id(1), id(1)], never: [] },
    { roomId: 'R', favorites: ['Demo Taco'], never: [] }, { roomId: 'R', favorites: [], never: [], uid: 'x' },
    { roomId: 'R', favorites: Array.from({ length: MAX_PLACES + 1 }, (_, n) => id(n)), never: [] }]) {
    assert.throws(() => parseRoomLists(bad), InvalidPlaces, JSON.stringify(bad).slice(0, 60));
  }
});

const { weekOf, monthOf, liveSearchConfig, deckFeatures, weeklyCapFor } = require('../rooms/quota.js');

test('weeks start Monday 00:00 UTC whatever the local day', () => {
  const sunday = weekOf(Date.parse('2026-10-11T23:59:59Z'));
  assert.equal(sunday.key, '2026-10-05');
  assert.equal(new Date(sunday.resetsAt).toISOString(), '2026-10-12T00:00:00.000Z');
  assert.equal(weekOf(Date.parse('2026-10-12T00:00:00Z')).key, '2026-10-12');
  assert.equal(weekOf(Date.parse('2027-01-01T12:00:00Z')).key, '2026-12-28', 'weeks cross the year');
  assert.equal(monthOf(Date.parse('2026-10-31T23:59:59Z')), '2026-10');
  assert.equal(monthOf(Date.parse('2026-11-01T00:00:00Z')), '2026-11');
});

test('live search is paused unless the config is complete and switched on', () => {
  const good = { enabled: true, weeklyCaps: { free: 20, plus: 50 }, monthlyCallStop: 3500 };
  assert.deepEqual(liveSearchConfig(good), { enabled: true, pausedReason: null,
    weeklyCaps: { free: 20, plus: 50 }, monthlyCallStop: 3500 });
  assert.equal(liveSearchConfig(null).pausedReason, 'not-configured');
  assert.equal(liveSearchConfig({ ...good, enabled: 'true' }).enabled, false, 'only a real true switches it on');
  assert.equal(liveSearchConfig({ ...good, enabled: false, pausedReason: 'budget' }).pausedReason, 'budget');
  for (const broken of [{ ...good, monthlyCallStop: -1 }, { ...good, monthlyCallStop: 1.5 },
    { ...good, weeklyCaps: { plus: 50 } }, { ...good, weeklyCaps: { free: '20' } }]) {
    assert.deepEqual([liveSearchConfig(broken).enabled, liveSearchConfig(broken).pausedReason], [false, 'misconfigured']);
  }
});

test('an unknown entitlement falls back to the free cap', () => {
  const config = liveSearchConfig({ enabled: true, weeklyCaps: { free: 20, plus: 50, odd: 'x' }, monthlyCallStop: 1 });
  assert.equal(weeklyCapFor(config, 'plus'), 50);
  assert.equal(weeklyCapFor(config, 'odd'), 20);
  assert.equal(weeklyCapFor(config, 'missing'), 20);
});

test('features: notice cards, photos and local favorites stay off unless set exactly right', () => {
  const on = { enabled: true, every: 4, title: 'A word from us', text: 'Thanks for deciding with us.' };
  assert.deepEqual(deckFeatures(null), { notices: null, photos: false, hotPicks: false });
  assert.deepEqual(deckFeatures({ deckNotices: on, photos: { enabled: true } }),
    { notices: { every: 4, title: 'A word from us', text: 'Thanks for deciding with us.' }, photos: true,
      hotPicks: false });
  for (const bad of [{ ...on, enabled: 'true' }, { ...on, every: 2 }, { ...on, every: 11 }, { ...on, every: 4.5 },
    { ...on, title: '' }, { ...on, text: 'x'.repeat(201) }, { ...on, title: 7 }]) {
    assert.equal(deckFeatures({ deckNotices: bad }).notices, null, JSON.stringify(bad));
  }
  assert.equal(deckFeatures({ photos: true }).photos, false);
  assert.equal(deckFeatures({ hotPicks: true }).hotPicks, false);
  assert.equal(deckFeatures({ hotPicks: { enabled: true } }).hotPicks, true);
});

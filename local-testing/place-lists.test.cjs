const test = require('node:test');
const assert = require('node:assert/strict');
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

test('room lists: card IDs only, no repeats, bounded', () => {
  assert.deepEqual(parseRoomLists({ roomId: 'R', favorites: [id(1)], never: [id(2), id(3)] }),
    { roomId: 'R', favorites: [id(1)], never: [id(2), id(3)] });
  for (const bad of [{ roomId: 'R', favorites: [] }, { roomId: 'R', favorites: [id(1), id(1)], never: [] },
    { roomId: 'R', favorites: ['Demo Taco'], never: [] }, { roomId: 'R', favorites: [], never: [], uid: 'x' },
    { roomId: 'R', favorites: Array.from({ length: MAX_PLACES + 1 }, (_, n) => id(n)), never: [] }]) {
    assert.throws(() => parseRoomLists(bad), InvalidPlaces, JSON.stringify(bad).slice(0, 60));
  }
});

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

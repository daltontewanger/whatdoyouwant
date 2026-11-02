const test = require('node:test');
const assert = require('node:assert/strict');
const { parseNickname, InvalidNickname, BlockedNickname } = require('../rooms/nickname');

test('nickname: ordinary names in any language are kept, tidied', () => {
  for (const [raw, kept] of [['Dalton', 'Dalton'], ['  Winner   Dinner ', 'Winner Dinner'], ['Rando1122', 'Rando1122'],
    ['J.R.', 'J.R.'], ["O'Brien", "O'Brien"], ['Mary-Kate_2', 'Mary-Kate_2'], ['Zoë', 'Zoë'],
    ['José María', 'José María'], ['Nguyễn', 'Nguyễn'], ['李小龙', '李小龙'],
    ['Ｆｕｌｌ', 'Full'], ['Dickens', 'Dickens'], ['Hancock', 'Hancock'], ['Cassie', 'Cassie'],
    ['Glass', 'Glass'], ['Swanky', 'Swanky'], ['Nigel', 'Nigel'], ['Fukuoka', 'Fukuoka']]) {
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

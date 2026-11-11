const test = require('node:test');
const assert = require('node:assert/strict');
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

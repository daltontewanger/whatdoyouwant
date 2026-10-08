const { test } = require('node:test');
const assert = require('node:assert/strict');
const { weekOf, monthOf, liveSearchConfig, weeklyCapFor } = require('../rooms/quota.js');

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
  const good = { enabled: true, weeklyCaps: { free: 20, plus: 50 }, monthlyCallStop: 27000 };
  assert.deepEqual(liveSearchConfig(good), { enabled: true, pausedReason: null,
    weeklyCaps: { free: 20, plus: 50 }, monthlyCallStop: 27000 });
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

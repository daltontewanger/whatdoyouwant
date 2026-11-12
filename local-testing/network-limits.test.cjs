// Per-network limits and the new-account allowance, without Firebase.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { clientNetwork, networkOf, createNetworkWindow } = require('../rooms/ip-limits.js');
const { newAccountRule, allowanceFor, weekOf } = require('../rooms/quota.js');

test('the network is the last forwarded address, which a caller cannot forge', () => {
  const request = header => ({ headers: { 'x-forwarded-for': header }, ip: '10.0.0.1' });
  assert.deepEqual(clientNetwork(request('203.0.113.9')), { network: '203.0.113.9', entries: 1 });
  // Whatever the caller sends lands in front of the address Cloud Run appends.
  assert.equal(clientNetwork(request('1.2.3.4, 198.51.100.2, 203.0.113.9')).network, '203.0.113.9');
  assert.equal(clientNetwork(request(' 1.2.3.4 ,203.0.113.9 ')).network, '203.0.113.9');
  assert.equal(clientNetwork({ headers: {}, ip: '::ffff:198.51.100.7' }).network, '198.51.100.7');
  assert.deepEqual(clientNetwork(undefined), { network: null, entries: 0 });
  assert.equal(clientNetwork(request('not-an-address')).network, null);
});

test('IPv6 counts by its /64 and IPv4 by the address', () => {
  assert.equal(networkOf('2001:db8:abcd:12:1:2:3:4'), '2001:db8:abcd:12::/64');
  assert.equal(networkOf('2001:db8:abcd:12::99'), '2001:db8:abcd:12::/64');
  assert.equal(networkOf('2001:0DB8::1'), '2001:db8:0:0::/64');
  assert.equal(networkOf('[2001:db8:1:2::5]:443'), '2001:db8:1:2::/64');
  assert.equal(networkOf('::1'), '0:0:0:0::/64');
  assert.equal(networkOf('64:ff9b::192.0.2.33'), '64:ff9b:0:0::/64');
  assert.equal(networkOf('198.51.100.7:5123'), '198.51.100.7');
  assert.equal(networkOf('999.1.1.1'), null);
  assert.equal(networkOf(42), null);
});

test('the in-memory window allows a set number of calls per network each minute', () => {
  let clock = Date.parse('2026-11-11T12:00:10Z');
  const take = createNetworkWindow({ now: () => clock, perMinute: 3, maxTracked: 2 });
  assert.deepEqual([take('a'), take('a'), take('a'), take('a')], [true, true, true, false]);
  assert.equal(take('b'), true, 'networks count separately');
  // Past the tracking limit a new network is let through rather than remembered.
  assert.equal(take('c'), true);
  assert.equal(take('c'), true);
  clock += 60000;
  assert.equal(take('a'), true, 'a new minute starts over');
});

test('new accounts get 3 searches in their first 48 hours unless the config says otherwise', () => {
  assert.deepEqual(newAccountRule(undefined), { searches: 3, windowMs: 48 * 3600000 });
  assert.deepEqual(newAccountRule({ newAccounts: { searches: 5, hours: 24 } }), { searches: 5, windowMs: 24 * 3600000 });
  assert.deepEqual(newAccountRule({ newAccounts: { searches: -1, hours: 9999 } }), { searches: 3, windowMs: 48 * 3600000 });
  assert.equal(newAccountRule({ newAccounts: { enabled: false } }), null);

  const at = Date.parse('2026-11-11T12:00:00Z'); // a Wednesday
  const week = weekOf(at);
  const config = { weeklyCaps: { free: 10 } };
  const allowance = (createdAt, data = {}) => allowanceFor({ config, data, entitlement: 'free', createdAt, at, week });
  const fresh = allowance(at - 3600000);
  assert.deepEqual(fresh, { cap: 3, reason: 'new-account-cap', resetsAt: at - 3600000 + 48 * 3600000, newAccount: true });
  assert.deepEqual(allowance(at - 49 * 3600000), { cap: 10, reason: 'weekly-cap', resetsAt: week.resetsAt, newAccount: false });
  assert.equal(allowance(null).cap, 10, 'an unknown age gets the normal allowance');
  assert.equal(allowance(at - 3600000, { newAccounts: { enabled: false } }).cap, 10);
  // Late in the week, more searches arrive at the weekly reset if that comes first.
  const sunday = Date.parse('2026-11-15T23:00:00Z');
  const late = allowanceFor({ config, data: {}, entitlement: 'free', createdAt: sunday - 3600000, at: sunday, week: weekOf(sunday) });
  assert.equal(late.resetsAt, weekOf(sunday).resetsAt);
  // A weekly cap already below the new-account one is never raised.
  assert.equal(allowanceFor({ config: { weeklyCaps: { free: 2 } }, data: {}, entitlement: 'free',
    createdAt: at, at, week }).cap, 2);
});

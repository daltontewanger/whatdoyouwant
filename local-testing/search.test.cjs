// Restaurant search layer: request contract, cuisine mapping, deck pipeline,
// fake provider and the HERE adapter against synthetic fixtures. No network.
const { test } = require('node:test');
const assert = require('node:assert/strict');
require('./network-guard.cjs').installHttpGuard();
const { parseSearchRequest, filterSummary, InvalidSearchRequest } = require('../rooms/search/request');
const { CUISINES, CUISINE_IDS, cuisinesFromHere, dietaryHintsFromHere } = require('../rooms/search/cuisines');
const { buildDeck, distanceMeters, candidateId } = require('../rooms/search/deck');
const { createFakeProvider } = require('../rooms/search/fake-provider');
const { assertProvider, normalizedRestaurant, ProviderUnavailable } = require('../rooms/search/provider');
const { createHereProvider, createHereTransport, normalizeHereItem, ENDPOINTS } = require('../rooms/search/here-provider');

const ORIGIN = { lat: 38.5, lng: -98.5 };
const KM5 = { value: 5, unit: 'km' };
const request = (fields = {}) => parseSearchRequest({ origin: ORIGIN, radius: KM5, ...fields });
const fixture = name => require(`./search/here-fixtures/${name}.json`);

// Plays a fixture's responses back in order for matching endpoints and keeps a
// log of what the adapter asked for.
function replay(name) {
  const queue = [...fixture(name).responses];
  const calls = [];
  const transport = async ({ endpoint, params }) => {
    const kind = Object.keys(ENDPOINTS).find(key => ENDPOINTS[key] === endpoint);
    calls.push({ kind, params });
    const index = queue.findIndex(response => response.endpoint === kind);
    if (index === -1) throw new Error(`No ${kind} response left in ${name}.`);
    const [response] = queue.splice(index, 1);
    return { status: response.status, body: response.body };
  };
  return { transport, calls };
}

async function fakeDeck(fields = {}, seed = 'seed-1') {
  const parsed = request(fields);
  const { restaurants } = await createFakeProvider().searchNearby(parsed);
  return buildDeck(restaurants, parsed, { seed });
}

test('request contract: accepts the documented shape and fills defaults', () => {
  assert.deepEqual(request(), { origin: ORIGIN, radius: KM5, radiusMeters: 5000, includedCuisineIds: [],
    excludedCuisineIds: [], openNowPreferred: false, deckSize: 15 });
  assert.equal(request({ radius: { value: 15, unit: 'mi' } }).radiusMeters, 24140);
  assert.equal(request({ radius: { value: 1, unit: 'mi' } }).radiusMeters, 1609);
  const full = request({ includedCuisineIds: ['thai', 'pizza'], excludedCuisineIds: ['fast_food'],
    openNowPreferred: true, deckSize: 25 });
  assert.deepEqual(full.includedCuisineIds, ['pizza', 'thai'], 'sorted so retries compare equal');
  assert.equal(filterSummary(full).origin, undefined, 'the stored summary never carries the origin');
});

test('request contract: rejects anything outside the whitelist instead of trimming it', () => {
  const bad = [
    null, [], {}, { origin: ORIGIN }, { radius: KM5 },
    { origin: ORIGIN, radiusMeters: 5000 },
    { origin: ORIGIN, radius: KM5, radiusMeters: 99999 },
    { origin: ORIGIN, radius: KM5, query: 'sushi' },
    { origin: ORIGIN, radius: KM5, uid: 'someone-else' },
    { origin: { lat: 91, lng: 0 }, radius: KM5 },
    { origin: { lat: 0, lng: -181 }, radius: KM5 },
    { origin: { lat: '38.5', lng: -98.5 }, radius: KM5 },
    { origin: { lat: NaN, lng: 0 }, radius: KM5 },
    { origin: { ...ORIGIN, accuracy: 5 }, radius: KM5 },
    { origin: ORIGIN, radius: { value: 4, unit: 'mi' } },
    { origin: ORIGIN, radius: { value: 5, unit: 'm' } },
    { origin: ORIGIN, radius: { value: '5', unit: 'mi' } },
    { origin: ORIGIN, radius: { value: 5, unit: 'mi', meters: 99999 } },
    { origin: ORIGIN, radius: 5 },
    { origin: ORIGIN, radius: KM5, includedCuisineIds: ['101-000'] },
    { origin: ORIGIN, radius: KM5, includedCuisineIds: ['thai', 'thai'] },
    { origin: ORIGIN, radius: KM5, includedCuisineIds: CUISINE_IDS.slice(0, 9) },
    { origin: ORIGIN, radius: KM5, includedCuisineIds: 'thai' },
    { origin: ORIGIN, radius: KM5, includedCuisineIds: ['thai'], excludedCuisineIds: ['thai'] },
    { origin: ORIGIN, radius: KM5, openNowPreferred: 'yes' },
    { origin: ORIGIN, radius: KM5, deckSize: 20 },
  ];
  for (const data of bad) assert.throws(() => parseSearchRequest(data), InvalidSearchRequest, JSON.stringify(data));
});

test('cuisines: HERE food types, families and categories map to whitelisted IDs only', () => {
  assert.deepEqual(cuisinesFromHere(['201-010']), ['chinese']);
  assert.deepEqual(cuisinesFromHere(['101-003']), ['american', 'bbq']);
  assert.deepEqual(cuisinesFromHere(['203-026', '203-010']), ['japanese', 'seafood']);
  assert.deepEqual(cuisinesFromHere([], ['100-1000-0005']), ['mexican']);
  assert.deepEqual(cuisinesFromHere(['800-067'], ['100-1000-0009']), ['burgers', 'fast_food']);
  assert.deepEqual(cuisinesFromHere(['800-066', '800-085']), [], 'unmapped types are unknown, not a cuisine');
  assert.deepEqual(cuisinesFromHere([]), []);
  assert.deepEqual(dietaryHintsFromHere(['800-077', '202-000', '800-076']), ['vegan', 'vegetarian']);
  for (const [id, cuisine] of Object.entries(CUISINES)) {
    assert.match(id, /^[a-z_]+$/);
    assert.ok(cuisine.label && (cuisine.foodTypes || cuisine.families || cuisine.categories), id);
  }
});

test('fake provider meets the contract and places one restaurant outside the circle', async () => {
  const provider = assertProvider(createFakeProvider({ simulatedCalls: 2 }));
  const result = await provider.searchNearby(request());
  assert.equal(result.providerCalls, 2);
  assert.ok(result.restaurants.every(r => r.provider === 'fake' && r.name.startsWith('Demo ')));
  const outside = result.restaurants.filter(r => distanceMeters(ORIGIN, { lat: r.latitude, lng: r.longitude }) > 5000);
  assert.deepEqual(outside.map(r => r.name), ['Demo Faraway Grill']);
});

test('deck: the same records, request and seed always give the same deck', async () => {
  const first = await fakeDeck();
  const again = await fakeDeck();
  assert.deepEqual(again, first);
  const parsed = request();
  const { restaurants } = await createFakeProvider().searchNearby(parsed);
  const shuffled = buildDeck([...restaurants].reverse(), parsed, { seed: 'seed-1' });
  assert.deepEqual(shuffled.candidates.map(c => c.id), first.candidates.map(c => c.id), 'input order does not matter');
  assert.deepEqual(first.candidates.map(c => c.order), first.candidates.map((_, index) => index));
  assert.throws(() => buildDeck(restaurants, parsed, {}), /stored seed/);
});

test('deck: the seed only decides exact ties', () => {
  const parsed = request();
  const twin = (id, bearing) => normalizedRestaurant({ provider: 'fake', providerPlaceId: id, name: `Tie ${id}`,
    address: `${id} Example Street`, latitude: ORIGIN.lat + 0.01 * Math.cos(bearing), longitude: ORIGIN.lng,
    cuisineIds: ['thai'] });
  // Same distance north and south of the origin: identical scores.
  const records = [twin('a', 0), twin('b', Math.PI)];
  const orders = new Set();
  for (let seed = 0; seed < 20; seed++) {
    orders.add(buildDeck(records, parsed, { seed: `s${seed}` }).candidates.map(c => c.name).join());
  }
  assert.equal(orders.size, 2);
  const closer = normalizedRestaurant({ ...twin('c', 0), latitude: ORIGIN.lat + 0.001 });
  for (let seed = 0; seed < 5; seed++) {
    assert.equal(buildDeck([...records, closer], parsed, { seed: `s${seed}` }).candidates[0].name, 'Tie c');
  }
});

test('deck: distance comes from the origin; out-of-radius and positively excluded places are removed', async () => {
  const { candidates, pool } = await fakeDeck({ excludedCuisineIds: ['mexican'], deckSize: 25 });
  assert.ok(candidates.every(c => c.distanceMetersFromOrigin <= 5000 && Number.isInteger(c.distanceMetersFromOrigin)));
  assert.ok(!candidates.some(c => c.name === 'Demo Faraway Grill'));
  assert.ok(!candidates.some(c => c.cuisineIds.includes('mexican')));
  assert.ok(candidates.some(c => c.cuisineIds.length === 0), 'unknown cuisine stays under exclusions (flexible)');
  assert.deepEqual(pool, { received: 26, invalid: 0, outOfRadius: 1, excluded: 2, duplicates: 0, eligible: 23,
    selected: 23, minimum: 8, sufficient: true });
  assert.equal((await fakeDeck({ deckSize: 5 })).pool.minimum, 5, 'a short deck needs only its own size');
});

test('deck: included cuisines lead, unknown cuisines next, other cuisines last', async () => {
  const { candidates } = await fakeDeck({ includedCuisineIds: ['chinese', 'thai'], deckSize: 25 });
  const tier = c => c.cuisineIds.some(id => ['chinese', 'thai'].includes(id)) ? 0 : c.cuisineIds.length ? 2 : 1;
  const tiers = candidates.map(tier);
  assert.deepEqual(tiers, [...tiers].sort(), tiers.join());
  assert.deepEqual(tiers.slice(0, 3), [0, 0, 0]);
});

test('deck: open-now preference ranks closed places last without removing them', async () => {
  const parsed = request({ deckSize: 10, openNowPreferred: true });
  const { restaurants } = await createFakeProvider().searchNearby(parsed);
  const small = restaurants.filter(r => r.openStatus !== 'open' || ['Demo Tacos', 'Demo Pho', 'Demo Deli',
    'Demo Curry', 'Demo Diner', 'Demo Falafel'].includes(r.name));
  const { candidates } = buildDeck(small, parsed, { seed: 'open' });
  assert.equal(candidates.length, 9);
  assert.equal(candidates.at(-1).name, 'Demo Burger Bar', 'closed, but still there when needed');
  assert.deepEqual(candidates.slice(-3, -1).map(c => c.openStatus), ['unknown', 'unknown']);
  const plain = buildDeck(small, request({ deckSize: 10 }), { seed: 'open' }).candidates;
  assert.ok(plain.findIndex(c => c.name === 'Demo Burger Bar') < 8, 'no penalty without the preference');
});

test('deck: one location per chain and a cuisine cap, relaxed only when the pool is short', async () => {
  const { candidates } = await fakeDeck({ deckSize: 10 });
  const chains = candidates.map(c => c.chainId).filter(Boolean);
  assert.equal(new Set(chains).size, chains.length);
  const counts = {};
  for (const c of candidates) if (c.cuisineIds[0]) counts[c.cuisineIds[0]] = (counts[c.cuisineIds[0]] ?? 0) + 1;
  assert.ok(Object.values(counts).every(count => count <= 4), JSON.stringify(counts));

  const parsed = request({ deckSize: 10 });
  const chainOnly = ['1', '2', '3'].map(id => normalizedRestaurant({ provider: 'fake', providerPlaceId: id,
    name: 'Same Chain', address: `${id} Example Street`, latitude: ORIGIN.lat + Number(id) / 100, longitude: ORIGIN.lng,
    chainId: 'chain' }));
  assert.equal(buildDeck(chainOnly, parsed, { seed: 's' }).candidates.length, 3, 'better a repeat than an empty deck');
});

test('deck: duplicates collapse by provider ID, then by name and address or nearby coordinates', () => {
  const parsed = request();
  const base = { provider: 'here', name: 'Café Ficticio', latitude: ORIGIN.lat + 0.01, longitude: ORIGIN.lng };
  const records = [
    normalizedRestaurant({ ...base, providerPlaceId: 'p1', address: '1 Example St' }),
    normalizedRestaurant({ ...base, providerPlaceId: 'p1', address: '1 Example St', phone: '+15550100000' }),
    normalizedRestaurant({ ...base, providerPlaceId: 'p2', name: 'CAFE FICTICIO', address: '1 Example St.' }),
    normalizedRestaurant({ ...base, providerPlaceId: 'p3', address: null, latitude: base.latitude + 0.0003 }),
    normalizedRestaurant({ ...base, providerPlaceId: 'p4', address: '9 Other St', latitude: base.latitude + 0.01 }),
    normalizedRestaurant({ ...base, providerPlaceId: '', address: 'missing ID' }),
  ];
  const { candidates, pool } = buildDeck(records, parsed, { seed: 's', minimumPool: 3 });
  assert.equal(candidates.length, 2, 'one place nearby, one branch across town');
  assert.equal(candidates.find(c => c.providerPlaceId === 'p1')?.phone, '+15550100000', 'keeps the richer listing');
  assert.deepEqual([pool.invalid, pool.duplicates, pool.eligible, pool.sufficient], [1, 3, 2, false]);
  assert.match(candidateId(records[0]), /^c[0-9a-f]{20}$/);
});

test('HERE normalization: contract fields only, title stripped from the address, unknown stays unknown', () => {
  const items = fixture('suburb').responses[0].body.items;
  const slice = normalizeHereItem(items[0]);
  assert.deepEqual(Object.keys(slice).sort(), ['address', 'attribution', 'categoryIds', 'chainId', 'cuisineIds',
    'dietaryHints', 'distanceMetersFromOrigin', 'latitude', 'longitude', 'name', 'openStatus', 'phone', 'provider',
    'providerPlaceId', 'website'].sort());
  assert.equal(slice.address, '101 Synthetic Ave, Exampleton, KS 67000, United States');
  assert.deepEqual(slice.cuisineIds, ['italian', 'pizza']);
  assert.equal(slice.chainId, 'here:9001');
  assert.equal(slice.openStatus, 'open');
  assert.match(slice.website, /^https:\/\/example\.com\//);
  const byName = name => normalizeHereItem(items.find(item => item.title === name));
  assert.equal(byName('Taqueria Inventada').openStatus, 'closed');
  assert.equal(byName('Sample Pho').openStatus, 'unknown');
  assert.equal(byName('Dummy Diner').address, '114 Synthetic Ave, Exampleton, KS 67000, United States');
  assert.deepEqual(byName('Untyped Eatery').cuisineIds, []);
  assert.equal(byName('Untyped Eatery').phone, null);
  assert.deepEqual(byName('Test Kitchen Curry').dietaryHints, ['vegetarian']);
  assert.equal(normalizeHereItem(items.find(item => item.resultType === 'locality')), null);
  assert.equal(normalizeHereItem({ ...items[0], contacts: [{ www: [{ value: 'javascript:alert(1)' }] }] }).website, null);
});

test('HERE one-circle: one browse call when the pool is healthy, with no key or free text in it', async () => {
  const { transport, calls } = replay('suburb');
  const parsed = request({ includedCuisineIds: ['thai'] });
  const result = await createHereProvider({ transport }).searchNearby(parsed);
  assert.equal(result.providerCalls, 1);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0], { kind: 'browse', params: { at: '38.5,-98.5', in: 'circle:38.5,-98.5;r=5000',
    categories: '100-1000', limit: 100 } });
  const { candidates, pool } = buildDeck(result.restaurants, parsed, { seed: 'here-1' });
  assert.equal(candidates[0].name, 'Stub Thai');
  assert.equal(pool.outOfRadius, 1);
  assert.ok(pool.sufficient);
  assert.equal(new Set(candidates.map(c => c.chainId).filter(Boolean)).size,
    candidates.filter(c => c.chainId).length);
});

test('HERE one-circle: a thin first answer triggers one discover fallback, and overlaps collapse', async () => {
  const { transport, calls } = replay('suburb');
  const result = await createHereProvider({ transport, fallbackBelow: 25 }).searchNearby(request({ deckSize: 25 }));
  assert.deepEqual(calls.map(call => call.kind), ['browse', 'discover']);
  assert.deepEqual(calls[1].params, { in: 'circle:38.5,-98.5;r=5000', q: 'restaurant', limit: 100 });
  assert.equal(result.providerCalls, 2);
  const { pool } = buildDeck(result.restaurants, request({ deckSize: 25 }), { seed: 'here-1' });
  assert.equal(pool.duplicates, 2, 'the repeated ID and the twin listing');
});

test('HERE one-circle: a rural area falls back and still reports an insufficient pool', async () => {
  const { transport } = replay('sparse');
  const parsed = request({ radius: { value: 5, unit: 'mi' } });
  const result = await createHereProvider({ transport }).searchNearby(parsed);
  assert.equal(result.providerCalls, 2);
  const { pool } = buildDeck(result.restaurants, parsed, { seed: 'rural' });
  assert.equal(pool.sufficient, false);
  assert.equal(pool.eligible, 4);
});

test('HERE failures count every call; a total failure raises ProviderUnavailable', async () => {
  const { transport } = replay('browse-fails');
  const partial = await createHereProvider({ transport }).searchNearby(request());
  assert.deepEqual([partial.providerCalls, partial.failedCalls], [2, 1]);
  assert.ok(partial.restaurants.length > 0);

  const down = createHereProvider({ transport: async () => { throw new Error('timeout'); } });
  await assert.rejects(down.searchNearby(request()), error => error instanceof ProviderUnavailable &&
    error.providerCalls === 2);
  const malformed = createHereProvider({ transport: async () => ({ status: 200, body: { nope: true } }) });
  await assert.rejects(malformed.searchNearby(request()), ProviderUnavailable);
});

test('HERE multi-center: the production layout costs four calls and mostly lands outside the circle', async () => {
  const { transport, calls } = replay('multi-center');
  const result = await createHereProvider({ transport, strategy: 'multi-center' }).searchNearby(request());
  assert.equal(result.providerCalls, 4);
  assert.ok(calls.every(call => call.kind === 'discover' && call.params.q === 'restaurant' && !call.params.in));
  const { pool } = buildDeck(result.restaurants, request(), { seed: 'm' });
  assert.equal(pool.outOfRadius, 8);
  assert.equal(pool.duplicates, 18);
  assert.equal(assertProvider(createHereProvider({ transport, strategy: 'multi-center' })).maxCallsPerSearch, 4);
});

test('HERE transport: key only in the outgoing URL, bounded by a timeout, error bodies dropped', async () => {
  const seen = [];
  const fetchImpl = async (url, options) => {
    seen.push({ url: String(url), signal: options.signal });
    return url.pathname.includes('browse')
      ? { ok: true, status: 200, json: async () => ({ items: [] }) }
      : { ok: false, status: 401, json: async () => ({ error: 'echo of the key' }) };
  };
  const transport = createHereTransport({ apiKey: 'test-key', fetchImpl });
  const ok = await transport({ endpoint: ENDPOINTS.browse, params: { at: '1,2', limit: 100 } });
  assert.deepEqual(ok, { status: 200, body: { items: [] } });
  assert.match(seen[0].url, /^https:\/\/browse\.search\.hereapi\.com\/v1\/browse\?at=1%2C2&limit=100&apiKey=test-key$/);
  assert.ok(seen[0].signal instanceof AbortSignal);
  assert.deepEqual(await transport({ endpoint: ENDPOINTS.discover, params: {} }), { status: 401, body: null });
  await assert.rejects(transport({ endpoint: 'https://example.com/steal', params: {} }), /Unexpected HERE endpoint/);
  assert.throws(() => createHereTransport({ apiKey: '' }), /key is required/);
});

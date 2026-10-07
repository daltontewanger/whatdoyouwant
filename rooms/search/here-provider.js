// HERE Geocoding & Search v7 behind the RestaurantProvider contract. The
// adapter builds requests and normalizes responses; a transport does the HTTP,
// so tests replay recorded or synthetic responses and only the real transport
// ever sees the API key.
const { normalizedRestaurant, ProviderUnavailable } = require('./provider');
const { cuisinesFromHere, dietaryHintsFromHere } = require('./cuisines');
const { distanceMeters } = require('./deck');

const ENDPOINTS = Object.freeze({
  browse: 'https://browse.search.hereapi.com/v1/browse',
  discover: 'https://discover.search.hereapi.com/v1/discover',
});
// Level-2 category: every restaurant subcategory (casual, fast food, deli...).
const RESTAURANTS = '100-1000';
const LIMIT = 100;
// Placeholder until the plan's attribution terms are confirmed.
const ATTRIBUTION = 'Restaurant data © HERE';
// The production function's layout: four centers about five miles out.
const MULTI_CENTER_OFFSET_METERS = 8047;

const STRATEGIES = Object.freeze({
  // One circle-constrained browse, plus one discover only when the first
  // result is too thin. Worst case two calls.
  'one-circle': { maxCalls: 2 },
  // Today's production search, kept for the benchmark comparison.
  'multi-center': { maxCalls: 4 },
});

const fixed = value => Number(value.toFixed(6));

function circle(request) {
  return `circle:${fixed(request.origin.lat)},${fixed(request.origin.lng)};r=${request.radiusMeters}`;
}

function centersAround(origin) {
  const dLat = MULTI_CENTER_OFFSET_METERS / 111320;
  const dLng = MULTI_CENTER_OFFSET_METERS / (111320 * Math.cos((origin.lat * Math.PI) / 180));
  return [[dLat, 0], [-dLat, 0], [0, dLng], [0, -dLng]]
    .map(([lat, lng]) => ({ lat: fixed(origin.lat + lat), lng: fixed(origin.lng + lng) }));
}

function openStatusOf(item) {
  const hours = Array.isArray(item.openingHours) ? item.openingHours : [];
  if (hours.some(entry => entry?.isOpen === true)) return 'open';
  if (hours.some(entry => entry?.isOpen === false)) return 'closed';
  return 'unknown';
}

// HERE address labels usually start with the place's own name; drop it so
// the card does not repeat itself.
function addressOf(item) {
  const label = item.address?.label;
  if (typeof label !== 'string') return null;
  const prefix = `${item.title}, `;
  return label.startsWith(prefix) ? label.slice(prefix.length) : label;
}

function normalizeHereItem(item) {
  if (!item || item.resultType !== 'place' || !item.position) return null;
  const foodTypes = (item.foodTypes ?? []).map(type => type?.id).filter(id => typeof id === 'string');
  const categories = (item.categories ?? []).map(category => category?.id).filter(id => typeof id === 'string');
  const contact = item.contacts?.[0] ?? {};
  const chain = item.chains?.[0]?.id;
  return normalizedRestaurant({
    provider: 'here',
    providerPlaceId: item.id,
    name: item.title,
    address: addressOf(item),
    latitude: item.position.lat,
    longitude: item.position.lng,
    cuisineIds: cuisinesFromHere(foodTypes, categories),
    categoryIds: categories,
    dietaryHints: dietaryHintsFromHere(foodTypes),
    openStatus: openStatusOf(item),
    phone: contact.phone?.[0]?.value,
    website: contact.www?.[0]?.value,
    chainId: chain ? `here:${chain}` : null,
  });
}

/**
 * @param {object} options
 * @param {(call: {endpoint: string, params: object}) => Promise<{status: number, body: any}>} options.transport
 * @param {'one-circle'|'multi-center'} [options.strategy]
 * @param {number} [options.fallbackBelow] Run the fallback when fewer in-radius places come back.
 */
function createHereProvider({ transport, strategy = 'one-circle', fallbackBelow = 15 }) {
  if (typeof transport !== 'function') throw new Error('The HERE provider needs a transport.');
  if (!STRATEGIES[strategy]) throw new Error(`Unknown HERE strategy ${strategy}.`);

  return {
    id: 'here',
    version: `1/${strategy}`,
    maxCallsPerSearch: STRATEGIES[strategy].maxCalls,

    async searchNearby(request) {
      let providerCalls = 0;
      let failedCalls = 0;
      const items = [];
      // Every attempt counts against the budget, including failures and
      // timeouts: the provider may have billed a request we never heard back from.
      const call = async (endpoint, params) => {
        providerCalls++;
        try {
          const response = await transport({ endpoint, params: { ...params, limit: LIMIT } });
          if (response?.status !== 200 || !Array.isArray(response.body?.items)) throw new Error(`HTTP ${response?.status}`);
          items.push(...response.body.items);
          return true;
        } catch {
          failedCalls++;
          return false;
        }
      };

      if (strategy === 'one-circle') {
        const at = `${fixed(request.origin.lat)},${fixed(request.origin.lng)}`;
        const primary = await call(ENDPOINTS.browse, { at, in: circle(request), categories: RESTAURANTS });
        const inRadius = items.filter(item => item?.resultType === 'place' && item.position &&
          distanceMeters(request.origin, item.position) <= request.radiusMeters).length;
        if (!primary || inRadius < fallbackBelow) {
          await call(ENDPOINTS.discover, { in: circle(request), q: 'restaurant' });
        }
      } else {
        for (const center of centersAround(request.origin)) {
          await call(ENDPOINTS.discover, { at: `${center.lat},${center.lng}`, q: 'restaurant' });
        }
      }

      if (failedCalls === providerCalls) {
        throw new ProviderUnavailable('HERE search failed.', { providerCalls });
      }
      const restaurants = items.map(normalizeHereItem).filter(Boolean);
      return { restaurants, providerCalls, failedCalls, attribution: ATTRIBUTION };
    },
  };
}

/**
 * The live transport. Not used by tests or the emulators; it exists so the
 * adapter has one reviewed place where a key and the network meet.
 */
function createHereTransport({ apiKey, fetchImpl = fetch, timeoutMs = 4000 }) {
  if (typeof apiKey !== 'string' || !apiKey) throw new Error('A HERE key is required.');
  return async ({ endpoint, params }) => {
    if (!Object.values(ENDPOINTS).includes(endpoint)) throw new Error('Unexpected HERE endpoint.');
    const url = new URL(endpoint);
    for (const [name, value] of Object.entries({ ...params, apiKey })) url.searchParams.set(name, String(value));
    const response = await fetchImpl(url, { signal: AbortSignal.timeout(timeoutMs) });
    // Error bodies can echo the request URL, key included; never keep them.
    return { status: response.status, body: response.ok ? await response.json() : null };
  };
}

module.exports = { createHereProvider, createHereTransport, normalizeHereItem, ENDPOINTS, STRATEGIES };

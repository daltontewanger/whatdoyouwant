// The only search input a client can send. Anything outside this shape is
// rejected rather than trimmed, so nothing unexpected can reach a provider.
const { CUISINE_IDS } = require('./cuisines');

const MIN_RADIUS_METERS = 400;
const MAX_RADIUS_METERS = 25000;
const DECK_SIZES = Object.freeze([10, 15, 20]);
const DEFAULT_DECK_SIZE = 15;
const MAX_CUISINES = 8;
const FIELDS = ['origin', 'radiusMeters', 'includedCuisineIds', 'excludedCuisineIds', 'openNowPreferred', 'deckSize'];
const REQUIRED = ['origin', 'radiusMeters'];

class InvalidSearchRequest extends Error {}

function fail(reason) {
  throw new InvalidSearchRequest(reason);
}

function cuisineList(value, name) {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > MAX_CUISINES) fail(`${name} must be a short list`);
  if (!value.every(id => typeof id === 'string' && CUISINE_IDS.includes(id))) fail(`${name} has an unknown cuisine`);
  if (new Set(value).size !== value.length) fail(`${name} repeats a cuisine`);
  return [...value].sort();
}

function coordinate(value, limit) {
  return typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= limit;
}

// Returns a normalized request. The origin is only for this search: callers
// must not store or log it (decks keep distances, not where someone stood).
function parseSearchRequest(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) fail('request must be an object');
  const keys = Object.keys(data);
  if (!keys.every(key => FIELDS.includes(key)) || !REQUIRED.every(key => keys.includes(key))) {
    fail('request has missing or unexpected fields');
  }
  const { origin } = data;
  if (!origin || typeof origin !== 'object' || Array.isArray(origin) ||
    Object.keys(origin).sort().join() !== 'lat,lng' || !coordinate(origin.lat, 90) || !coordinate(origin.lng, 180)) {
    fail('origin must be { lat, lng }');
  }
  const radius = data.radiusMeters;
  if (!Number.isInteger(radius) || radius < MIN_RADIUS_METERS || radius > MAX_RADIUS_METERS) {
    fail('radiusMeters is out of range');
  }
  const included = cuisineList(data.includedCuisineIds, 'includedCuisineIds');
  const excluded = cuisineList(data.excludedCuisineIds, 'excludedCuisineIds');
  if (included.some(id => excluded.includes(id))) fail('a cuisine cannot be both included and excluded');
  if (data.openNowPreferred !== undefined && typeof data.openNowPreferred !== 'boolean') {
    fail('openNowPreferred must be true or false');
  }
  const deckSize = data.deckSize ?? DEFAULT_DECK_SIZE;
  if (!DECK_SIZES.includes(deckSize)) fail('deckSize is not offered');
  return {
    origin: { lat: origin.lat, lng: origin.lng },
    radiusMeters: radius,
    includedCuisineIds: included,
    excludedCuisineIds: excluded,
    openNowPreferred: data.openNowPreferred === true,
    deckSize,
  };
}

// Everything about a request except where it was made: safe to store with a
// deck, compare across retries and show back to the host.
function filterSummary(request) {
  const { origin, ...rest } = request;
  return rest;
}

module.exports = { parseSearchRequest, filterSummary, InvalidSearchRequest, DECK_SIZES, MIN_RADIUS_METERS,
  MAX_RADIUS_METERS };

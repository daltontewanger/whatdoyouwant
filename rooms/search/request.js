// The only search input a client can send. Anything outside this shape is
// rejected rather than trimmed, so nothing unexpected can reach a provider.
const { CUISINE_IDS } = require('./cuisines');
const { zipCentre, ZIP } = require('./zip-codes');

// The radius choices the app offers, in either unit; miles are the default
// in the app, kilometres an option.
const RADIUS_VALUES = Object.freeze([1, 3, 5, 10, 15]);
const METERS_PER_UNIT = Object.freeze({ mi: 1609.344, km: 1000 });
const DECK_SIZES = Object.freeze([5, 10, 15, 25]);
const DEFAULT_DECK_SIZE = 15;
const MAX_CUISINES = 8;
const FIELDS = ['origin', 'radius', 'includedCuisineIds', 'excludedCuisineIds', 'openNowPreferred', 'deckSize'];
const REQUIRED = ['origin', 'radius'];

class InvalidSearchRequest extends Error {}

// A well-formed ZIP code that has no area to search, so the person can be
// told to check it rather than given a generic failure.
class UnknownZip extends InvalidSearchRequest {}

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

// Either a position or a US ZIP code, which stands in for its centre. The ZIP
// code itself goes no further than this, so it is never stored or logged.
function searchOrigin(origin) {
  if (!origin || typeof origin !== 'object' || Array.isArray(origin)) fail('origin must be { lat, lng } or { zip }');
  const keys = Object.keys(origin).sort().join();
  if (keys === 'zip') {
    if (typeof origin.zip !== 'string' || !ZIP.test(origin.zip)) fail('zip must be five digits');
    const centre = zipCentre(origin.zip);
    if (!centre) throw new UnknownZip('zip has no area to search');
    return centre;
  }
  if (keys !== 'lat,lng' || !coordinate(origin.lat, 90) || !coordinate(origin.lng, 180)) {
    fail('origin must be { lat, lng } or { zip }');
  }
  return origin;
}

// Returns a normalized request. The origin is only for this search: callers
// must not store or log it (decks keep distances, not where someone stood).
function parseSearchRequest(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) fail('request must be an object');
  const keys = Object.keys(data);
  if (!keys.every(key => FIELDS.includes(key)) || !REQUIRED.every(key => keys.includes(key))) {
    fail('request has missing or unexpected fields');
  }
  const origin = searchOrigin(data.origin);
  const { radius } = data;
  if (!radius || typeof radius !== 'object' || Array.isArray(radius) ||
    Object.keys(radius).sort().join() !== 'unit,value' || !RADIUS_VALUES.includes(radius.value) ||
    !Object.hasOwn(METERS_PER_UNIT, radius.unit)) {
    fail('radius must be one of the offered distances');
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
    radius: { value: radius.value, unit: radius.unit },
    radiusMeters: Math.round(radius.value * METERS_PER_UNIT[radius.unit]),
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

module.exports = { parseSearchRequest, filterSummary, InvalidSearchRequest, UnknownZip, DECK_SIZES, RADIUS_VALUES };

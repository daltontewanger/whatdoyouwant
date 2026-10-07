// Turns normalized provider records into one deterministic deck. Pure: no I/O,
// no clock, no randomness except the seed it is given, so the same records,
// request and seed always produce the same deck.
const { createHash } = require('node:crypto');

const MINIMUM_POOL = 8;
const EARTH_RADIUS_METERS = 6371008.8;
// Records closer than this with the same name are one place listed twice.
const SAME_PLACE_METERS = 75;

function distanceMeters(a, b) {
  const rad = degrees => (degrees * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}

const normalizeText = text => String(text ?? '').toLowerCase().normalize('NFKD').replace(/[̀-ͯ]/g, '')
  .replace(/&/g, ' and ').replace(/[^a-z0-9]+/g, ' ').trim();

const hash = value => createHash('sha256').update(value).digest('hex');

// A short, stable ID for a place within a deck; provider IDs can be long and
// contain characters awkward in document paths.
const candidateId = record => `c${hash(`${record.provider}:${record.providerPlaceId}`).slice(0, 20)}`;

function isUsable(record) {
  return record && typeof record.provider === 'string' && typeof record.providerPlaceId === 'string' &&
    record.providerPlaceId.length > 0 && normalizeText(record.name).length > 0 &&
    Number.isFinite(record.latitude) && Number.isFinite(record.longitude);
}

// Keeps the better of two listings of one place: the one with more detail,
// then the closer one.
function richer(a, b) {
  const detail = r => (r.address ? 2 : 0) + (r.cuisineIds.length ? 2 : 0) + (r.phone ? 1 : 0) + (r.website ? 1 : 0) +
    (r.openStatus !== 'unknown' ? 1 : 0);
  if (detail(a) !== detail(b)) return detail(a) > detail(b) ? a : b;
  return a.distanceMetersFromOrigin <= b.distanceMetersFromOrigin ? a : b;
}

function dedupe(records) {
  const byProviderId = new Map();
  for (const record of records) {
    const key = `${record.provider}:${record.providerPlaceId}`;
    const existing = byProviderId.get(key);
    byProviderId.set(key, existing ? richer(existing, record) : record);
  }
  const kept = [];
  for (const record of byProviderId.values()) {
    const name = normalizeText(record.name);
    const address = normalizeText(record.address);
    const twin = kept.findIndex(other => normalizeText(other.name) === name &&
      ((address && address === normalizeText(other.address)) ||
        distanceMeters({ lat: record.latitude, lng: record.longitude },
          { lat: other.latitude, lng: other.longitude }) <= SAME_PLACE_METERS));
    if (twin === -1) kept.push(record);
    else kept[twin] = richer(kept[twin], record);
  }
  return { kept, duplicates: records.length - kept.length };
}

// Integer points so ordering never depends on floating-point rounding.
// Included cuisines dominate; unknown cuisine sits between a match and a known
// non-match (the flexible policy). Open-now only counts when asked for.
function score(record, request) {
  let points = 0;
  if (request.includedCuisineIds.length) {
    if (record.cuisineIds.some(id => request.includedCuisineIds.includes(id))) points += 3000;
    else if (!record.cuisineIds.length) points += 1000;
  }
  if (request.openNowPreferred) {
    if (record.openStatus === 'open') points += 600;
    else if (record.openStatus === 'closed') points -= 600;
  }
  points += Math.round(500 * (1 - record.distanceMetersFromOrigin / request.radiusMeters));
  if (record.address) points += 100;
  if (record.cuisineIds.length) points += 50;
  if (record.phone || record.website) points += 50;
  return points;
}

// Picks a varied deck: one location per chain and no cuisine taking more than
// a third of the cards, unless the pool is too small to allow it.
function selectVaried(ranked, deckSize) {
  const perCuisine = Math.max(2, Math.ceil(deckSize / 3));
  const chains = new Set();
  const cuisineCounts = new Map();
  const chosen = [];
  const skipped = [];
  for (const record of ranked) {
    if (chosen.length === deckSize) break;
    const cuisine = record.cuisineIds[0];
    if ((record.chainId && chains.has(record.chainId)) || (cuisine && (cuisineCounts.get(cuisine) ?? 0) >= perCuisine)) {
      skipped.push(record);
      continue;
    }
    chosen.push(record);
    if (record.chainId) chains.add(record.chainId);
    if (cuisine) cuisineCounts.set(cuisine, (cuisineCounts.get(cuisine) ?? 0) + 1);
  }
  for (const record of skipped) {
    if (chosen.length === deckSize) break;
    chosen.push(record);
  }
  const rank = new Map(ranked.map((record, index) => [record, index]));
  return chosen.sort((a, b) => rank.get(a) - rank.get(b));
}

/**
 * The places a deck may be drawn from: usable, inside the radius, not
 * positively excluded, one listing per place, distances from the origin.
 * @returns {{kept: object[], counts: object}}
 */
function eligiblePool(records, request) {
  const usable = records.filter(isUsable).map(record => ({
    ...record,
    cuisineIds: [...(record.cuisineIds ?? [])],
    openStatus: ['open', 'closed'].includes(record.openStatus) ? record.openStatus : 'unknown',
    // Provider distances are measured from wherever the provider searched,
    // which is not always the person's origin; always measure again.
    distanceMetersFromOrigin: distanceMeters(request.origin, { lat: record.latitude, lng: record.longitude }),
  }));
  const inRadius = usable.filter(record => record.distanceMetersFromOrigin <= request.radiusMeters);
  const allowed = inRadius.filter(record => !record.cuisineIds.some(id => request.excludedCuisineIds.includes(id)));
  const { kept, duplicates } = dedupe(allowed);
  return {
    kept,
    counts: {
      received: records.length,
      invalid: records.length - usable.length,
      outOfRadius: usable.length - inRadius.length,
      excluded: inRadius.length - allowed.length,
      duplicates,
      eligible: kept.length,
    },
  };
}

/**
 * Builds a deck from normalized records.
 * @param {object[]} records NormalizedRestaurant records from any provider.
 * @param {object} request A parsed search request (see request.js).
 * @param {{seed: string, minimumPool?: number}} options The stored seed decides exact ties.
 * @returns {{candidates: object[], pool: object}} Candidates in deck order and a pool report.
 */
function buildDeck(records, request, { seed, minimumPool = Math.min(MINIMUM_POOL, request.deckSize) }) {
  if (typeof seed !== 'string' || !seed.length) throw new Error('A deck needs a stored seed.');
  const { kept, counts } = eligiblePool(records, request);
  const ranked = kept
    .map(record => ({ record, points: score(record, request), tie: hash(`${seed}:${candidateId(record)}`) }))
    .sort((a, b) => b.points - a.points || (a.tie < b.tie ? -1 : a.tie > b.tie ? 1 : 0))
    .map(entry => entry.record);
  const chosen = selectVaried(ranked, request.deckSize);
  const candidates = chosen.map((record, order) => ({
    ...record,
    id: candidateId(record),
    order,
    distanceMetersFromOrigin: Math.round(record.distanceMetersFromOrigin),
  }));
  return {
    candidates,
    pool: {
      ...counts,
      selected: candidates.length,
      minimum: minimumPool,
      sufficient: kept.length >= minimumPool,
    },
  };
}

module.exports = { buildDeck, eligiblePool, distanceMeters, normalizeText, candidateId, MINIMUM_POOL };

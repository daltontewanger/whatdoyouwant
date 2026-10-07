// Replays recorded HERE calls for one location and measures what each search
// strategy would have produced. No network: only recorded responses are read.
const { createHereProvider, ENDPOINTS } = require('../../../rooms/search/here-provider');
const { parseSearchRequest } = require('../../../rooms/search/request');
const { buildDeck, eligiblePool } = require('../../../rooms/search/deck');

const TARGET_POOL = 15;

// One-circle with and without its fallback, and today's production layout.
function variants(fallbackBelow) {
  return [
    { name: 'one-circle, no fallback', strategy: 'one-circle', fallbackBelow: 0 },
    { name: `one-circle, fallback < ${fallbackBelow}`, strategy: 'one-circle', fallbackBelow },
    { name: 'multi-center (production)', strategy: 'multi-center' },
  ];
}

const endpointName = url => Object.keys(ENDPOINTS).find(key => ENDPOINTS[key] === url);
const sameParams = (a, b) => JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());

// Serves each call from the recording, matched on endpoint and parameters, so
// a recording made once answers every strategy that asks the same question.
function replayTransport(recording) {
  const used = [];
  const transport = async ({ endpoint, params }) => {
    const kind = endpointName(endpoint);
    const call = recording.calls.find(entry => entry.endpoint === kind && sameParams(entry.params, params));
    if (!call) throw new Error(`Recording ${recording.location.id} has no ${kind} call for ${JSON.stringify(params)}.`);
    used.push(call);
    if (call.timedOut) throw new Error('timeout');
    return { status: call.status, body: call.body };
  };
  return { transport, used };
}

const share = (part, whole) => (whole ? part / whole : null);

async function measure(recording, variant) {
  const request = parseSearchRequest({ origin: recording.origin, radius: recording.radius, deckSize: TARGET_POOL });
  const { transport, used } = replayTransport(recording);
  const provider = createHereProvider({ transport, strategy: variant.strategy, fallbackBelow: variant.fallbackBelow });
  let result;
  try {
    result = await provider.searchNearby(request);
  } catch (error) {
    return { location: recording.location, variant: variant.name, failed: true, calls: error.providerCalls ?? used.length,
      timeouts: used.filter(call => call.timedOut).length, rateLimited: used.filter(call => call.status === 429).length };
  }
  const { kept, counts } = eligiblePool(result.restaurants, request);
  const deck = buildDeck(result.restaurants, request, { seed: 'benchmark', minimumPool: TARGET_POOL });
  const inRadius = counts.received - counts.invalid - counts.outOfRadius;
  const latencies = used.map(call => call.latencyMs).filter(Number.isFinite);
  const rate = test => share(kept.filter(test).length, kept.length);
  return {
    location: recording.location,
    variant: variant.name,
    failed: false,
    calls: result.providerCalls,
    failedCalls: result.failedCalls,
    timeouts: used.filter(call => call.timedOut).length,
    rateLimited: used.filter(call => call.status === 429).length,
    cacheControl: [...new Set(used.map(call => call.headers?.['cache-control']).filter(Boolean))],
    latencyMs: latencies.length ? latencies.reduce((a, b) => a + b, 0) : null,
    received: used.reduce((sum, call) => sum + (call.body?.items?.length ?? 0), 0),
    places: counts.received - counts.invalid,
    inRadius,
    duplicates: counts.duplicates,
    duplicateRate: share(counts.duplicates, inRadius),
    eligible: counts.eligible,
    usable: counts.eligible >= TARGET_POOL,
    cuisines: new Set(kept.flatMap(record => record.cuisineIds)).size,
    deckCuisines: new Set(deck.candidates.flatMap(record => record.cuisineIds)).size,
    unknownCuisineRate: rate(record => !record.cuisineIds.length),
    missingAddressRate: rate(record => !record.address),
    missingPhoneRate: rate(record => !record.phone),
    missingWebsiteRate: rate(record => !record.website),
    unknownOpenRate: rate(record => record.openStatus === 'unknown'),
    chainRate: rate(record => Boolean(record.chainId)),
    dietaryHintRate: rate(record => record.dietaryHints.length > 0),
  };
}

const mean = values => {
  const known = values.filter(value => value !== null && Number.isFinite(value));
  return known.length ? known.reduce((a, b) => a + b, 0) / known.length : null;
};
const median = values => {
  const sorted = values.filter(Number.isFinite).sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

function summarize(rows) {
  const ok = rows.filter(row => !row.failed);
  const usable = ok.filter(row => row.usable).length;
  const calls = rows.reduce((sum, row) => sum + row.calls, 0);
  return {
    variant: rows[0]?.variant,
    locations: rows.length,
    failed: rows.length - ok.length,
    totalCalls: calls,
    meanCalls: mean(rows.map(row => row.calls)),
    callsPerUsableDeck: usable ? calls / usable : null,
    usableShare: share(usable, rows.length),
    medianEligible: median(ok.map(row => row.eligible)),
    meanDuplicateRate: mean(ok.map(row => row.duplicateRate)),
    meanCuisines: mean(ok.map(row => row.cuisines)),
    meanUnknownCuisineRate: mean(ok.map(row => row.unknownCuisineRate)),
    meanMissingPhoneRate: mean(ok.map(row => row.missingPhoneRate)),
    meanUnknownOpenRate: mean(ok.map(row => row.unknownOpenRate)),
    meanChainRate: mean(ok.map(row => row.chainRate)),
    meanDietaryHintRate: mean(ok.map(row => row.dietaryHintRate)),
    timeoutRate: share(rows.reduce((sum, row) => sum + row.timeouts, 0), calls),
    rateLimitedCalls: rows.reduce((sum, row) => sum + row.rateLimited, 0),
    // Distinct caching headers seen, for checking what HERE allows us to keep.
    cacheControl: [...new Set(rows.flatMap(row => row.cacheControl ?? []))],
    meanLatencyMs: mean(ok.map(row => row.latencyMs)),
  };
}

async function runBenchmark(recordings, { fallbackBelow = TARGET_POOL } = {}) {
  const results = [];
  for (const variant of variants(fallbackBelow)) {
    const rows = [];
    for (const recording of recordings) rows.push(await measure(recording, variant));
    results.push({ summary: summarize(rows), rows });
  }
  return { synthetic: recordings.every(recording => recording.synthetic === true), results };
}

module.exports = { runBenchmark, measure, summarize, replayTransport, variants, TARGET_POOL };

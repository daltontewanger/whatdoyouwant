// Records live HERE responses for the search benchmark. Only for a run the owner
// has approved: an approved location list, an approved call ceiling and the
// benchmark key. Without --live it only prints the plan.
//
//   node local-testing/search/benchmark/record-here.cjs --locations <file> --max-calls 150
//   HERE_BENCHMARK_API_KEY=... node ... --locations <file> --max-calls 150 --live
//
// Each location costs 6 calls: one-circle browse and its discover fallback
// (always recorded, so any fallback threshold can be replayed later) and the
// four production multi-center discovers. Recordings go to an ignored folder
// and stay on this machine; HERE's storage terms decide how long they may be kept.
const { mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');
const { createHereProvider, createHereTransport, STRATEGIES } = require('../../../rooms/search/here-provider');
const { parseSearchRequest } = require('../../../rooms/search/request');

const CALLS_PER_LOCATION = STRATEGIES['one-circle'].maxCalls + STRATEGIES['multi-center'].maxCalls;
const LOCATION_TYPES = ['dense-urban', 'urban', 'suburb', 'small-town', 'rural', 'coastal', 'chain-heavy',
  'independent-heavy', 'boundary'];
const MAX_LOCATIONS = 30;
const DEFAULT_OUT = path.join(__dirname, 'recordings');

function parseArgs(argv) {
  const args = { live: false, out: DEFAULT_OUT };
  for (let i = 0; i < argv.length; i++) {
    const flag = argv[i];
    if (flag === '--live') args.live = true;
    else if (flag === '--locations') args.locations = argv[++i];
    else if (flag === '--max-calls') args.maxCalls = Number(argv[++i]);
    else if (flag === '--out') args.out = argv[++i];
    else throw new Error(`Unknown option ${flag}.`);
  }
  if (!args.locations) throw new Error('Pass --locations with the approved location list.');
  if (!Number.isInteger(args.maxCalls) || args.maxCalls < 1) throw new Error('Pass --max-calls with the approved ceiling.');
  return args;
}

function validateLocations(list) {
  if (!Array.isArray(list) || !list.length || list.length > MAX_LOCATIONS) {
    throw new Error(`The location list must have 1-${MAX_LOCATIONS} entries.`);
  }
  const ids = new Set();
  return list.map(entry => {
    if (!/^[a-z0-9-]{1,40}$/.test(entry?.id ?? '') || ids.has(entry.id)) throw new Error('Each location needs a unique id.');
    ids.add(entry.id);
    if (!LOCATION_TYPES.includes(entry.type)) throw new Error(`${entry.id}: type must be one of ${LOCATION_TYPES.join(', ')}.`);
    // Reuses the app's request contract, so only offered radii can be recorded.
    parseSearchRequest({ origin: { lat: entry.lat, lng: entry.lng }, radius: entry.radius });
    return { id: entry.id, label: String(entry.label ?? entry.id), type: entry.type,
      origin: { lat: entry.lat, lng: entry.lng }, radius: entry.radius };
  });
}

// Wraps the live transport to keep what came back. Parameters are recorded as
// the adapter sent them; the key is added inside the live transport and never
// reaches this layer.
function recordingTransport(live, calls, budget) {
  return async ({ endpoint, params }) => {
    if (budget.used >= budget.max) throw new Error('Call ceiling reached.');
    budget.used++;
    const kind = endpoint.includes('browse') ? 'browse' : 'discover';
    const started = Date.now();
    try {
      const response = await live({ endpoint, params });
      calls.push({ endpoint: kind, params, status: response.status, latencyMs: Date.now() - started,
        body: response.body });
      return response;
    } catch (error) {
      calls.push({ endpoint: kind, params, status: null, latencyMs: Date.now() - started,
        timedOut: error?.name === 'TimeoutError', body: null });
      throw new Error('HERE request failed.');
    }
  };
}

async function record({ locations, maxCalls, live, out, apiKey, fetchImpl, log = console.log }) {
  const planned = locations.length * CALLS_PER_LOCATION;
  log(`${locations.length} locations x ${CALLS_PER_LOCATION} calls = ${planned} HERE calls (ceiling ${maxCalls}).`);
  if (planned > maxCalls) throw new Error('The plan exceeds the approved call ceiling; nothing was called.');
  if (!live) {
    log('Dry run: no calls made. Add --live to record.');
    return { planned, used: 0, files: [] };
  }
  const transport = createHereTransport({ apiKey, fetchImpl });
  const budget = { used: 0, max: maxCalls };
  mkdirSync(out, { recursive: true });
  const files = [];
  for (const location of locations) {
    const calls = [];
    const request = parseSearchRequest({ origin: location.origin, radius: location.radius });
    const recorder = recordingTransport(transport, calls, budget);
    // An infinite threshold makes one-circle always run its fallback.
    for (const options of [{ strategy: 'one-circle', fallbackBelow: Infinity }, { strategy: 'multi-center' }]) {
      try {
        await createHereProvider({ transport: recorder, ...options }).searchNearby(request);
      } catch {
        // Failures are part of the measurement; the recording keeps them.
      }
    }
    const file = path.join(out, `${location.id}.json`);
    writeFileSync(file, `${JSON.stringify({ synthetic: false, recordedAt: new Date().toISOString(),
      location: { id: location.id, label: location.label, type: location.type }, origin: location.origin,
      radius: location.radius, calls }, null, 2)}\n`);
    files.push(file);
    log(`${location.id}: ${calls.length} calls, ${calls.filter(call => call.status !== 200).length} failed.`);
  }
  log(`Done: ${budget.used} HERE calls used of ${maxCalls}.`);
  return { planned, used: budget.used, files };
}

if (require.main === module) {
  (async () => {
    const args = parseArgs(process.argv.slice(2));
    const locations = validateLocations(JSON.parse(readFileSync(args.locations, 'utf8')));
    const apiKey = process.env.HERE_BENCHMARK_API_KEY;
    if (args.live && !apiKey) throw new Error('Set HERE_BENCHMARK_API_KEY for a live run.');
    await record({ ...args, locations, apiKey });
  })().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = { record, validateLocations, parseArgs, CALLS_PER_LOCATION };

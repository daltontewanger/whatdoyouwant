// Compares search strategies on recorded HERE responses. No network.
//
//   npm run benchmark:search                         synthetic locations
//   npm run benchmark:search -- --recordings <dir>   real recordings (record-here.cjs)
//   options: --fallback-below <n>   --out <report.json>
const { readdirSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');
require('../../network-guard.cjs').installHttpGuard();
const { runBenchmark } = require('./metrics.cjs');
const { syntheticRecordings } = require('./synthetic.cjs');

function parseArgs(argv) {
  const args = { fallbackBelow: 15 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--recordings') args.recordings = argv[++i];
    else if (argv[i] === '--fallback-below') args.fallbackBelow = Number(argv[++i]);
    else if (argv[i] === '--out') args.out = argv[++i];
    else throw new Error(`Unknown option ${argv[i]}.`);
  }
  if (!Number.isInteger(args.fallbackBelow) || args.fallbackBelow < 1) throw new Error('--fallback-below must be a count.');
  return args;
}

function loadRecordings(dir) {
  return readdirSync(dir).filter(name => name.endsWith('.json')).sort()
    .map(name => JSON.parse(readFileSync(path.join(dir, name), 'utf8')));
}

const percent = value => (value === null ? '-' : `${Math.round(value * 100)}%`);
const number = (value, digits = 1) => (value === null ? '-' : value.toFixed(digits));

function print({ synthetic, results }) {
  console.log(synthetic ? 'SYNTHETIC locations: these numbers describe the simulation, not HERE.\n' :
    'Recorded HERE responses.\n');
  console.table(Object.fromEntries(results.map(({ summary: s }) => [s.variant, {
    locations: s.locations,
    'calls/location': number(s.meanCalls),
    'calls/usable deck': number(s.callsPerUsableDeck),
    '>=15 usable': percent(s.usableShare),
    'median pool': number(s.medianEligible, 0),
    duplicates: percent(s.meanDuplicateRate),
    cuisines: number(s.meanCuisines),
    'unknown cuisine': percent(s.meanUnknownCuisineRate),
    'no phone': percent(s.meanMissingPhoneRate),
    'hours unknown': percent(s.meanUnknownOpenRate),
    chains: percent(s.meanChainRate),
    'dietary hints': percent(s.meanDietaryHintRate),
    timeouts: percent(s.timeoutRate),
    '429s': s.rateLimitedCalls,
    'latency ms': number(s.meanLatencyMs, 0),
  }])));
  const caching = [...new Set(results.flatMap(({ summary }) => summary.cacheControl))];
  if (caching.length) console.log(`Cache-Control seen: ${caching.join(' | ')}\n`);
  console.log('Per location (usable pool / calls):');
  const locations = results[0].rows.map(row => row.location.id);
  console.table(Object.fromEntries(locations.map((id, index) => [id, Object.fromEntries(results.map(({ rows }) => [
    rows[index].variant, rows[index].failed ? `failed (${rows[index].calls})` : `${rows[index].eligible} / ${rows[index].calls}`,
  ]))])));
}

if (require.main === module) {
  (async () => {
    const args = parseArgs(process.argv.slice(2));
    const recordings = args.recordings ? loadRecordings(args.recordings) : await syntheticRecordings();
    const report = await runBenchmark(recordings, { fallbackBelow: args.fallbackBelow });
    print(report);
    if (args.out) writeFileSync(args.out, `${JSON.stringify(report, null, 2)}\n`);
  })().catch(error => {
    console.error(error.message);
    process.exitCode = 1;
  });
}

module.exports = { parseArgs, loadRecordings };

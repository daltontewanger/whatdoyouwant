// Search benchmark harness and the guarded HERE recorder. No network: the
// recorder is exercised with a fake fetch.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, readFileSync, readdirSync, rmSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
require('./network-guard.cjs').installHttpGuard();
const { runBenchmark, measure, variants } = require('./search/benchmark/metrics.cjs');
const { syntheticRecordings } = require('./search/benchmark/synthetic.cjs');
const { record, validateLocations, CALLS_PER_LOCATION } = require('./search/benchmark/record-here.cjs');
const { loadRecordings } = require('./search/benchmark/run.cjs');

const ORIGIN = { lat: 38.5, lng: -98.5 };
const RADIUS = { value: 5, unit: 'km' };
const place = (id, northMeters, extra = {}) => ({ title: `Place ${id}`, id: `here:${id}`, resultType: 'place',
  position: { lat: ORIGIN.lat + northMeters / 111320, lng: ORIGIN.lng }, address: { label: `${id} Example St` }, ...extra });

test('benchmark: every variant runs over every synthetic location and reports call costs', async () => {
  const recordings = await syntheticRecordings();
  const report = await runBenchmark(recordings);
  assert.equal(report.synthetic, true);
  assert.deepEqual(report.results.map(result => result.summary.variant), variants(15).map(variant => variant.name));
  const [single, fallback, multi] = report.results.map(result => result.summary);
  assert.equal(single.totalCalls, recordings.length);
  assert.equal(multi.totalCalls, recordings.length * 4);
  assert.ok(fallback.totalCalls > single.totalCalls && fallback.totalCalls <= recordings.length * 2);
  for (const result of report.results) assert.equal(result.rows.length, recordings.length);
});

test('benchmark: pool, duplicate and metadata measures come from the normalized records', async () => {
  const items = [
    place('a', 100, { foodTypes: [{ id: '205-000' }], contacts: [{ phone: [{ value: '+15550100001' }] }],
      chains: [{ id: '1' }], openingHours: [{ isOpen: true }] }),
    place('a', 100),
    place('b', 200, { foodTypes: [{ id: '800-077' }] }),
    place('c', 9000),
  ];
  const recording = { synthetic: true, location: { id: 'tiny', type: 'suburb' }, origin: ORIGIN, radius: RADIUS,
    calls: [{ endpoint: 'browse', params: { at: '38.5,-98.5', in: 'circle:38.5,-98.5;r=5000', categories: '100-1000',
      limit: 100 }, status: 200, latencyMs: 120, body: { items } }] };
  const row = await measure(recording, variants(15)[0]);
  assert.deepEqual([row.calls, row.received, row.places, row.inRadius, row.duplicates, row.eligible, row.usable],
    [1, 4, 4, 3, 1, 2, false]);
  assert.equal(row.latencyMs, 120);
  assert.equal(row.unknownCuisineRate, 0.5, 'b has only a dietary type, so its cuisine is unknown');
  assert.equal(row.dietaryHintRate, 0.5);
  assert.equal(row.chainRate, 0.5);
  assert.equal(row.missingPhoneRate, 0.5);
  assert.equal(row.unknownOpenRate, 0.5);

  const missing = await measure(recording, variants(15)[2]);
  assert.equal(missing.failed, true, 'a call absent from the recording counts as a failure, not a guess');
});

test('recorder: only valid, approved-shape location lists are accepted', () => {
  const ok = { id: 'town-1', label: 'A town', type: 'small-town', lat: 38.5, lng: -98.5, radius: { value: 5, unit: 'mi' } };
  assert.equal(validateLocations([ok]).length, 1);
  for (const list of [[], [ok, ok], [{ ...ok, type: 'moon' }], [{ ...ok, radius: { value: 7, unit: 'mi' } }],
    [{ ...ok, id: 'Bad Id' }], [{ ...ok, lat: 123 }], Array.from({ length: 31 }, (_, i) => ({ ...ok, id: `l${i}` }))]) {
    assert.throws(() => validateLocations(list));
  }
});

test('recorder: dry run and over-ceiling plans make no calls; live runs stay under the ceiling', async () => {
  const locations = validateLocations([
    { id: 'one', type: 'suburb', lat: 38.5, lng: -98.5, radius: { value: 5, unit: 'mi' } },
    { id: 'two', type: 'rural', lat: 39.5, lng: -99.5, radius: { value: 10, unit: 'mi' } },
  ]);
  const requested = [];
  const fetchImpl = async url => {
    requested.push(String(url));
    if (url.pathname.includes('browse')) {
      const error = new Error('slow');
      error.name = 'TimeoutError';
      throw error;
    }
    return { ok: true, status: 200, json: async () => ({ items: [] }) };
  };
  const quiet = () => {};
  const out = mkdtempSync(path.join(os.tmpdir(), 'here-recordings-'));
  try {
    const dry = await record({ locations, maxCalls: 100, live: false, out, apiKey: 'test-key', fetchImpl, log: quiet });
    assert.deepEqual([dry.planned, dry.used, requested.length], [2 * CALLS_PER_LOCATION, 0, 0]);
    await assert.rejects(record({ locations, maxCalls: 11, live: true, out, apiKey: 'test-key', fetchImpl, log: quiet }),
      /exceeds the approved call ceiling/);
    assert.equal(requested.length, 0);

    const live = await record({ locations, maxCalls: 12, live: true, out, apiKey: 'test-key', fetchImpl, log: quiet });
    assert.equal(live.used, 12);
    assert.equal(requested.length, 12);
    assert.ok(requested.every(url => url.startsWith('https://browse.search.hereapi.com/') ||
      url.startsWith('https://discover.search.hereapi.com/')));
    const files = readdirSync(out);
    assert.deepEqual(files.sort(), ['one.json', 'two.json']);
    for (const file of files) {
      const text = readFileSync(path.join(out, file), 'utf8');
      assert.ok(!text.includes('test-key') && !text.includes('apiKey'), 'the key never reaches a recording');
      const saved = JSON.parse(text);
      assert.equal(saved.synthetic, false);
      assert.equal(saved.calls.length, CALLS_PER_LOCATION);
      assert.equal(saved.calls.filter(call => call.timedOut).length, 1);
    }
    const replayed = await runBenchmark(loadRecordings(out));
    const fallback = replayed.results[1].rows[0];
    assert.deepEqual([fallback.calls, fallback.timeouts], [2, 1], 'recordings replay, timeouts included');
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
});

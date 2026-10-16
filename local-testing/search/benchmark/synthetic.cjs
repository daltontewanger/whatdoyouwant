// Synthetic benchmark recordings, one per location type, in the format
// record-here.cjs produces. Each location is a made-up world of places; the
// browse and discover answers are simulated from it (nearest first, at most 100
// per call), so the harness has something to run before real recordings exist.
// The numbers it produces describe this simulation, not HERE. Built in memory
// on each run rather than stored.
const { createHereProvider } = require('../../../rooms/search/here-provider');
const { parseSearchRequest } = require('../../../rooms/search/request');
const { distanceMeters } = require('../../../rooms/search/deck');

const LIMIT = 100;

// Deterministic pseudo-random numbers so the files are stable.
function random(seed) {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const FOOD_TYPES = [['800-057', 'Pizza'], ['102-000', 'Mexican'], ['201-000', 'Chinese'], ['203-026', 'Japanese-Sushi'],
  ['205-000', 'Thai'], ['206-000', 'Vietnamese'], ['202-000', 'Indian'], ['304-000', 'Italian'], ['101-000', 'American'],
  ['800-067', 'Burgers'], ['800-060', 'Sandwich'], ['800-075', 'Seafood'], ['253-000', 'Lebanese'], ['303-000', 'Greek'],
  ['800-061', 'Breakfast'], ['800-066', 'Fusion'], ['800-078', 'Grill'], ['207-000', 'Korean']];
const CHAINS = [['9101', 'Synthetic Burger Co'], ['9102', 'Placeholder Pizza'], ['9103', 'Example Chicken'],
  ['9104', 'Mock Sub Shop'], ['9105', 'Demo Taco Stop']];

// Places per square km near the origin, how far the world reaches, and how
// complete the metadata is. Coastal worlds have nothing west of the origin.
const LOCATIONS = [
  { id: 'dense-urban', type: 'dense-urban', radius: { value: 1, unit: 'mi' }, density: 60, reachKm: 20, chain: 0.15,
    foodTypes: 0.85, phone: 0.9, web: 0.6, hours: 0.75, dietary: 0.12 },
  { id: 'urban', type: 'urban', radius: { value: 3, unit: 'mi' }, density: 12, reachKm: 25, chain: 0.25,
    foodTypes: 0.8, phone: 0.85, web: 0.5, hours: 0.7, dietary: 0.08 },
  { id: 'suburb', type: 'suburb', radius: { value: 5, unit: 'mi' }, density: 2.5, reachKm: 25, chain: 0.4,
    foodTypes: 0.75, phone: 0.85, web: 0.45, hours: 0.65, dietary: 0.05 },
  { id: 'small-town', type: 'small-town', radius: { value: 5, unit: 'mi' }, density: 0.12, reachKm: 25, chain: 0.45,
    foodTypes: 0.65, phone: 0.8, web: 0.3, hours: 0.5, dietary: 0.03 },
  { id: 'rural', type: 'rural', radius: { value: 10, unit: 'mi' }, density: 0.012, reachKm: 30, chain: 0.35,
    foodTypes: 0.55, phone: 0.7, web: 0.2, hours: 0.4, dietary: 0.01 },
  { id: 'coastal', type: 'coastal', radius: { value: 5, unit: 'mi' }, density: 3, reachKm: 25, chain: 0.3,
    foodTypes: 0.75, phone: 0.85, web: 0.45, hours: 0.6, dietary: 0.05, coast: true },
  { id: 'chain-heavy', type: 'chain-heavy', radius: { value: 3, unit: 'mi' }, density: 4, reachKm: 25, chain: 0.75,
    foodTypes: 0.8, phone: 0.9, web: 0.7, hours: 0.8, dietary: 0.04 },
  { id: 'independent-heavy', type: 'independent-heavy', radius: { value: 3, unit: 'mi' }, density: 5, reachKm: 25,
    chain: 0.05, foodTypes: 0.7, phone: 0.75, web: 0.35, hours: 0.55, dietary: 0.1 },
];

function world(spec, origin, seed) {
  const next = random(seed);
  const places = [];
  const reach = spec.reachKm * 1000;
  // Expected count over a square of side 2*reach; density falls off with distance.
  const attempts = Math.round(spec.density * (2 * spec.reachKm) ** 2);
  for (let i = 0; i < attempts; i++) {
    const dx = (next() * 2 - 1) * reach;
    const dy = (next() * 2 - 1) * reach;
    const distance = Math.hypot(dx, dy);
    if (next() > Math.max(0.15, 1 - distance / reach)) continue;
    if (spec.coast && dx < 0) continue;
    const lat = origin.lat + dy / 111320;
    const lng = origin.lng + dx / (111320 * Math.cos((origin.lat * Math.PI) / 180));
    const chain = next() < spec.chain ? CHAINS[Math.floor(next() * CHAINS.length)] : null;
    const food = FOOD_TYPES[Math.floor(next() * FOOD_TYPES.length)];
    const id = `here:pds:place:synthetic-${spec.id}-${i}`;
    const title = chain ? chain[1] : `Fictional ${food[1]} ${i}`;
    const item = {
      title, id, language: 'en', resultType: 'place',
      address: { label: `${title}, ${100 + (i % 900)} Example Rd, Synthetic City, ZZ 00000, United States` },
      position: { lat: Number(lat.toFixed(6)), lng: Number(lng.toFixed(6)) },
      categories: [{ id: food[0] === '800-067' && chain ? '100-1000-0009' : '100-1000-0000', name: 'Restaurant',
        primary: true }],
    };
    if (next() < spec.foodTypes) {
      item.foodTypes = [{ id: food[0], name: food[1], primary: true }];
      if (next() < spec.dietary) item.foodTypes.push({ id: '800-077', name: 'Vegetarian' });
    }
    if (chain) item.chains = [{ id: chain[0], name: chain[1] }];
    const contact = {};
    if (next() < spec.phone) contact.phone = [{ value: `+1555010${String(i % 10000).padStart(4, '0')}` }];
    if (next() < spec.web) contact.www = [{ value: `https://example.com/${spec.id}/${i}` }];
    if (Object.keys(contact).length) item.contacts = [contact];
    if (next() < spec.hours) item.openingHours = [{ text: ['Mon-Sun: 11:00 - 21:00'], isOpen: next() < 0.7 }];
    places.push(item);
    // A few places are listed twice under different IDs, as real data sometimes is.
    if (next() < 0.03) places.push({ ...item, id: `${id}-twin`, contacts: undefined });
  }
  return places;
}

// Nearest-first answers, the way a location search returns them.
function nearest(places, point, within) {
  return places
    .map(place => ({ place, distance: distanceMeters(point, place.position) }))
    .filter(entry => within === undefined || entry.distance <= within)
    .sort((a, b) => a.distance - b.distance)
    .slice(0, LIMIT)
    .map(entry => ({ ...entry.place, distance: Math.round(entry.distance) }));
}

function parseAt(value) {
  const [lat, lng] = value.split(',').map(Number);
  return { lat, lng };
}
function parseCircle(value) {
  const [, lat, lng, radius] = value.match(/^circle:([-\d.]+),([-\d.]+);r=(\d+)$/);
  return { center: { lat: Number(lat), lng: Number(lng) }, radius: Number(radius) };
}

async function recordSynthetic(spec, index) {
  // Fictional coordinates spread over open land; none describe a real place.
  const origin = { lat: 36 + index * 0.5, lng: -100 + index * 0.5 };
  const places = world(spec, origin, 1000 + index);
  const calls = [];
  const transport = async ({ endpoint, params }) => {
    let items;
    if (endpoint.includes('browse')) {
      const { center, radius } = parseCircle(params.in);
      items = nearest(places, center, radius);
    } else if (params.in) {
      // Discover ranks by relevance rather than distance: simulate a different
      // slice of the same circle.
      const { center, radius } = parseCircle(params.in);
      const inCircle = nearest(places, center, radius);
      items = inCircle.filter((_, i) => i % 3 !== 0).concat(inCircle.filter((_, i) => i % 3 === 0)).slice(0, LIMIT);
    } else {
      items = nearest(places, parseAt(params.at));
    }
    const body = { items };
    calls.push({ endpoint: endpoint.includes('browse') ? 'browse' : 'discover', params, status: 200, latencyMs: null,
      body });
    return { status: 200, body };
  };
  const request = parseSearchRequest({ origin, radius: spec.radius });
  await createHereProvider({ transport, strategy: 'one-circle', fallbackBelow: Infinity }).searchNearby(request);
  await createHereProvider({ transport, strategy: 'multi-center' }).searchNearby(request);
  return { synthetic: true, location: { id: spec.id, label: `Synthetic ${spec.type}`, type: spec.type }, origin,
    radius: spec.radius, calls };
}

async function syntheticRecordings() {
  const recordings = [];
  for (const [index, spec] of LOCATIONS.entries()) recordings.push(await recordSynthetic(spec, index));
  return recordings;
}

module.exports = { syntheticRecordings, recordSynthetic, LOCATIONS };

// Writes the synthetic HERE fixtures next to this file. They follow the shape
// of HERE Geocoding & Search v7 browse/discover responses but every place,
// address, phone number and coordinate is made up. Real recordings from an
// approved benchmark run replace or join them; keep `synthetic: true` on these.
//
//   node local-testing/search/here-fixtures/build-synthetic.cjs
const { writeFileSync } = require('node:fs');
const path = require('node:path');

// A fictional town in open country; nothing here describes a real person or place.
const ORIGIN = { lat: 38.5, lng: -98.5 };
let serial = 0;

function at(meters, bearingDegrees, origin = ORIGIN) {
  const bearing = (bearingDegrees * Math.PI) / 180;
  return {
    lat: Number((origin.lat + (meters * Math.cos(bearing)) / 111320).toFixed(6)),
    lng: Number((origin.lng + (meters * Math.sin(bearing)) / (111320 * Math.cos((origin.lat * Math.PI) / 180)))
      .toFixed(6)),
  };
}

function place(title, meters, bearing, { foodTypes = [], categories = [['100-1000-0000', 'Restaurant']], chain,
  open, phone = true, www = false, id, street, labelWithoutTitle = false } = {}) {
  serial++;
  const position = at(meters, bearing);
  const streetLine = street ?? `${100 + serial} Synthetic Ave`;
  const item = {
    title,
    id: id ?? `here:pds:place:840synthetic${String(serial).padStart(4, '0')}`,
    language: 'en',
    resultType: 'place',
    address: {
      label: `${labelWithoutTitle ? '' : `${title}, `}${streetLine}, Exampleton, KS 67000, United States`,
      countryCode: 'USA', countryName: 'United States', stateCode: 'KS', state: 'Kansas', city: 'Exampleton',
      street: streetLine.replace(/^\d+ /, ''), postalCode: '67000', houseNumber: streetLine.split(' ')[0],
    },
    position,
    access: [position],
    distance: Math.round(meters),
    categories: categories.map(([catId, name], index) => ({ id: catId, name, primary: index === 0 })),
  };
  if (foodTypes.length) item.foodTypes = foodTypes.map(([typeId, name], index) => ({ id: typeId, name, primary: index === 0 }));
  if (chain) item.chains = [{ id: chain[0], name: chain[1] }];
  const contact = {};
  if (phone) contact.phone = [{ value: `+1555010${String(serial).padStart(4, '0')}` }];
  if (www) contact.www = [{ value: `https://example.com/${title.toLowerCase().replace(/[^a-z]+/g, '-')}` }];
  if (Object.keys(contact).length) item.contacts = [contact];
  if (open !== undefined) item.openingHours = [{ text: ['Mon-Sun: 11:00 - 22:00'], isOpen: open }];
  return item;
}

const fastFood = ['100-1000-0009', 'Fast Food'];

function suburb() {
  serial = 0;
  const browse = [
    place('Synthetic Slice', 300, 10, { foodTypes: [['800-057', 'Pizza'], ['304-000', 'Italian']], open: true,
      chain: ['9001', 'Synthetic Slice'], www: true }),
    place('Synthetic Slice', 3900, 200, { foodTypes: [['800-057', 'Pizza']], open: true, chain: ['9001', 'Synthetic Slice'] }),
    place('Casa Ficticia', 800, 90, { foodTypes: [['102-000', 'Mexican']], open: true }),
    place('Taqueria Inventada', 1500, 120, { foodTypes: [['102-005', 'Mexican-Yucateca']],
      categories: [['100-1000-0005', 'Taqueria']], open: false }),
    place('Golden Placeholder', 1100, 140, { foodTypes: [['201-010', 'Chinese-Cantonese']], open: true }),
    place('Noodle Fixture', 2600, 160, { foodTypes: [['201-055', 'Chinese-Hot Pot'], ['800-085', 'Noodles']] }),
    place('Mock Sushi', 1700, 220, { foodTypes: [['203-026', 'Japanese-Sushi'], ['203-010', 'Japanese-Fish/Other Seafood']],
      open: true, www: true }),
    place('Stub Thai', 2100, 260, { foodTypes: [['205-000', 'Thai']], open: true }),
    place('Sample Pho', 2900, 300, { foodTypes: [['206-000', 'Vietnamese']] }),
    place('Test Kitchen Curry', 3300, 320, { foodTypes: [['202-021', 'Indian-South Indian'], ['800-077', 'Vegetarian']],
      open: true }),
    place('Burger Placeholder', 600, 30, { foodTypes: [['800-067', 'Burgers'], ['101-000', 'American']],
      categories: [fastFood], chain: ['9002', 'Burger Placeholder'], open: true }),
    place('Burger Placeholder', 4200, 250, { foodTypes: [['800-067', 'Burgers']], categories: [fastFood],
      chain: ['9002', 'Burger Placeholder'], open: true }),
    place('Example Smokehouse', 3600, 70, { foodTypes: [['101-003', 'American-Barbecue/Southern']], open: false }),
    place('Dummy Diner', 1300, 50, { foodTypes: [['101-000', 'American'], ['800-061', 'Breakfast']], open: true,
      labelWithoutTitle: true }),
    place('Faux Falafel', 2300, 100, { foodTypes: [['253-000', 'Lebanese'], ['800-076', 'Vegan']] }),
    place('Mockup Bistro', 4600, 180, { foodTypes: [['301-000', 'French']], open: true, www: true }),
    place('Fixture Fusion', 1900, 240, { foodTypes: [['800-066', 'Fusion']], open: true }),
    place('Untyped Eatery', 2500, 280, { phone: false }),
    // Outside the 5 km circle: browse can still return places at the edge.
    place('Edge of Town Grill', 5600, 340, { foodTypes: [['800-078', 'Grill']] }),
    // Not a place; normalization must skip it.
    { title: 'Exampleton, KS', id: 'here:cm:namedplace:synthetic', resultType: 'locality', position: ORIGIN },
  ];
  // Discover overlaps browse: one exact repeat (same ID) and one twin listing
  // of the same restaurant under a different ID.
  const discover = [
    browse[2],
    { ...browse[4], id: 'here:pds:place:840synthetic-twin', contacts: undefined },
    place('Late Addition Cafe', 2000, 20, { foodTypes: [['800-069', 'Pastries']] }),
  ];
  return {
    synthetic: true,
    description: 'Suburb, 5 km: chains, a repeat, a twin listing, unknown cuisine, a non-place result, one place outside the circle.',
    origin: ORIGIN,
    radiusMeters: 5000,
    responses: [
      { endpoint: 'browse', status: 200, body: { items: browse } },
      { endpoint: 'discover', status: 200, body: { items: discover } },
    ],
  };
}

function sparse() {
  serial = 100;
  const browse = [
    place('Lonely Placeholder Cafe', 2500, 45, { foodTypes: [['101-000', 'American']], open: true }),
    place('Crossroads Stub', 6200, 190, { foodTypes: [['800-062', 'Chicken']], categories: [fastFood] }),
    place('Prairie Example', 7400, 280, {}),
  ];
  const discover = [
    browse[0],
    place('Grain Elevator Grill', 7900, 120, { foodTypes: [['800-056', 'Steak House']], open: false }),
  ];
  return {
    synthetic: true,
    description: 'Rural, 8 km: too few places, so the fallback runs and the pool is still below the minimum.',
    origin: ORIGIN,
    radiusMeters: 8000,
    responses: [
      { endpoint: 'browse', status: 200, body: { items: browse } },
      { endpoint: 'discover', status: 200, body: { items: discover } },
    ],
  };
}

function browseFails() {
  const base = suburb();
  return {
    synthetic: true,
    description: 'Browse answers 503; the fallback discover still produces a (thin) pool.',
    origin: ORIGIN,
    radiusMeters: 5000,
    responses: [{ endpoint: 'browse', status: 503, body: null }, base.responses[1]],
  };
}

function multiCenter() {
  const base = suburb().responses[0].body.items;
  serial = 200;
  // The production layout searches around four points ~8 km out, so most of
  // what comes back is outside a 5 km circle around the person.
  const ring = bearing => [
    ...base.slice(0, 6),
    place(`Far Side Diner ${bearing}`, 8000, bearing, { foodTypes: [['101-000', 'American']] }),
    place(`Far Side Pizza ${bearing}`, 9500, bearing + 10, { foodTypes: [['800-057', 'Pizza']] }),
  ];
  return {
    synthetic: true,
    description: 'Four discover calls in the production layout, heavy overlap and many places outside the circle.',
    origin: ORIGIN,
    radiusMeters: 5000,
    responses: [0, 180, 90, 270].map(bearing => ({ endpoint: 'discover', status: 200, body: { items: ring(bearing) } })),
  };
}

for (const [name, build] of Object.entries({ suburb, sparse, 'browse-fails': browseFails, 'multi-center': multiCenter })) {
  writeFileSync(path.join(__dirname, `${name}.json`), `${JSON.stringify(build(), null, 2)}\n`);
}

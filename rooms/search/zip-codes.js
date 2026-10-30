// US ZIP codes to a point to search around, from a table bundled with the
// functions. Looking one up costs nothing and tells no outside service which
// ZIP code someone asked about.
const fs = require('fs');
const path = require('path');

const ZIP = /^\d{5}$/;
let table;

// Read on first use, so instances that never see a ZIP search skip the work.
function load() {
  if (table) return table;
  table = new Map();
  const text = fs.readFileSync(path.join(__dirname, 'zip-centroids.txt'), 'utf8');
  for (const line of text.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [zip, lat, lng] = line.split(',');
    table.set(zip, { lat: Number(lat), lng: Number(lng) });
  }
  return table;
}

/** The centre of a ZIP code's area, or null for one with no area (such as PO boxes only). */
function zipCentre(zip) {
  if (typeof zip !== 'string' || !ZIP.test(zip)) return null;
  const centre = load().get(zip);
  return centre ? { ...centre } : null;
}

module.exports = { zipCentre, ZIP };

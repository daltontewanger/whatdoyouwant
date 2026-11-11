// A person's own list for We'll Decide What We Want: names and notes they
// typed, never looked up with a provider. Rules cannot check each spot in a
// list, so the list is written only through saveOwnList, which checks it here.
const MAX_SPOTS = 50;
const LIMITS = Object.freeze({ name: 80, address: 120, note: 120 });
const SPOT_ID = /^[A-Za-z0-9-]{1,64}$/;

class InvalidList extends Error {}

// Trimmed, with control characters and runs of spaces collapsed, so one odd
// entry cannot carry hidden text or break a card.
function cleanText(value, max, required) {
  if (value === undefined && !required) return '';
  if (typeof value !== 'string') throw new InvalidList();
  const text = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
  if ((required && !text) || text.length > max) throw new InvalidList();
  return text;
}

/** @returns the spots as they will be stored; throws InvalidList otherwise. */
function parseOwnList(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new InvalidList();
  const keys = Object.keys(data);
  if (keys.length !== 1 || keys[0] !== 'spots' || !Array.isArray(data.spots)) throw new InvalidList();
  if (data.spots.length > MAX_SPOTS) throw new InvalidList();
  const ids = new Set();
  return data.spots.map(raw => {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new InvalidList();
    if (Object.keys(raw).some(key => !['id', 'name', 'address', 'note'].includes(key))) throw new InvalidList();
    if (typeof raw.id !== 'string' || !SPOT_ID.test(raw.id) || ids.has(raw.id)) throw new InvalidList();
    ids.add(raw.id);
    const spot = { id: raw.id, name: cleanText(raw.name, LIMITS.name, true) };
    const address = cleanText(raw.address, LIMITS.address, false);
    const note = cleanText(raw.note, LIMITS.note, false);
    if (address) spot.address = address;
    if (note) spot.note = note;
    return spot;
  });
}

module.exports = { parseOwnList, InvalidList, MAX_SPOTS, LIMITS };

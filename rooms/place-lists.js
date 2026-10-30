// A person's favorites ("I know what I want") and never list ("Never what I
// want"). Places are known by their deck card ID, a hash of the provider's
// place ID, so neither the app nor these lists hold the provider's own ID.
// Rules cannot check each entry, so lists are written only through callables
// that check them here.
const PLACE_ID = /^c[0-9a-f]{20}$/;
const MAX_PLACES = 200;
const LIMITS = Object.freeze({ name: 120, address: 200 });
// Place details from the provider are kept at most this long without the
// place turning up in a new deck; after that only the ID remains.
const DETAILS_MS = 30 * 24 * 3600000;
// Small allowance for a phone clock running ahead of the server.
const CLOCK_SKEW_MS = 5 * 60000;

class InvalidPlaces extends Error {}

const fail = () => { throw new InvalidPlaces(); };

function cleanText(value, max) {
  if (value === undefined) return '';
  if (typeof value !== 'string') fail();
  const text = value.replace(/[\u0000-\u001f\u007f]+/g, ' ').replace(/\s+/g, ' ').trim();
  if (text.length > max) fail();
  return text;
}

function exactObject(value, required, optional = []) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail();
  const keys = Object.keys(value);
  if (!required.every(key => keys.includes(key)) || !keys.every(key => required.includes(key) ||
    optional.includes(key))) {
    fail();
  }
}

function placeIds(value) {
  if (!Array.isArray(value) || value.length > MAX_PLACES) fail();
  if (!value.every(id => typeof id === 'string' && PLACE_ID.test(id)) || new Set(value).size !== value.length) fail();
  return [...value];
}

function entries(value, fields, seen) {
  if (!Array.isArray(value) || value.length > MAX_PLACES) fail();
  return value.map(raw => {
    exactObject(raw, ['id'], fields);
    if (typeof raw.id !== 'string' || !PLACE_ID.test(raw.id) || seen.has(raw.id)) fail();
    seen.add(raw.id);
    return raw;
  });
}

/**
 * The lists as they will be stored. Details older than 30 days are dropped
 * here as well as by the sweep, so a stale device copy cannot bring them back.
 */
function parsePlaces(data, now) {
  exactObject(data, ['favorites', 'never', 'useFavorites', 'useNever']);
  if (typeof data.useFavorites !== 'boolean' || typeof data.useNever !== 'boolean') fail();
  const seen = new Set();
  const favorites = entries(data.favorites, ['name', 'address', 'seenAt'], seen).map(raw => {
    const name = cleanText(raw.name, LIMITS.name);
    const address = cleanText(raw.address, LIMITS.address);
    const place = { id: raw.id };
    if (!name && !address && raw.seenAt === undefined) return place;
    if (!name || !Number.isInteger(raw.seenAt) || raw.seenAt > now + CLOCK_SKEW_MS) fail();
    if (raw.seenAt <= now - DETAILS_MS) return place;
    return { ...place, name, ...(address ? { address } : {}), seenAt: Math.min(raw.seenAt, now) };
  });
  const never = entries(data.never, ['name'], seen).map(raw => {
    const name = cleanText(raw.name, LIMITS.name);
    return name ? { id: raw.id, name } : { id: raw.id };
  });
  return { favorites, never, useFavorites: data.useFavorites, useNever: data.useNever };
}

/** When the oldest kept details run out, or null when no favorite has any. */
function detailsExpireAt(favorites) {
  const seen = favorites.filter(place => place.seenAt !== undefined).map(place => place.seenAt);
  return seen.length ? Math.min(...seen) + DETAILS_MS : null;
}

/** The same favorites with expired details removed. */
function withoutStaleDetails(favorites, now) {
  return favorites.map(place => (place.seenAt !== undefined && place.seenAt <= now - DETAILS_MS
    ? { id: place.id } : place));
}

/** What a room member shares while in the lobby: card IDs only. */
function parseRoomLists(data) {
  exactObject(data, ['roomId', 'favorites', 'never']);
  return { roomId: data.roomId, favorites: placeIds(data.favorites), never: placeIds(data.never) };
}

module.exports = { parsePlaces, parseRoomLists, detailsExpireAt, withoutStaleDetails, InvalidPlaces, PLACE_ID,
  MAX_PLACES, DETAILS_MS, LIMITS };

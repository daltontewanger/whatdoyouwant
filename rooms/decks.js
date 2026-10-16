// restaurantDecks/{deckId}: one immutable deck per decision, written only by
// callables and removed by TTL with the room or Quick Pick it belongs to.
const { filterSummary } = require('./search/request');

// What a stored card keeps. Chain IDs, categories and dietary hints stay
// behind; the person's origin is never part of a deck.
function storedCandidate(candidate) {
  return {
    id: candidate.id,
    order: candidate.order,
    name: candidate.name,
    address: candidate.address,
    distanceMeters: candidate.distanceMetersFromOrigin,
    cuisineIds: candidate.cuisineIds,
    openStatus: candidate.openStatus,
    phone: candidate.phone,
    website: candidate.website,
    // The restaurant's own position, for map links.
    latitude: candidate.latitude,
    longitude: candidate.longitude,
    provider: candidate.provider,
    providerPlaceId: candidate.providerPlaceId,
  };
}

// The winner or backup as the room keeps it after its deck is gone: enough to
// show the result and its links, nothing more.
function resultCard(candidate) {
  if (!candidate) return null;
  const { id, name, address, distanceMeters, latitude, longitude, phone, website } = candidate;
  return { id, name, address, distanceMeters, latitude, longitude, phone, website };
}

function deckDocument({ ownerUid, targetType, targetId, provider, result, request, built, seed, expiresAt,
  generatedAt }) {
  const candidates = built.candidates.map(storedCandidate);
  return {
    ownerUid,
    targetType,
    targetId,
    source: 'provider',
    provider: provider.id,
    providerVersion: provider.version,
    filterSummary: filterSummary(request),
    seed,
    candidateIds: candidates.map(candidate => candidate.id),
    candidates,
    pool: built.pool,
    providerCalls: result.providerCalls,
    attribution: result.attribution,
    generatedAt,
    expiresAt,
  };
}

module.exports = { deckDocument, storedCandidate, resultCard };

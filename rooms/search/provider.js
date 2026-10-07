// The RestaurantProvider contract. Room code depends only on this shape, never
// on a provider's own request or response objects.
//
// provider = {
//   id: string,                  // 'here', 'fake', ...
//   version: string,             // bumps when normalization changes
//   maxCallsPerSearch: number,   // worst case, reserved before searching
//   searchNearby(request, { correlationId }) -> Promise<ProviderSearchResult>
// }
//
// ProviderSearchResult = {
//   restaurants: NormalizedRestaurant[],
//   providerCalls: number,       // calls that reached the provider, failed or not
//   failedCalls: number,
//   attribution: string | null,  // text the provider's terms require us to show
// }
//
// A provider throws ProviderUnavailable when it could not produce a result;
// `providerCalls` on the error says how many calls still counted.

class ProviderUnavailable extends Error {
  constructor(message, { providerCalls = 0, cause } = {}) {
    super(message, { cause });
    this.providerCalls = providerCalls;
  }
}

const OPEN_STATUSES = ['open', 'closed', 'unknown'];

const text = (value, max) => {
  if (typeof value !== 'string') return null;
  const trimmed = value.replace(/\s+/g, ' ').trim();
  return trimmed ? trimmed.slice(0, max) : null;
};

// Builds a NormalizedRestaurant, dropping anything not in the contract and
// bounding text so one odd record cannot bloat a deck.
function normalizedRestaurant(fields) {
  const website = text(fields.website, 300);
  return {
    provider: fields.provider,
    providerPlaceId: String(fields.providerPlaceId ?? ''),
    name: text(fields.name, 120) ?? '',
    address: text(fields.address, 200),
    latitude: Number(fields.latitude),
    longitude: Number(fields.longitude),
    // Filled in by the deck builder from the person's origin.
    distanceMetersFromOrigin: null,
    cuisineIds: [...new Set(fields.cuisineIds ?? [])],
    categoryIds: [...new Set(fields.categoryIds ?? [])],
    dietaryHints: [...new Set(fields.dietaryHints ?? [])],
    openStatus: OPEN_STATUSES.includes(fields.openStatus) ? fields.openStatus : 'unknown',
    phone: text(fields.phone, 40),
    // Only web links; anything else from a provider is not a usable link.
    website: website && /^https?:\/\//i.test(website) ? website : null,
    chainId: text(fields.chainId, 80),
    attribution: text(fields.attribution, 200),
  };
}

function assertProvider(provider) {
  if (!provider || typeof provider.id !== 'string' || typeof provider.version !== 'string' ||
    !Number.isInteger(provider.maxCallsPerSearch) || provider.maxCallsPerSearch < 0 ||
    typeof provider.searchNearby !== 'function') {
    throw new Error('Not a RestaurantProvider.');
  }
  return provider;
}

module.exports = { normalizedRestaurant, assertProvider, ProviderUnavailable };

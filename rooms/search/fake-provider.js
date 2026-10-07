// Fictional restaurants placed around whatever origin is asked for, so the
// emulators and staging exercise the full deck pipeline without a real
// provider. Nothing here comes from or is sent to one.
const { normalizedRestaurant } = require('./provider');

// [name, cuisines, share of the radius away, bearing in degrees, extras]
const PLACES = [
  ['Demo Pizza', ['pizza', 'italian'], 0.05, 10, { chainId: 'demo-pizza-chain' }],
  ['Demo Pizza', ['pizza', 'italian'], 0.6, 200, { chainId: 'demo-pizza-chain' }],
  ['Demo Trattoria', ['italian'], 0.3, 45],
  ['Demo Tacos', ['mexican'], 0.1, 90],
  ['Demo Cantina', ['mexican'], 0.45, 300],
  ['Demo Noodle House', ['chinese'], 0.15, 135],
  ['Demo Dumplings', ['chinese'], 0.5, 170],
  ['Demo Sushi', ['japanese', 'seafood'], 0.2, 225],
  ['Demo Ramen', ['japanese'], 0.55, 250],
  ['Demo Thai Kitchen', ['thai'], 0.25, 270],
  ['Demo Pho', ['vietnamese'], 0.35, 315],
  ['Demo Curry', ['indian'], 0.4, 330],
  ['Demo Burger Bar', ['burgers', 'american'], 0.12, 20, { openStatus: 'closed' }],
  ['Demo Diner', ['american', 'breakfast'], 0.22, 60],
  ['Demo Smokehouse', ['bbq', 'american'], 0.65, 80],
  ['Demo Falafel', ['middle_eastern'], 0.3, 110],
  ['Demo Gyro', ['greek_mediterranean'], 0.42, 150],
  ['Demo Bistro', ['french'], 0.7, 190],
  ['Demo Fish Shack', ['seafood'], 0.75, 210],
  ['Demo Steakhouse', ['steakhouse'], 0.8, 240],
  ['Demo Deli', ['sandwiches'], 0.18, 280],
  ['Demo Chicken', ['chicken', 'fast_food'], 0.28, 340, { chainId: 'demo-chicken-chain' }],
  ['Demo Creamery', ['dessert'], 0.38, 5],
  ['Demo Kitchen', [], 0.33, 125, { openStatus: 'unknown' }],
  ['Demo Corner Cafe', [], 0.48, 260, { openStatus: 'unknown' }],
  // Just outside the circle, so the radius filter is always exercised.
  ['Demo Faraway Grill', ['american'], 1.15, 30],
];

function offset(origin, meters, bearingDegrees) {
  const bearing = (bearingDegrees * Math.PI) / 180;
  const dLat = (meters * Math.cos(bearing)) / 111320;
  const dLng = (meters * Math.sin(bearing)) / (111320 * Math.cos((origin.lat * Math.PI) / 180));
  return { lat: origin.lat + dLat, lng: origin.lng + dLng };
}

/**
 * @param {{simulatedCalls?: number}} options How many provider calls each search
 *   reports, so call budgets can be tested without a real provider.
 */
function createFakeProvider({ simulatedCalls = 1 } = {}) {
  return {
    id: 'fake',
    version: '1',
    maxCallsPerSearch: simulatedCalls,
    async searchNearby(request) {
      const restaurants = PLACES.map(([name, cuisineIds, share, bearing, extras = {}], index) => {
        const at = offset(request.origin, share * request.radiusMeters, bearing);
        return normalizedRestaurant({
          provider: 'fake',
          providerPlaceId: `fake-${String(index + 1).padStart(2, '0')}`,
          name,
          address: `${index + 1} Example Street`,
          latitude: at.lat,
          longitude: at.lng,
          cuisineIds,
          openStatus: 'open',
          ...extras,
        });
      });
      return { restaurants, providerCalls: simulatedCalls, failedCalls: 0, attribution: null };
    },
  };
}

module.exports = { createFakeProvider };

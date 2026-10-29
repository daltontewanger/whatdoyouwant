// Server-owned cuisine IDs. Clients may only send these; provider codes never
// reach the app. HERE codes come from its Places food types and categories:
// https://docs.here.com/geocoding-and-search/docs/food-types-category-system-full
//
// Each entry lists exact HERE food type IDs and/or whole regional families
// (the three-digit prefix, e.g. '201' covers every Chinese sub-style).
const CUISINES = Object.freeze({
  // Cuisines of a place or culture first, then kinds of food, each A to Z.
  african: { label: 'African', families: ['500', '501', '502', '503', '504', '505', '506'] },
  american: { label: 'American', families: ['101', '103'] },
  chinese: { label: 'Chinese', families: ['201'] },
  french: { label: 'French', families: ['301'] },
  greek_mediterranean: { label: 'Greek & Mediterranean', families: ['303', '372'] },
  indian: { label: 'Indian & South Asian', families: ['202', '208', '258'] },
  italian: { label: 'Italian', families: ['304', '315'] },
  japanese: { label: 'Japanese', families: ['203'] },
  korean: { label: 'Korean', families: ['207'] },
  latin_american: { label: 'Latin American & Caribbean', foodTypes: ['152-000', '153-000'], families: ['400', '401',
    '402', '403', '404', '405', '406', '407'] },
  mexican: { label: 'Mexican', families: ['102'], categories: ['100-1000-0005'] },
  middle_eastern: { label: 'Middle Eastern', families: ['250', '251', '252', '253', '254', '380', '382'],
    foodTypes: ['800-087'] },
  thai: { label: 'Thai', families: ['205'] },
  vietnamese: { label: 'Vietnamese', families: ['206'] },
  bbq: { label: 'BBQ', foodTypes: ['101-003'] },
  breakfast: { label: 'Breakfast & Brunch', foodTypes: ['800-061', '800-072'] },
  burgers: { label: 'Burgers', foodTypes: ['800-067'] },
  chicken: { label: 'Chicken', foodTypes: ['800-062', '203-031'] },
  dessert: { label: 'Dessert', foodTypes: ['800-063', '800-068', '800-069'] },
  fast_food: { label: 'Fast food', foodTypes: ['800-050'], categories: ['100-1000-0009'] },
  pizza: { label: 'Pizza', foodTypes: ['800-057'] },
  sandwiches: { label: 'Sandwiches & Deli', foodTypes: ['800-060'], categories: ['100-1000-0006'] },
  seafood: { label: 'Seafood', foodTypes: ['800-075', '203-010'] },
  steakhouse: { label: 'Steakhouse', foodTypes: ['800-056'] },
});

const CUISINE_IDS = Object.freeze(Object.keys(CUISINES));

// Collected for the benchmark only. These are never cuisine filters and never
// shown as dietary or allergy guarantees.
const DIETARY_HINTS = Object.freeze({ '800-076': 'vegan', '800-077': 'vegetarian', '800-086': 'halal',
  '800-079': 'kosher' });

const byFoodType = new Map();
const byFamily = new Map();
const byCategory = new Map();
for (const [id, cuisine] of Object.entries(CUISINES)) {
  for (const code of cuisine.foodTypes ?? []) byFoodType.set(code, [...(byFoodType.get(code) ?? []), id]);
  for (const code of cuisine.families ?? []) byFamily.set(code, [...(byFamily.get(code) ?? []), id]);
  for (const code of cuisine.categories ?? []) byCategory.set(code, [...(byCategory.get(code) ?? []), id]);
}

// Cuisine IDs for a set of HERE food type and category codes. An empty result
// means the cuisine is unknown, which is not the same as "not excluded".
function cuisinesFromHere(foodTypeIds = [], categoryIds = []) {
  const found = new Set();
  for (const code of foodTypeIds) {
    for (const id of byFoodType.get(code) ?? []) found.add(id);
    for (const id of byFamily.get(String(code).slice(0, 3)) ?? []) found.add(id);
  }
  for (const code of categoryIds) for (const id of byCategory.get(code) ?? []) found.add(id);
  return CUISINE_IDS.filter(id => found.has(id));
}

function dietaryHintsFromHere(foodTypeIds = []) {
  return [...new Set(foodTypeIds.map(code => DIETARY_HINTS[code]).filter(Boolean))].sort();
}

module.exports = { CUISINES, CUISINE_IDS, cuisinesFromHere, dietaryHintsFromHere };

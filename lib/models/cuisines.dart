/// A cuisine the host can ask for or rule out. The server owns the list
/// (`rooms/search/cuisines.js`) and rejects any other ID; a unit test keeps
/// this copy in step with it.
class Cuisine {
  const Cuisine(this.id, this.label);
  final String id;
  final String label;
}

const cuisines = [
  // Cuisines of a place or culture first, then kinds of food, each A to Z.
  Cuisine('african', 'African'),
  Cuisine('american', 'American'),
  Cuisine('chinese', 'Chinese'),
  Cuisine('french', 'French'),
  Cuisine('greek_mediterranean', 'Greek & Mediterranean'),
  Cuisine('indian', 'Indian & South Asian'),
  Cuisine('italian', 'Italian'),
  Cuisine('japanese', 'Japanese'),
  Cuisine('korean', 'Korean'),
  Cuisine('latin_american', 'Latin American & Caribbean'),
  Cuisine('mexican', 'Mexican'),
  Cuisine('middle_eastern', 'Middle Eastern'),
  Cuisine('thai', 'Thai'),
  Cuisine('vietnamese', 'Vietnamese'),
  Cuisine('bbq', 'BBQ'),
  Cuisine('breakfast', 'Breakfast & Brunch'),
  Cuisine('burgers', 'Burgers'),
  Cuisine('chicken', 'Chicken'),
  Cuisine('dessert', 'Dessert'),
  Cuisine('fast_food', 'Fast food'),
  Cuisine('pizza', 'Pizza'),
  Cuisine('sandwiches', 'Sandwiches & Deli'),
  Cuisine('seafood', 'Seafood'),
  Cuisine('steakhouse', 'Steakhouse'),
];

/// The server accepts at most this many cuisines on each list.
const maxCuisinesPerList = 8;

String cuisineLabel(String id) =>
    cuisines.firstWhere((c) => c.id == id, orElse: () => Cuisine(id, id)).label;

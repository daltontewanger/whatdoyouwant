import 'dart:math';
import '../models/restaurant.dart';

class LocationService {
  /// Filters restaurants within [radiusMiles] and returns a randomized subset
  /// of [maxOptions] restaurants.
  List<Restaurant> filterAndRandomizeRestaurants({
    required List<Restaurant> allRestaurants,
    required double radiusMiles,
    required int maxOptions,
  }) {
    // Filter restaurants to only those within the specified radius
    List<Restaurant> withinRadius = allRestaurants
        .where((restaurant) => restaurant.distance <= radiusMiles)
        .toList();

    // If there are fewer options than the max desired, return them all.
    if (withinRadius.length <= maxOptions) {
      return withinRadius;
    }

    // Randomize the list.
    withinRadius.shuffle(Random());

    // Return only the first [maxOptions] restaurants.
    return withinRadius.take(maxOptions).toList();
  }
}

import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';

class LocationService {
  /// Filters restaurants within [radiusMiles] and returns a randomized subset of [maxOptions] restaurants.
  static List<Restaurant> filterAndRandomizeRestaurants({
    required List<Restaurant> allRestaurants,
    required double radiusMiles,
    required int maxOptions,
  }) {
    // Filter restaurants to only those within the specified radius.
    List<Restaurant> withinRadius = allRestaurants
        .where((restaurant) => restaurant.distance <= radiusMiles)
        .toList();

    // If there are fewer options than desired, return them all.
    if (withinRadius.length <= maxOptions) {
      return withinRadius;
    }

    // Randomize the list.
    withinRadius.shuffle(Random());

    // Return only the first [maxOptions] restaurants.
    return withinRadius.take(maxOptions).toList();
  }

  /// Gets the current device location using the Geolocator package.
  static Future<Position> getCurrentLocation() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled.');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied.');
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception('Location permissions are permanently denied.');
  }

  // Use the locationSettings parameter instead of desiredAccuracy
  return await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}

  /// Simulates fetching nearby restaurants from an external API.
  /// In a real implementation, you might integrate with the Google Places API or Yelp Fusion.
  static Future<List<Restaurant>> fetchNearbyRestaurants(double radiusMiles) async {
    // Simulate network delay.
    await Future.delayed(const Duration(seconds: 2));

    // Generate dummy data.
    List<Restaurant> dummyList = [];
    int count = 20; // Simulate 20 nearby restaurants.
    Random random = Random();
    for (int i = 1; i <= count; i++) {
      // Randomly generate a distance up to slightly above the provided radius.
      double distance = random.nextDouble() * (radiusMiles + 5);
      dummyList.add(
        Restaurant(
          id: i.toString(),
          name: 'Restaurant $i',
          address: 'Address $i',
          rating: 3.0 + random.nextDouble() * 2, // Rating between 3.0 and 5.0.
          distance: distance,
        ),
      );
    }
    return dummyList;
  }
}

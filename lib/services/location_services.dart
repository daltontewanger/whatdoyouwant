import 'dart:math';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:geolocator/geolocator.dart';
import '../models/restaurant.dart';

class LocationService {
  /// Filters restaurants within [radiusMiles] and returns a randomized subset of [maxOptions] restaurants.
  /// Partitions the results into three distance buckets and selects a proportional number
  /// from each bucket. If a bucket doesn’t have enough items, it fills from the overall pool.
  static List<Restaurant> filterAndRandomizeRestaurants({
    required List<Restaurant> allRestaurants,
    required double radiusMiles,
    required int maxOptions,
  }) {
    // Filter to only consider restaurants within the selected radius.
    List<Restaurant> withinRadius =
        allRestaurants.where((r) => r.distance <= radiusMiles).toList();

    // If nothing is within the selected radius, return an empty list.
    if (withinRadius.isEmpty) return withinRadius;

    // If the selected radius is 3 miles or less, use all results within that range.
    if (radiusMiles <= 3) {
      withinRadius.shuffle(Random());
      return withinRadius.take(maxOptions).toList();
    }
    // If radius is > 3 but less than or equal to 8, partition into two buckets.
    else if (radiusMiles <= 8) {
      List<Restaurant> bucket1 =
          withinRadius.where((r) => r.distance <= 3).toList();
      List<Restaurant> bucket2 =
          withinRadius
              .where((r) => r.distance > 3 && r.distance <= radiusMiles)
              .toList();

      bucket1.shuffle(Random());
      bucket2.shuffle(Random());

      List<Restaurant> finalSelection = [];
      // Divide maxOptions equally among the two buckets.
      int perBucket = (maxOptions / 2).floor();

      finalSelection.addAll(bucket1.take(perBucket));
      finalSelection.addAll(bucket2.take(perBucket));

      // If there is any extra capacity, fill from all withinRadius.
      int extraNeeded = maxOptions - finalSelection.length;
      if (extraNeeded > 0) {
        withinRadius.shuffle(Random());
        finalSelection.addAll(withinRadius.take(extraNeeded));
      }

      finalSelection.shuffle(Random());
      return finalSelection.take(maxOptions).toList();
    }
    // If radius is greater than 8, partition into three buckets.
    else {
      List<Restaurant> bucket1 =
          withinRadius.where((r) => r.distance <= 3).toList();
      List<Restaurant> bucket2 =
          withinRadius.where((r) => r.distance > 3 && r.distance <= 8).toList();
      List<Restaurant> bucket3 =
          withinRadius
              .where((r) => r.distance > 8 && r.distance <= radiusMiles)
              .toList();

      bucket1.shuffle(Random());
      bucket2.shuffle(Random());
      bucket3.shuffle(Random());

      List<Restaurant> finalSelection = [];
      int perBucket = (maxOptions / 3).floor();

      finalSelection.addAll(bucket1.take(perBucket));
      finalSelection.addAll(bucket2.take(perBucket));
      finalSelection.addAll(bucket3.take(perBucket));

      // Fill any remaining slots from all withinRadius.
      int extraNeeded = maxOptions - finalSelection.length;
      if (extraNeeded > 0) {
        withinRadius.shuffle(Random());
        finalSelection.addAll(withinRadius.take(extraNeeded));
      }

      finalSelection.shuffle(Random());
      return finalSelection.take(maxOptions).toList();
    }
  }

  // Gets the current device location using the Geolocator package.
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

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Calls the Firebase backend, which handles HERE API requests, monthly usage limits,
  /// tile-based queries, duplicate removal, and HERE API key protection.
  static Future<List<Restaurant>> _fetchRestaurantsFromFirebase(
    double baseLat,
    double baseLon,
  ) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'fetchNearbyRestaurants',
      );

      final result = await callable.call({
        'baseLat': baseLat,
        'baseLon': baseLon,
      });

      final data = result.data;

      if (data == null || data is! Map) {
        throw Exception('Invalid response from Firebase restaurant function.');
      }

      final items = data['restaurants'];

      if (items == null || items is! List) {
        return [];
      }

      List<Restaurant> restaurants = [];

      for (var item in items) {
        if (item is! Map) continue;

        String id = item['id']?.toString() ?? '';
        String name = item['name']?.toString() ?? 'Unknown Restaurant';
        String address = item['address']?.toString() ?? 'Address not available';
        double distance = (item['distance'] as num?)?.toDouble() ?? 0.0;

        if (id.isEmpty || name.trim().isEmpty) continue;

        restaurants.add(
          Restaurant(
            id: id,
            name: name,
            address: address,
            distance: distance,
          ),
        );
      }

      return restaurants;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw Exception(
          'Monthly HERE API limit reached. Restaurant search is temporarily unavailable.',
        );
      }

      if (e.code == 'invalid-argument') {
        throw Exception('Invalid location data sent to restaurant search.');
      }

      throw Exception(
        'Failed to load restaurants from Firebase function: ${e.code} - ${e.message}',
      );
    } catch (e) {
      throw Exception('Failed to load restaurants: $e');
    }
  }

  /// Fetches nearby restaurants using the Firebase backend.
  /// The backend makes the tile-based HERE queries with slightly shifted center points
  /// and removes duplicates before returning the restaurant list.
  static Future<List<Restaurant>> fetchNearbyRestaurantsTiled({
    required double radiusMiles,
  }) async {
    // Get the current position.
    Position position = await getCurrentLocation();
    double baseLat = position.latitude;
    double baseLon = position.longitude;

    List<Restaurant> restaurants = await _fetchRestaurantsFromFirebase(
      baseLat,
      baseLon,
    );

    return restaurants.where((r) => r.distance <= radiusMiles).toList();
  }
}
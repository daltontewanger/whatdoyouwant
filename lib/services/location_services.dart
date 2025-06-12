import 'dart:math';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
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
    // Filter so that we only consider restaurants within the selected radius.
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

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Makes a single API call to fetch up to 100 restaurants for a given center coordinate.
  /// Uses limit=100
  static Future<List<Restaurant>> _fetchRestaurantsForCenterTiled(
    double centerLat,
    double centerLon,
  ) async {
    final url = Uri.https('discover.search.hereapi.com', '/v1/discover', {
      'at': '$centerLat,$centerLon',
      'q': 'restaurant',
      'limit': '100',
      'apiKey': dotenv.env['HERE_API_KEY'] ?? '',
    });

    final response = await http.get(url);
    List<Restaurant> restaurants = [];

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      List items = data['items'] ?? [];
      for (var item in items) {
        String id = item['id'];
        String name = item['title'];
        String address = item['address']?['label'] ?? 'Address not available';
        double distanceMeters = (item['distance'] as num?)?.toDouble() ?? 0.0;
        double distanceMiles = distanceMeters * 0.000621371;

        restaurants.add(
          Restaurant(
            id: id,
            name: name,
            address: address,
            distance: distanceMiles,
          ),
        );
      }
    } else {
      throw Exception(
        'Failed to load restaurants from HERE API: ${response.statusCode}',
      );
    }

    return restaurants;
  }

  /// Fetches nearby restaurants using tile-based queries.
  /// Make 4 API calls with slightly shifted center points (north, south, east, and west),
  /// each offset by approximately 5 miles from the user's location.
  /// Combines the results and removes duplicates by restaurant name,
  /// keeping only the closest result for each name.
  static Future<List<Restaurant>> fetchNearbyRestaurantsTiled({
    required double radiusMiles,
  }) async {
    // Get the current position.
    Position position = await getCurrentLocation();
    double baseLat = position.latitude;
    double baseLon = position.longitude;

    // For latitude, roughly 1 degree ~ 69 miles.
    double latOffset = 5.0 / 69.0; // ~5 miles offset in degrees.
    // For longitude, the degree distance depends on latitude.
    double lonOffset = 5.0 / (cos(baseLat * pi / 180) * 69.0);

    // Define four query centers for tiling: north, south, east, and west.
    List<Map<String, double>> centers = [
      {'lat': baseLat + latOffset, 'lon': baseLon}, // North
      {'lat': baseLat - latOffset, 'lon': baseLon}, // South
      {'lat': baseLat, 'lon': baseLon + lonOffset}, // East
      {'lat': baseLat, 'lon': baseLon - lonOffset}, // West
    ];

    List<Restaurant> aggregatedResults = [];

    // For each center, fetch results.
    for (var center in centers) {
      double queryLat = center['lat']!;
      double queryLon = center['lon']!;
      List<Restaurant> results = await _fetchRestaurantsForCenterTiled(
        queryLat,
        queryLon,
      );
      aggregatedResults.addAll(results);
    }

    // Remove duplicate results by restaurant name. If the same name exists at multiple locations,
    // keep only the entry with the smallest distance.
    Map<String, Restaurant> uniqueByName = {};
    for (var res in aggregatedResults) {
      String nameKey =
          res.name.toLowerCase(); // Lowercase to avoid case mismatches.
      if (uniqueByName.containsKey(nameKey)) {
        // Check if the new result is closer.
        if (res.distance < uniqueByName[nameKey]!.distance) {
          uniqueByName[nameKey] = res;
        }
      } else {
        uniqueByName[nameKey] = res;
      }
    }
    List<Restaurant> uniqueResults = uniqueByName.values.toList();

    return uniqueResults;
  }
}

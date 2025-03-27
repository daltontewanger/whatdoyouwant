import 'dart:math';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
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

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  /// Fetches nearby restaurants using the HERE Places (Discover) API.
  ///
  /// Steps:
  /// 1. Retrieve the user's current location.
  /// 2. Convert the search radius from miles to meters.
  /// 3. Build and call the HERE API URL using a circle query.
  /// 4. Parse the response into a list of Restaurant objects.
  static Future<List<Restaurant>> fetchNearbyRestaurants({
    required double radiusMiles,
  }) async {
    // Get the current position.
    Position position = await getCurrentLocation();
    double latitude = position.latitude;
    double longitude = position.longitude;

    // Build the HERE API URL.
    // The 'in' parameter restricts the search to a circle centered at the location.
    final url = Uri.https(
      'discover.search.hereapi.com',
      '/v1/discover',
      {
        'at': '$latitude,$longitude',
        'q': 'restaurant',
        'limit': '50', // Adjust limit as needed.
        'apiKey': dotenv.env['HERE_API_KEY'] ?? ''
      },
    );

    // Perform the HTTP GET request.
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      List<Restaurant> restaurants = [];
      // HERE API returns a list of items in the 'items' key.
      for (var item in data['items']) {
        String id = item['id'];
        String name = item['title'];
        // The address is provided in the 'address' object; 'label' holds the formatted address.
        String address = item['address']?['label'] ?? 'Address not available';
        // 'distance' is provided in meters; convert it to miles.
        double distanceMeters = (item['distance'] as num?)?.toDouble() ?? 0.0;
        double distanceMiles = distanceMeters * 0.000621371;
        // HERE API does not supply ratings, so default to 0.0.
        double rating = 0.0;

        restaurants.add(
          Restaurant(
            id: id,
            name: name,
            address: address,
            rating: rating,
            distance: distanceMiles,
          ),
        );
      }
      return restaurants;
    } else {
      throw Exception('Failed to load restaurants from HERE API: ${response.statusCode}');
    }
  }
}

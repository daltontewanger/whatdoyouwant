import '../models/restaurant.dart';

/// Where someone can go from a chosen restaurant.
///
/// Map and directions open HERE WeGo by default, since the listings come
/// from HERE. Directions can also open in another maps app the person
/// chooses; those links carry only the restaurant's position. Website and
/// phone are the restaurant's own.
class PlaceLinks {
  const PlaceLinks({
    this.map,
    this.directions,
    this.googleDirections,
    this.appleDirections,
    this.deviceMaps,
    this.website,
    this.phone,
  });

  final Uri? map;
  final Uri? directions;
  final Uri? googleDirections;
  final Uri? appleDirections;

  /// A `geo:` link, which Android hands to whichever maps app is the default.
  final Uri? deviceMaps;
  final Uri? website;
  final Uri? phone;

  bool get isEmpty =>
      map == null && directions == null && website == null && phone == null;
}

PlaceLinks placeLinksFor(Restaurant restaurant) {
  final lat = restaurant.latitude;
  final lng = restaurant.longitude;
  final hasPosition =
      lat != null &&
      lng != null &&
      lat.abs() <= 90 &&
      lng.abs() <= 180 &&
      (lat != 0 || lng != 0);
  Uri? map;
  Uri? directions;
  Uri? googleDirections;
  Uri? appleDirections;
  Uri? deviceMaps;
  if (hasPosition) {
    // HERE's share links take "lat,lng,title"; the title is encoded whole so
    // commas or slashes in a name cannot be read as more of the path.
    final title = Uri.encodeComponent(
      [
        restaurant.name,
        restaurant.address,
      ].where((part) => part.trim().isNotEmpty).join(', '),
    );
    final point = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},$title';
    map = Uri.parse('https://share.here.com/l/$point?z=17');
    directions = Uri.parse('https://share.here.com/r/mylocation/$point');
    final at = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    googleDirections = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': at,
    });
    appleDirections = Uri.https('maps.apple.com', '/', {'daddr': at});
    deviceMaps = Uri(scheme: 'geo', path: '0,0', query: 'q=$at');
  }
  return PlaceLinks(
    map: map,
    directions: directions,
    googleDirections: googleDirections,
    appleDirections: appleDirections,
    deviceMaps: deviceMaps,
    website: _webLink(restaurant.website),
    phone: _phoneLink(restaurant.phone),
  );
}

Uri? _webLink(String? value) {
  final uri = value == null ? null : Uri.tryParse(value.trim());
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return null;
  }
  return uri.host.isEmpty ? null : uri;
}

Uri? _phoneLink(String? value) {
  if (value == null) return null;
  final digits = value.replaceAll(RegExp(r'[^\d+]'), '');
  if (!RegExp(r'^\+?\d{7,15}$').hasMatch(digits)) return null;
  return Uri(scheme: 'tel', path: digits);
}

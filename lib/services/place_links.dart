import '../models/restaurant.dart';

/// Where someone can go from a chosen restaurant.
///
/// Map and directions links open HERE WeGo (HERE's own maps app or site):
/// restaurant data comes from HERE, whose terms do not allow handing it to a
/// competing map service. Website and phone are the restaurant's own.
class PlaceLinks {
  const PlaceLinks({this.map, this.directions, this.website, this.phone});

  final Uri? map;
  final Uri? directions;
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
  }
  return PlaceLinks(
    map: map,
    directions: directions,
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

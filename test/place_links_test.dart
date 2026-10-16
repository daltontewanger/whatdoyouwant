import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/services/place_links.dart';

Restaurant place({
  String name = 'Demo Pizza',
  String address = '1 Example Street, Exampleton',
  double? latitude = 38.5,
  double? longitude = -98.5,
  String? phone,
  String? website,
}) => Restaurant(
  id: 'c1',
  name: name,
  address: address,
  distance: 1,
  latitude: latitude,
  longitude: longitude,
  phone: phone,
  website: website,
);

void main() {
  test('map and directions open HERE WeGo at the restaurant', () {
    final links = placeLinksFor(place());
    expect(
      links.map.toString(),
      'https://share.here.com/l/38.500000,-98.500000,'
      'Demo%20Pizza%2C%201%20Example%20Street%2C%20Exampleton?z=17',
    );
    expect(
      links.directions.toString(),
      'https://share.here.com/r/mylocation/38.500000,-98.500000,'
      'Demo%20Pizza%2C%201%20Example%20Street%2C%20Exampleton',
    );
  });

  test('names cannot break out of the link path', () {
    final links = placeLinksFor(place(name: 'Tacos/Bar?x=1#top', address: ''));
    expect(
      links.map!.path,
      '/l/38.500000,-98.500000,Tacos%2FBar%3Fx%3D1%23top',
    );
    expect(links.map!.query, 'z=17');
    expect(links.map!.fragment, isEmpty);
  });

  test('no position, no map links; legacy cards get nothing', () {
    expect(placeLinksFor(place(latitude: null)).map, isNull);
    expect(placeLinksFor(place(latitude: 0, longitude: 0)).directions, isNull);
    expect(placeLinksFor(place(latitude: 120)).map, isNull);
    expect(
      placeLinksFor(
        Restaurant(id: 'x', name: 'Legacy', address: '', distance: 1),
      ).isEmpty,
      isTrue,
    );
  });

  test('only web links and plausible phone numbers are offered', () {
    expect(
      placeLinksFor(place(website: 'https://example.com/menu')).website,
      Uri.parse('https://example.com/menu'),
    );
    for (final bad in [
      'javascript:alert(1)',
      'ftp://example.com',
      'https://',
    ]) {
      expect(placeLinksFor(place(website: bad)).website, isNull, reason: bad);
    }
    expect(
      placeLinksFor(place(phone: '+1 (555) 010-0001')).phone.toString(),
      'tel:+15550100001',
    );
    expect(placeLinksFor(place(phone: 'call us')).phone, isNull);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/link.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/screens/place_card.dart';
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

  test('other maps apps get only the position', () {
    final links = placeLinksFor(place());
    expect(
      links.googleDirections.toString(),
      'https://www.google.com/maps/dir/?api=1&destination=38.500000%2C-98.500000',
    );
    expect(
      links.appleDirections.toString(),
      'https://maps.apple.com/?daddr=38.500000%2C-98.500000',
    );
    expect(links.deviceMaps.toString(), 'geo:0,0?q=38.500000,-98.500000');
    expect(placeLinksFor(place(latitude: null)).googleDirections, isNull);
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

  testWidgets(
    'every place action is a real link with only what the listing has',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceActions(
              links: placeLinksFor(
                place(
                  phone: '+1 555-010-0001',
                  website: 'https://demo.example',
                ),
              ),
            ),
          ),
        ),
      );
      final links = {
        for (final link in tester.widgetList<Link>(find.byType(Link)))
          link.uri!.scheme: link.target,
      };
      // Tests run as an app, where the phone handles every link itself.
      expect(links, {'https': LinkTarget.blank, 'tel': LinkTarget.blank});
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Website'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceActions(links: placeLinksFor(place(latitude: null))),
          ),
        ),
      );
      expect(
        find.text('This listing has no map or contact details.'),
        findsOneWidget,
      );
    },
  );

  for (final (platform, extra, missing) in [
    (TargetPlatform.android, "Your phone's maps app", 'Apple Maps'),
    (TargetPlatform.iOS, 'Apple Maps', "Your phone's maps app"),
  ]) {
    testWidgets('directions offer HERE WeGo first on ${platform.name}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PlaceActions(links: placeLinksFor(place()))),
        ),
      );
      await tester.tap(find.text('Directions'));
      await tester.pumpAndSettle();
      final titles = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data,
      ];
      expect(titles, ['HERE WeGo', 'Google Maps', extra]);
      expect(find.text(missing), findsNothing);
      expect(find.text('Default'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

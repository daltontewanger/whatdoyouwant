import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/services/device_location.dart';

Position at(double lat, double lng, DateTime timestamp) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: timestamp,
  accuracy: 50,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class FakeGeolocation extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  Position? lastKnown;
  Completer<Position>? next;
  final requests = <LocationSettings?>[];

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => lastKnown;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    requests.add(locationSettings);
    return (next = Completer<Position>()).future;
  }
}

void main() {
  final noon = DateTime(2026, 10, 8, 12);
  late FakeGeolocation geo;
  late DateTime now;
  DeviceLocator locator({bool isWeb = false}) =>
      DeviceLocator(platform: geo, clock: () => now, isWeb: isWeb);

  setUp(() {
    geo = FakeGeolocation();
    now = noon;
  });

  test('a recent fix is reused; an old one is replaced', () async {
    final device = locator();
    final first = device.locate();
    await pumpEventQueue();
    geo.next!.complete(at(38.5, -98.5, noon));
    expect(await first, (lat: 38.5, lng: -98.5));

    now = noon.add(const Duration(minutes: 9));
    expect(await device.locate(), (lat: 38.5, lng: -98.5));
    expect(geo.requests, hasLength(1), reason: 'no new fix within ten minutes');

    now = noon.add(const Duration(minutes: 11));
    final later = device.locate();
    await pumpEventQueue();
    geo.next!.complete(at(38.6, -98.4, now));
    expect(await later, (lat: 38.6, lng: -98.4));
    expect(geo.requests, hasLength(2));
  });

  test('requests running at once share one fix, with a time limit', () async {
    final device = locator();
    final both = Future.wait([device.locate(), device.locate()]);
    await pumpEventQueue();
    geo.next!.complete(at(1, 2, noon));
    expect(await both, [(lat: 1.0, lng: 2.0), (lat: 1.0, lng: 2.0)]);
    expect(geo.requests, hasLength(1));
    expect(geo.requests.single!.timeLimit, DeviceLocator.timeLimit);
    expect(geo.requests.single!.accuracy, LocationAccuracy.medium);
  });

  test('phones use a recent last-known position without a new fix', () async {
    geo.lastKnown = at(3, 4, noon.subtract(const Duration(minutes: 2)));
    expect(await locator().locate(), (lat: 3.0, lng: 4.0));
    expect(geo.requests, isEmpty);

    geo.lastKnown = at(3, 4, noon.subtract(const Duration(hours: 1)));
    final stale = locator().locate();
    await pumpEventQueue();
    expect(
      geo.requests,
      hasLength(1),
      reason: 'an hour-old position is not used',
    );
    geo.next!.complete(at(5, 6, noon));
    expect(await stale, (lat: 5.0, lng: 6.0));
  });

  test(
    'browsers may return their own position from the last ten minutes',
    () async {
      final device = locator(isWeb: true);
      final found = device.locate();
      await pumpEventQueue();
      final settings = geo.requests.single as WebSettings;
      expect(settings.maximumAge, DeviceLocator.maxAge);
      expect(settings.timeLimit, DeviceLocator.timeLimit);
      geo.next!.complete(at(7, 8, noon));
      await found;
    },
  );

  test(
    'warming up starts a fix only when permission is already granted',
    () async {
      geo.permission = LocationPermission.denied;
      final device = locator();
      await device.warmUp();
      await pumpEventQueue();
      expect(geo.requests, isEmpty, reason: 'never prompts from the lobby');

      geo.permission = LocationPermission.whileInUse;
      await device.warmUp();
      await pumpEventQueue();
      expect(geo.requests, hasLength(1));
      final start = device.locate();
      geo.next!.complete(at(9, 10, noon));
      expect(await start, (lat: 9.0, lng: 10.0));
      expect(geo.requests, hasLength(1), reason: 'Start reuses the lobby fix');
    },
  );

  test('a failed fix is not cached and can be retried', () async {
    final device = locator();
    final failed = device.locate();
    await pumpEventQueue();
    geo.next!.completeError(TimeoutException('slow'));
    await expectLater(failed, throwsA(isA<TimeoutException>()));
    final retry = device.locate();
    await pumpEventQueue();
    geo.next!.complete(at(1, 1, noon));
    expect(await retry, (lat: 1.0, lng: 1.0));
  });

  test('location failures read plainly when starting a room', () {
    expect(
      startRoomErrorMessage(TimeoutException('slow')),
      startsWith('Could not find your location in time.'),
    );
    expect(
      startRoomErrorMessage(const PermissionDeniedException('no')),
      startsWith('Location permission is required'),
    );
    expect(
      startRoomErrorMessage(const LocationServiceDisabledException()),
      startsWith('Location services are disabled.'),
    );
  });
}

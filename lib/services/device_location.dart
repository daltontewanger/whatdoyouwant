import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

typedef SearchOrigin = ({double lat, double lng});

/// Finds roughly where the device is for a restaurant search, without making
/// the host wait for a brand-new GPS fix each time.
///
/// A search only needs about 100 m of precision, so a position up to
/// [maxAge] old is reused, a fix can start in the background while the host
/// waits in the lobby ([warmUp]), and no request may run longer than
/// [timeLimit].
class DeviceLocator {
  DeviceLocator({
    GeolocatorPlatform? platform,
    DateTime Function()? clock,
    bool? isWeb,
  }) : _platform = platform ?? GeolocatorPlatform.instance,
       _clock = clock ?? DateTime.now,
       _isWeb = isWeb ?? kIsWeb;

  static const maxAge = Duration(minutes: 10);
  static const timeLimit = Duration(seconds: 12);

  final GeolocatorPlatform _platform;
  final DateTime Function() _clock;
  final bool _isWeb;
  Position? _last;
  Future<Position>? _pending;

  /// The device's position, reusing a recent one. Calls made while a request
  /// is already running share it.
  Future<SearchOrigin> locate() async {
    final position = _usable(_last) ?? await (_pending ??= _fix());
    return (lat: position.latitude, lng: position.longitude);
  }

  /// Starts finding the position early when permission is already granted.
  /// Never prompts: without permission, the prompt waits for Start.
  Future<void> warmUp() async {
    final permission = await _platform.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return;
    }
    // Errors surface when the host actually starts.
    unawaited(locate().then((_) {}, onError: (_) {}));
  }

  Position? _usable(Position? position) =>
      position != null && _clock().difference(position.timestamp) <= maxAge
          ? position
          : null;

  Future<Position> _fix() async {
    try {
      // Phones usually already know where they are; the web has no such call.
      if (!_isWeb) {
        try {
          final known = _usable(await _platform.getLastKnownPosition());
          if (known != null) return _last = known;
        } catch (_) {}
      }
      // Browsers can hand back their own recent fix when allowed to.
      final settings =
          _isWeb
              ? WebSettings(
                accuracy: LocationAccuracy.medium,
                maximumAge: maxAge,
                timeLimit: timeLimit,
              )
              : const LocationSettings(
                accuracy: LocationAccuracy.medium,
                timeLimit: timeLimit,
              );
      return _last = await _platform.getCurrentPosition(
        locationSettings: settings,
      );
    } finally {
      _pending = null;
    }
  }
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/live_search.dart';
import '../services/room_backend.dart';
import '../services/search_defaults.dart';
import 'search_setup_screen.dart';

/// Plain wording for a failed live search, or null when [error] is specific
/// to what was being started.
String? searchErrorMessage(Object error) {
  final limited = liveSearchErrorMessage(error);
  if (limited != null) return limited;
  if (error is TimeoutException) {
    return 'Could not find your location in time. Check that location is on, then try again.';
  }
  if (error is PermissionDeniedException) {
    return 'Location permission is required to find restaurants near you.';
  }
  if (error is LocationServiceDisabledException) {
    return 'Location services are disabled. Please enable them in settings.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'resource-exhausted':
        return 'Restaurant search is busy right now. Wait a minute and try again.';
      case 'failed-precondition':
        return 'Not enough restaurants nearby match. Try a wider distance.';
      case 'unavailable':
        return 'Restaurant search is unavailable right now. Try again in a minute.';
      case 'unauthenticated':
        return 'This device could not be verified. Restart the app and try again.';
    }
  }
  return null;
}

/// What a live search starts from, shared by the room lobby and Quick Pick:
/// the person's saved setup, this week's remaining searches, and location
/// permission asked for with an explanation first.
mixin SearchStarter<T extends StatefulWidget> on State<T> {
  SearchPreferences search = const SearchPreferences();
  LiveSearchAllowance? allowance;
  bool locationBlocked = false;

  /// The button that starts the search, as messages refer to it.
  String get startLabel;

  /// What one search costs, said after the remaining count.
  String get searchCostNote;

  /// Whether the setup offers a number of options.
  bool get choosesDeckSize => true;

  RoomBackend get backend => RoomBackendScope.of(context).backend;

  /// Opens with the saved setup and this week's remaining searches.
  Future<void> loadSearchSetup() async {
    final defaults = RoomBackendScope.of(context).searchDefaults;
    final refreshed = refreshAllowance();
    if (defaults != null) {
      search = defaults.current;
      final loaded = await defaults.load();
      if (mounted) setState(() => search = loaded);
    }
    await refreshed;
  }

  Future<void> refreshAllowance() async {
    final backend = this.backend;
    try {
      final remaining = await backend.liveSearchAllowance();
      if (mounted) setState(() => allowance = remaining);
    } catch (_) {
      // The server still enforces the limits when the search starts.
    }
  }

  Future<void> editSearch() async {
    final defaults = RoomBackendScope.of(context).searchDefaults;
    final chosen = await Navigator.push<SearchPreferences>(
      context,
      MaterialPageRoute(
        builder:
            (_) => SearchSetupScreen(
              initial: search,
              choosesDeckSize: choosesDeckSize,
            ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => search = chosen);
    await defaults?.save(chosen);
  }

  /// Live searches are switched off or used up for this week.
  bool get cannotSearch =>
      allowance != null && (allowance!.paused || allowance!.remaining <= 0);

  String? get allowanceText {
    final allowance = this.allowance;
    if (allowance == null) return null;
    if (allowance.paused) {
      return 'Live restaurant search is paused for now. Try again later.';
    }
    if (allowance.remaining <= 0) {
      return "You've used this week's live searches. More arrive ${resetTimeText(allowance.resetsAt)}.";
    }
    return '${allowance.remaining} of ${allowance.weeklyCap} live searches left this week. $searchCostNote';
  }

  /// Says what the location is for before the device or browser asks.
  Future<bool> _explainLocation() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Use your location?'),
            content: const Text(
              'To find restaurants near you, the app needs your location when '
              'you start. It is rounded to about 100 m, used only for this '
              'search, and never saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );
    return proceed == true;
  }

  /// Location permission for backends that search around the device. False
  /// when the search cannot go ahead; the reason is already on screen.
  Future<bool> locationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location services are disabled. Please enable them in settings.',
          ),
        ),
      );
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (!mounted) return false;
    if (permission == LocationPermission.denied) {
      if (!await _explainLocation()) return false;
      // On the web, asking for permission means taking a full location fix
      // just to learn the answer. The search's own request prompts instead.
      if (kIsWeb) return true;
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(
          () =>
              locationBlocked = permission == LocationPermission.deniedForever,
        );
      }
      return false;
    }
    if (mounted) setState(() => locationBlocked = false);
    return true;
  }

  /// A browser that blocks location only says so once the search asks. True
  /// when [error] was that, now shown as the blocked message.
  bool showBlockedLocation(Object error) {
    if (error is! PermissionDeniedException) return false;
    setState(() => locationBlocked = true);
    return true;
  }

  Widget searchPanel(ThemeData theme, {required bool busy}) {
    final allowance = allowanceText;
    final preferences = preferenceSummary(search);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Search', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          searchSummary(search, withDeckSize: choosesDeckSize),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge!.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          preferences ?? 'Any cuisine',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        TextButton.icon(
          icon: const Icon(Icons.tune),
          label: const Text('Change search'),
          onPressed: busy ? null : editSearch,
        ),
        if (allowance != null)
          Text(
            allowance,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall!.copyWith(color: Colors.grey[800]),
          ),
        if (locationBlocked)
          LocationBlocked(onWeb: kIsWeb, startLabel: startLabel),
      ],
    );
  }
}

/// Location is blocked for good, so only the person can turn it back on.
class LocationBlocked extends StatelessWidget {
  const LocationBlocked({
    super.key,
    required this.onWeb,
    required this.startLabel,
  });

  final bool onWeb;
  final String startLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1C9),
        border: Border.all(color: const Color(0xFFF7C948)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            onWeb
                ? "Location is blocked for this site. Allow it in your browser's site settings, then tap $startLabel again."
                : 'Location is off for this app. Allow it in Settings, then tap $startLabel again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF5A4300)),
          ),
          if (!onWeb)
            TextButton(
              onPressed: Geolocator.openAppSettings,
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }
}

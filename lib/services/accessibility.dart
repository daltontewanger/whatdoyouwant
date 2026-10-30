import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_backend.dart';

/// The person's own accessibility choices. Kept on this device only: they
/// describe how this person uses this phone, and nothing else needs them.
class AccessibilitySettings extends ChangeNotifier {
  static const _noTimerKey = 'accessibility.noTimer';

  /// Vote without the 15-second card timer.
  bool noTimer = false;

  Future<void> load() async {
    try {
      final saved =
          (await SharedPreferences.getInstance()).getBool(_noTimerKey) ?? false;
      if (saved != noTimer) {
        noTimer = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage can be unavailable, as in a private browser window.
    }
  }

  Future<void> setNoTimer(bool value) async {
    noTimer = value;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(_noTimerKey, value);
    } catch (_) {
      // Still applies for this visit.
    }
  }
}

/// Whether the device says a screen reader or switch control is in use.
/// Checked on the device only; it is never sent anywhere.
bool assistiveTechOn(BuildContext context) =>
    MediaQuery.accessibleNavigationOf(context);

/// Whether this person votes without a card timer: by their own choice, or
/// because their device uses a screen reader or switch control.
bool votesWithoutTimer(BuildContext context) =>
    (RoomBackendScope.maybeOf(context)?.accessibility?.noTimer ?? false) ||
    assistiveTechOn(context);

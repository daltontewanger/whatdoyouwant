import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_backend.dart';

/// Taps the server never sees on its own, counted as anonymous daily totals.
/// The names are a fixed list the server also checks; nothing about the
/// place, the room or the person goes with them.
enum UsageEvent {
  resultMap,
  resultDirections,
  resultWebsite,
  resultPhone,
  resultShare,
  ownResultMap,
  ownResultDirections,
  introFinished,
  introSkipped,
  demoStarted,
  signUpAfterDemo,
  quickPickChosen,
  joinWithCode,
  joinWithLink,
  shareRoomCode,
  openedFromSite,
}

/// The person's choice to send those counts, kept on this device. On unless
/// they turn it off in Account.
class UsageCounts extends ChangeNotifier {
  static const _offKey = 'usageCounts.off';
  static const _demoKey = 'usageCounts.demoSeen';

  bool enabled = true;
  bool _demoSeen = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = !(prefs.getBool(_offKey) ?? false);
      _demoSeen = prefs.getBool(_demoKey) ?? false;
      if (saved != enabled) {
        enabled = saved;
        notifyListeners();
      }
    } catch (_) {
      // Storage can be unavailable in a private window; the default stands.
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value == enabled) return;
    enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_offKey, !value);
    } catch (_) {}
  }

  /// Sends one count without waiting, and never lets a failure reach the
  /// person: a lost count matters far less than the tap it came from.
  void send(RoomBackend backend, UsageEvent event) {
    if (!enabled) return;
    unawaited(backend.countEvent(event.name).catchError((_) {}));
  }

  /// The demo was opened on this device, so a sign-up later can say so.
  Future<void> markDemoSeen() async {
    _demoSeen = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_demoKey, true);
    } catch (_) {}
  }

  /// Counts a sign-up that followed the demo, once per device.
  Future<void> signedUp(RoomBackend backend) async {
    if (!_demoSeen) return;
    send(backend, UsageEvent.signUpAfterDemo);
    _demoSeen = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_demoKey, false);
    } catch (_) {}
  }
}

/// Counts [event] for the screens' backend, unless the person turned counts
/// off or the screens are running the demo.
void countTap(BuildContext context, UsageEvent event) {
  final scope = context.getInheritedWidgetOfExactType<RoomBackendScope>();
  if (scope == null || scope.demo) return;
  scope.usageCounts?.send(scope.backend, event);
}

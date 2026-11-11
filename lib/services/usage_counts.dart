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

  bool enabled = true;

  // Only for this visit: nothing is stored on the device just to count.
  bool _demoSeen = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = !(prefs.getBool(_offKey) ?? false);
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

  /// The demo was opened during this visit, so a sign-up after it can say so.
  void markDemoSeen() => _demoSeen = true;

  /// Counts a sign-up that followed the demo in the same visit, once.
  Future<void> signedUp(RoomBackend backend) async {
    if (!_demoSeen) return;
    _demoSeen = false;
    send(backend, UsageEvent.signUpAfterDemo);
  }
}

/// Counts [event] for the screens' backend, unless the person turned counts
/// off or the screens are running the demo.
void countTap(BuildContext context, UsageEvent event) {
  final scope = context.getInheritedWidgetOfExactType<RoomBackendScope>();
  if (scope == null || scope.demo) return;
  scope.usageCounts?.send(scope.backend, event);
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_backend.dart';

/// The person's own accessibility choices. Kept on this device only: they
/// describe how this person uses this phone, and nothing else needs them.
class AccessibilitySettings extends ChangeNotifier {
  static const _noTimerKey = 'accessibility.noTimer';
  static const _textSizeKey = 'accessibility.textSize';

  /// The text sizes offered, as a share of the device's own size.
  static const minTextSize = 1.0;
  static const maxTextSize = 2.0;

  /// Vote without the 15-second card timer.
  bool noTimer = false;

  /// Text this many times the device's own size. A browser can't zoom the
  /// app and phones don't pass their text size to web pages, so this is
  /// the way to make the text bigger there.
  double textSize = minTextSize;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTimer = prefs.getBool(_noTimerKey) ?? false;
      final savedSize = (prefs.getDouble(_textSizeKey) ?? minTextSize).clamp(
        minTextSize,
        maxTextSize,
      );
      if (savedTimer != noTimer || savedSize != textSize) {
        noTimer = savedTimer;
        textSize = savedSize;
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

  Future<void> setTextSize(double value) async {
    textSize = value.clamp(minTextSize, maxTextSize);
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setDouble(
        _textSizeKey,
        textSize,
      );
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

/// Applies the chosen text size on top of the device's own, below every
/// screen of the app.
class AppTextSize extends StatelessWidget {
  const AppTextSize({super.key, required this.settings, required this.child});

  final AccessibilitySettings? settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final settings = this.settings;
    if (settings == null) return child;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        if (settings.textSize == AccessibilitySettings.minTextSize) {
          return child!;
        }
        return MediaQuery(
          data: media.copyWith(
            textScaler: _Times(media.textScaler, settings.textSize),
          ),
          child: child!,
        );
      },
      child: child,
    );
  }
}

class _Times extends TextScaler {
  const _Times(this.device, this.factor);

  final TextScaler device;
  final double factor;

  @override
  double scale(double fontSize) => device.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => device.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _Times && other.device == device && other.factor == factor;

  @override
  int get hashCode => Object.hash(device, factor);
}

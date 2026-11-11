import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'room_backend.dart';

/// The person's own accessibility choices. Kept on this device only: they
/// describe how this person uses this phone, and nothing else needs them.
class AccessibilitySettings extends ChangeNotifier {
  AccessibilitySettings({bool? web}) : web = web ?? kIsWeb;

  static const _noTimerKey = 'accessibility.noTimer';
  static const _textSizeKey = 'accessibility.textSize';

  /// The web page's hidden "Turn on screen reader support" link writes this
  /// too, as `flutter.accessibility.screenReader` in local storage.
  static const _screenReaderKey = 'accessibility.screenReader';

  /// Only the web app needs screen reader support turned on. Phones build
  /// what readers read on their own as soon as a reader starts.
  final bool web;

  /// The text sizes offered, as a share of the device's own size.
  static const minTextSize = 1.0;
  static const maxTextSize = 2.0;

  /// Vote without the 15-second card timer.
  bool noTimer = false;

  /// Text this many times the device's own size. A browser can't zoom the
  /// app and phones don't pass their text size to web pages, so this is
  /// the way to make the text bigger there.
  double textSize = minTextSize;

  /// Builds what screen readers read in the web app. Flutter leaves it off
  /// there unless asked, because keeping it up to date slows the app down,
  /// and its own hidden button for readers disappears after a few taps.
  bool screenReader = false;

  SemanticsHandle? _readerTree;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTimer = prefs.getBool(_noTimerKey) ?? false;
      final savedSize = (prefs.getDouble(_textSizeKey) ?? minTextSize).clamp(
        minTextSize,
        maxTextSize,
      );
      final savedReader = web && (prefs.getBool(_screenReaderKey) ?? false);
      if (savedTimer != noTimer ||
          savedSize != textSize ||
          savedReader != screenReader) {
        noTimer = savedTimer;
        textSize = savedSize;
        screenReader = savedReader;
        _applyScreenReader();
        notifyListeners();
      }
    } catch (_) {
      // Storage can be unavailable, as in a private browser window.
    }
  }

  Future<void> setScreenReader(bool value) async {
    if (!web) return;
    screenReader = value;
    _applyScreenReader();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_screenReaderKey, true);
      } else {
        await prefs.remove(_screenReaderKey);
      }
    } catch (_) {
      // Still applies for this visit.
    }
  }

  void _applyScreenReader() {
    if (screenReader) {
      _readerTree ??= SemanticsBinding.instance.ensureSemantics();
    } else {
      _readerTree?.dispose();
      _readerTree = null;
    }
  }

  @override
  void dispose() {
    _readerTree?.dispose();
    super.dispose();
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

/// Whether the device says a screen reader or switch control is in use. In
/// the web app that means screen reader support was turned on, by the person
/// or by their reader. Checked on the device only; it is never sent anywhere.
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

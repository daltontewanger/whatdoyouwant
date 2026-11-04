import 'package:shared_preferences/shared_preferences.dart';

/// Whether this device has already been shown the first-run intro. Kept on
/// the device only; a new phone or browser sees the intro once more.
abstract class IntroStore {
  Future<bool> seen();
  Future<void> markSeen();
}

class PreferencesIntroStore implements IntroStore {
  static const _key = 'introSeen';

  @override
  Future<bool> seen() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> markSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/own_spot.dart';

/// The room this device is taking part in, so the app can offer to return to
/// it after a restart. Membership itself lives on the server; this only
/// remembers which room to look at.
class ActiveRoom {
  const ActiveRoom(this.id, {required this.host, this.ownSpots});
  final String id;
  final bool host;

  /// The spots a host chose from their own list, which the server only learns
  /// when the room starts, so a lobby reopened after a restart keeps them.
  final List<OwnSpot>? ownSpots;
}

/// Notifies listeners whenever the remembered room changes, so screens in the
/// background (such as Home) stay current.
abstract class ActiveRoomStore extends ChangeNotifier {
  Future<ActiveRoom?> load();
  Future<void> remember(ActiveRoom room);
  Future<void> forget();
}

class PreferencesActiveRoomStore extends ActiveRoomStore {
  static const _id = 'activeRoomId';
  static const _host = 'activeRoomHost';
  static const _spots = 'activeRoomSpots';

  @override
  Future<ActiveRoom?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final id = preferences.getString(_id);
    if (id == null) return null;
    return ActiveRoom(
      id,
      host: preferences.getBool(_host) ?? false,
      ownSpots: _readSpots(preferences.getString(_spots)),
    );
  }

  static List<OwnSpot>? _readSpots(String? saved) {
    if (saved == null) return null;
    try {
      final raw = jsonDecode(saved);
      if (raw is! List) return null;
      final spots = raw.map(OwnSpot.fromJson).whereType<OwnSpot>().toList();
      return spots.isEmpty ? null : spots;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> remember(ActiveRoom room) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_id, room.id);
    await preferences.setBool(_host, room.host);
    final spots = room.ownSpots;
    if (spots == null) {
      await preferences.remove(_spots);
    } else {
      await preferences.setString(
        _spots,
        jsonEncode([for (final spot in spots) spot.toJson()]),
      );
    }
    notifyListeners();
  }

  @override
  Future<void> forget() async {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey(_id)) return;
    await preferences.remove(_id);
    await preferences.remove(_host);
    await preferences.remove(_spots);
    notifyListeners();
  }
}

class MemoryActiveRoomStore extends ActiveRoomStore {
  ActiveRoom? room;

  @override
  Future<ActiveRoom?> load() async => room;

  @override
  Future<void> remember(ActiveRoom room) async {
    this.room = room;
    notifyListeners();
  }

  @override
  Future<void> forget() async {
    if (room == null) return;
    room = null;
    notifyListeners();
  }
}

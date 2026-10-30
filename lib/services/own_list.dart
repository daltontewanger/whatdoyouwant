import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/own_spot.dart';

/// The person's own list of spots for We'll Decide What We Want.
/// [spots] is usable straight away and updates once [load] has run.
abstract class OwnListStore extends ChangeNotifier {
  List<OwnSpot> get spots;

  /// Spots from this device's guest list that did not fit in the account's
  /// list when they were merged. They stay on the device.
  List<OwnSpot> get leftOver;

  /// Whether the list is kept with an account, rather than on this device.
  bool get synced;

  Future<List<OwnSpot>> load();
  Future<void> save(List<OwnSpot> spots);

  /// Moves as many [leftOver] spots into the list as fit.
  Future<void> bringOverLeftOver();
}

class MemoryOwnList extends OwnListStore {
  MemoryOwnList([List<OwnSpot> spots = const []]) : spots = [...spots];

  @override
  List<OwnSpot> spots;
  @override
  List<OwnSpot> leftOver = [];
  @override
  bool synced = false;

  @override
  Future<List<OwnSpot>> load() async => spots;

  @override
  Future<void> save(List<OwnSpot> spots) async {
    this.spots = [...spots];
    notifyListeners();
  }

  @override
  Future<void> bringOverLeftOver() async {
    final (merged, left) = mergeSpots(spots, leftOver);
    spots = merged;
    leftOver = left;
    notifyListeners();
  }
}

/// Where a verified account's list lives on the server.
abstract class OwnListAccount {
  /// The signed-in account, when it is verified; null for guests and
  /// unverified accounts, whose list stays on the device.
  String? get verifiedUid;

  /// The account's list, or null when it has never saved one.
  Future<List<OwnSpot>?> read(String uid);
  Future<void> write(List<OwnSpot> spots);
}

class FirebaseOwnListAccount implements OwnListAccount {
  FirebaseOwnListAccount({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  String? get verifiedUid {
    final user = _auth.currentUser;
    return user != null && !user.isAnonymous && user.emailVerified
        ? user.uid
        : null;
  }

  @override
  Future<List<OwnSpot>?> read(String uid) async {
    final data = (await _db.doc('userLists/$uid').get()).data();
    if (data == null) return null;
    return spotsFrom(data['spots']);
  }

  // The server checks the size and lengths that rules cannot check per spot.
  @override
  Future<void> write(List<OwnSpot> spots) =>
      _functions.httpsCallable('saveOwnList').call({
        'spots': [for (final spot in spots) spot.toJson()],
      });
}

List<OwnSpot> spotsFrom(Object? raw) => [
  if (raw is List)
    for (final item in raw)
      if (OwnSpot.fromJson(item) case final spot?) spot,
];

/// Adds [extra] spots whose names are not already in [base], up to the
/// limit. Returns the merged list and the spots that did not fit.
(List<OwnSpot>, List<OwnSpot>) mergeSpots(
  List<OwnSpot> base,
  List<OwnSpot> extra,
) {
  final merged = [...base];
  final keys = {for (final spot in base) spot.matchKey};
  final left = <OwnSpot>[];
  for (final spot in extra) {
    if (!keys.add(spot.matchKey)) continue;
    if (merged.length < OwnSpot.maxSpots) {
      merged.add(spot);
    } else {
      left.add(spot);
    }
  }
  return (merged, left);
}

/// A guest's list on the device, and a verified account's list synced to the
/// server with a device copy for offline use. The two device copies are kept
/// apart, so signing out does not show the account's list to the next guest.
/// A guest list is merged into the account once, the first time the account
/// loads on this device.
class SyncedOwnList extends OwnListStore {
  SyncedOwnList({required this.account});

  final OwnListAccount account;

  static const _guestKey = 'ownList.guest';
  static const _accountKey = 'ownList.account';

  @override
  List<OwnSpot> spots = [];
  @override
  List<OwnSpot> leftOver = [];
  @override
  bool get synced => account.verifiedUid != null;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<OwnSpot>> _readGuest() async {
    final raw = (await _prefs).getString(_guestKey);
    try {
      return raw == null ? [] : spotsFrom(jsonDecode(raw));
    } on FormatException {
      return [];
    }
  }

  Future<void> _writeGuest(List<OwnSpot> spots) async {
    final prefs = await _prefs;
    if (spots.isEmpty) {
      await prefs.remove(_guestKey);
    } else {
      await prefs.setString(_guestKey, jsonEncode(spots));
    }
  }

  /// The account copy on this device: which account, its spots, and
  /// whether it holds edits the server has not taken yet.
  Future<(String?, List<OwnSpot>, bool)> _readAccountCopy() async {
    final raw = (await _prefs).getString(_accountKey);
    try {
      final data = raw == null ? null : jsonDecode(raw);
      if (data is Map && data['uid'] is String) {
        return (
          data['uid'] as String,
          spotsFrom(data['spots']),
          data['pending'] == true,
        );
      }
    } on FormatException {
      // Treated as no copy.
    }
    return (null, <OwnSpot>[], false);
  }

  Future<void> _writeAccountCopy(
    String uid,
    List<OwnSpot> spots, {
    bool pending = false,
  }) async => (await _prefs).setString(
    _accountKey,
    jsonEncode({'uid': uid, 'spots': spots, 'pending': pending}),
  );

  void _show(List<OwnSpot> next, List<OwnSpot> left) {
    final changed = !listEquals(next, spots) || !listEquals(left, leftOver);
    spots = next;
    leftOver = left;
    if (changed) notifyListeners();
  }

  @override
  Future<List<OwnSpot>> load() async {
    final guest = await _readGuest();
    final uid = account.verifiedUid;
    if (uid == null) {
      _show(guest, const []);
      return spots;
    }
    final (copyUid, copy, pending) = await _readAccountCopy();
    var current = copyUid == uid ? copy : <OwnSpot>[];
    _show(current, guest);
    try {
      // Edits made offline go up first, so the older server copy does not
      // replace them.
      if (copyUid == uid && pending) {
        await account.write(current);
      } else {
        current = await account.read(uid) ?? current;
      }
    } catch (_) {
      // Offline: the device copy still works.
      return spots;
    }
    if (guest.isNotEmpty) {
      final (merged, left) = mergeSpots(current, guest);
      if (merged.length != current.length) {
        try {
          await account.write(merged);
          current = merged;
          await _writeGuest(left);
          _show(current, left);
        } catch (_) {
          // Merged next time instead.
        }
      }
    }
    await _writeAccountCopy(uid, current);
    _show(current, await _readGuest());
    return spots;
  }

  @override
  Future<void> save(List<OwnSpot> next) async {
    final uid = account.verifiedUid;
    if (uid == null) {
      await _writeGuest(next);
      _show(next, const []);
      return;
    }
    _show(next, leftOver);
    await _writeAccountCopy(uid, next, pending: true);
    await account.write(next);
    await _writeAccountCopy(uid, next);
  }

  @override
  Future<void> bringOverLeftOver() async {
    final (merged, left) = mergeSpots(spots, leftOver);
    await save(merged);
    await _writeGuest(left);
    _show(merged, left);
  }
}

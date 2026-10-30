import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/restaurant.dart';
import '../models/saved_place.dart';

/// A list already holds [MyPlaces.maxPlaces] places.
class ListFull implements Exception {
  const ListFull(this.never);
  final bool never;

  @override
  String toString() =>
      'Your "${never ? 'Never what I want' : 'I know what I want'}" list is full. Remove some in Account to add more.';
}

/// The person's favorites ("I know what I want") and never list ("Never
/// what I want"). [places] is usable straight away and updates once [load]
/// has run.
abstract class MyPlacesStore extends ChangeNotifier {
  MyPlacesStore({DateTime Function()? now}) : now = now ?? DateTime.now;

  final DateTime Function() now;

  MyPlaces get places;

  /// Whether the lists are kept with an account, rather than on this device.
  bool get synced;

  Future<MyPlaces> load();
  Future<void> save(MyPlaces places);

  bool isFavorite(String id) => places.favorites.any((p) => p.id == id);
  bool isNever(String id) => places.never.any((p) => p.id == id);

  /// Saves [restaurant] as a favorite, taking it off the never list.
  Future<void> addFavorite(Restaurant restaurant) {
    final current = places;
    if (isFavorite(restaurant.id)) return seen([restaurant]);
    if (current.favorites.length >= MyPlaces.maxPlaces) {
      throw const ListFull(false);
    }
    return save(
      current.copyWith(
        favorites: [
          SavedPlace.favorite(restaurant, now()),
          ...current.favorites,
        ],
        never: current.never.where((p) => p.id != restaurant.id).toList(),
      ),
    );
  }

  /// Puts [restaurant] on the never list, taking it off the favorites.
  Future<void> addNever(Restaurant restaurant) async {
    final current = places;
    if (isNever(restaurant.id)) return;
    if (current.never.length >= MyPlaces.maxPlaces) throw const ListFull(true);
    await save(
      current.copyWith(
        never: [SavedPlace.never(restaurant), ...current.never],
        favorites:
            current.favorites.where((p) => p.id != restaurant.id).toList(),
      ),
    );
  }

  Future<void> remove(String id) => save(
    places.copyWith(
      favorites: places.favorites.where((p) => p.id != id).toList(),
      never: places.never.where((p) => p.id != id).toList(),
    ),
  );

  /// Puts a place back as it was before an add, for Undo.
  Future<void> restore(MyPlaces before) => save(before);

  /// Refreshes the details of any favorites among [restaurants], which just
  /// turned up in a new deck, in one save. Each at most once a day.
  Future<void> seen(Iterable<Restaurant> restaurants) async {
    final at = now().millisecondsSinceEpoch;
    final fresh = {
      for (final restaurant in restaurants)
        if (SavedPlace.canSave(restaurant)) restaurant.id: restaurant,
    };
    bool stale(SavedPlace place, Restaurant restaurant) =>
        place.seenAt == null ||
        at - place.seenAt! >= const Duration(days: 1).inMilliseconds ||
        place.name != restaurant.name;
    var changed = false;
    final favorites = [...places.favorites];
    for (var i = 0; i < favorites.length; i++) {
      final restaurant = fresh[favorites[i].id];
      if (restaurant == null || !stale(favorites[i], restaurant)) continue;
      favorites[i] = SavedPlace.favorite(restaurant, now());
      changed = true;
    }
    if (changed) await save(places.copyWith(favorites: favorites));
  }
}

class MemoryMyPlaces extends MyPlacesStore {
  MemoryMyPlaces([this.places = const MyPlaces(), DateTime Function()? now])
    : super(now: now);

  @override
  MyPlaces places;
  @override
  bool synced = false;
  int saves = 0;

  @override
  Future<MyPlaces> load() async => places;

  @override
  Future<void> save(MyPlaces places) async {
    saves++;
    this.places = places;
    notifyListeners();
  }
}

/// Where a verified account's lists live on the server.
abstract class MyPlacesAccount {
  /// The signed-in account, when it is verified; null for guests and
  /// unverified accounts, whose lists stay on the device.
  String? get verifiedUid;

  /// Whether a guest session is signed in, as after signing out. False while
  /// the app is still restoring a session at start.
  bool get isGuest;

  /// Fires whenever someone signs in or out.
  Stream<void> get changes;

  /// The account's lists, or null when it has never saved any.
  Future<MyPlaces?> read(String uid);
  Future<void> write(MyPlaces places);
}

class FirebaseMyPlacesAccount implements MyPlacesAccount {
  FirebaseMyPlacesAccount({
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
  bool get isGuest => _auth.currentUser?.isAnonymous == true;

  @override
  Stream<void> get changes => _auth.authStateChanges();

  @override
  Future<MyPlaces?> read(String uid) async {
    final data = (await _db.doc('userPlaces/$uid').get()).data();
    return data == null ? null : MyPlaces.fromJson(data);
  }

  // The server checks every entry, since rules cannot.
  @override
  Future<void> write(MyPlaces places) =>
      _functions.httpsCallable('saveMyPlaces').call(places.toJson());
}

/// Lists for guests on the device and for verified accounts on the server,
/// with a device copy so they work offline. A guest's lists are merged into
/// the account the first time it loads here; signing out removes the
/// account's copy from the device.
class SyncedMyPlaces extends MyPlacesStore {
  SyncedMyPlaces({required this.account, super.now}) {
    _changes = account.changes.listen((_) => load().catchError((_) => places));
  }

  final MyPlacesAccount account;
  late final StreamSubscription<void> _changes;

  static const _guestKey = 'myPlaces.guest';
  static const _accountKey = 'myPlaces.account';

  @override
  MyPlaces places = const MyPlaces();
  @override
  bool get synced => account.verifiedUid != null;

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<MyPlaces> _readGuest() async {
    final raw = (await _prefs).getString(_guestKey);
    try {
      return raw == null
          ? const MyPlaces()
          : MyPlaces.fromJson(jsonDecode(raw)).current(now());
    } on FormatException {
      return const MyPlaces();
    }
  }

  Future<void> _writeGuest(MyPlaces places) async {
    final prefs = await _prefs;
    if (places.isEmpty && places.useFavorites && places.useNever) {
      await prefs.remove(_guestKey);
    } else {
      await prefs.setString(_guestKey, jsonEncode(places.toJson()));
    }
  }

  /// The account copy on this device: which account, its lists, and whether
  /// it holds edits the server has not taken yet.
  Future<(String?, MyPlaces, bool)> _readAccountCopy() async {
    final raw = (await _prefs).getString(_accountKey);
    try {
      final data = raw == null ? null : jsonDecode(raw);
      if (data is Map && data['uid'] is String) {
        return (
          data['uid'] as String,
          MyPlaces.fromJson(data['places']).current(now()),
          data['pending'] == true,
        );
      }
    } on FormatException {
      // Treated as no copy.
    }
    return (null, const MyPlaces(), false);
  }

  Future<void> _writeAccountCopy(
    String uid,
    MyPlaces places, {
    bool pending = false,
  }) async => (await _prefs).setString(
    _accountKey,
    jsonEncode({'uid': uid, 'places': places.toJson(), 'pending': pending}),
  );

  void _show(MyPlaces next) {
    if (next == places) return;
    places = next;
    notifyListeners();
  }

  @override
  Future<MyPlaces> load() async {
    final guest = await _readGuest();
    final uid = account.verifiedUid;
    if (uid == null) {
      // Signed out: the account's lists leave this device with it, along
      // with any edits that never reached the server.
      if (account.isGuest) await (await _prefs).remove(_accountKey);
      _show(guest);
      return places;
    }
    final (copyUid, copy, pending) = await _readAccountCopy();
    var current = copyUid == uid ? copy : const MyPlaces();
    _show(current);
    try {
      // Edits made offline go up first, so the older server copy does not
      // replace them.
      if (copyUid == uid && pending) {
        await account.write(current);
      } else {
        current = (await account.read(uid))?.current(now()) ?? current;
      }
    } catch (_) {
      // Offline: the device copy still works.
      return places;
    }
    if (!guest.isEmpty) {
      final merged = current.merged(guest);
      try {
        if (merged != current) await account.write(merged);
        current = merged;
        await _writeGuest(const MyPlaces());
      } catch (_) {
        // Merged next time instead.
      }
    }
    await _writeAccountCopy(uid, current);
    _show(current);
    return places;
  }

  @override
  Future<void> save(MyPlaces next) async {
    final uid = account.verifiedUid;
    _show(next);
    if (uid == null) {
      await _writeGuest(next);
      return;
    }
    await _writeAccountCopy(uid, next, pending: true);
    await account.write(next);
    await _writeAccountCopy(uid, next);
  }
}

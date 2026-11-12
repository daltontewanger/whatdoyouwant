import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cuisines.dart';

enum DistanceUnit {
  mi('mi', 1609.344),
  km('km', 1000);

  const DistanceUnit(this.label, this.meters);
  final String label;
  final double meters;
}

const _metersPerMile = 1609.344;

/// A card's distance in the person's unit. Cards carry miles.
String distanceText(double miles, DistanceUnit unit) {
  final value = miles * _metersPerMile / unit.meters;
  final digits =
      value < 1
          ? 2
          : value < 10
          ? 1
          : 0;
  return '${value.toStringAsFixed(digits)} ${unit.label}';
}

/// What a search asks for, apart from where it starts. The same values the
/// server's search contract accepts; never a location.
@immutable
class SearchPreferences {
  const SearchPreferences({
    this.unit = DistanceUnit.mi,
    this.radius = 5,
    this.deckSize = 10,
    this.includedCuisineIds = const [],
    this.excludedCuisineIds = const [],
    this.openNowPreferred = false,
  });

  static const radiusChoices = [1, 3, 5, 10, 15];
  static const deckSizes = [5, 10, 15, 25];

  final DistanceUnit unit;

  /// In [unit]; one of [radiusChoices].
  final int radius;
  final int deckSize;

  /// Ranked first when the listing says so; not a guarantee.
  final List<String> includedCuisineIds;

  /// Left out when the listing positively says so.
  final List<String> excludedCuisineIds;
  final bool openNowPreferred;

  SearchPreferences copyWith({
    DistanceUnit? unit,
    int? radius,
    int? deckSize,
    List<String>? includedCuisineIds,
    List<String>? excludedCuisineIds,
    bool? openNowPreferred,
  }) => SearchPreferences(
    unit: unit ?? this.unit,
    radius: radius ?? this.radius,
    deckSize: deckSize ?? this.deckSize,
    includedCuisineIds: includedCuisineIds ?? this.includedCuisineIds,
    excludedCuisineIds: excludedCuisineIds ?? this.excludedCuisineIds,
    openNowPreferred: openNowPreferred ?? this.openNowPreferred,
  );

  Map<String, Object> toJson() => {
    'unit': unit.label,
    'radius': radius,
    'deckSize': deckSize,
    'includedCuisineIds': includedCuisineIds,
    'excludedCuisineIds': excludedCuisineIds,
    'openNowPreferred': openNowPreferred,
  };

  /// Reads stored defaults. Saved values can predate a change to the offered
  /// choices, so anything no longer offered falls back to the default rather
  /// than failing the search later.
  factory SearchPreferences.fromJson(Map<String, dynamic>? raw) {
    const fallback = SearchPreferences();
    if (raw == null) return fallback;
    List<String> known(Object? value) {
      if (value is! List) return const [];
      final ids = <String>{
        for (final id in value)
          if (id is String && cuisines.any((c) => c.id == id)) id,
      };
      return ids.take(maxCuisinesPerList).toList();
    }

    final included = known(raw['includedCuisineIds']);
    final radius = raw['radius'];
    final deckSize = raw['deckSize'];
    return SearchPreferences(
      unit: DistanceUnit.values.firstWhere(
        (u) => u.label == raw['unit'],
        orElse: () => fallback.unit,
      ),
      radius:
          radius is num && radiusChoices.contains(radius)
              ? radius.toInt()
              : fallback.radius,
      deckSize:
          deckSize is num && deckSizes.contains(deckSize)
              ? deckSize.toInt()
              : fallback.deckSize,
      includedCuisineIds: included,
      excludedCuisineIds:
          known(
            raw['excludedCuisineIds'],
          ).where((id) => !included.contains(id)).toList(),
      openNowPreferred: raw['openNowPreferred'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchPreferences &&
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// A five-digit US ZIP code, the only kind the server can search around.
bool isZipCode(String value) => RegExp(r'^\d{5}$').hasMatch(value);

/// The setup a person last used, so the next search starts from it.
/// [current] is usable straight away and updates once [load] has run.
abstract class SearchDefaultsStore extends ChangeNotifier {
  SearchPreferences get current;
  Future<SearchPreferences> load();
  Future<void> save(SearchPreferences preferences);

  /// A ZIP code to search around instead of the device location, or null
  /// for the device. Kept only while the app runs: it is never saved with
  /// the defaults, so it is forgotten when the app closes.
  String? get zip => _zip;
  String? _zip;
  set zip(String? value) {
    if (value == _zip) return;
    _zip = value;
    notifyListeners();
  }
}

class MemorySearchDefaults extends SearchDefaultsStore {
  MemorySearchDefaults([this.current = const SearchPreferences()]);

  @override
  SearchPreferences current;
  int saves = 0;

  @override
  Future<SearchPreferences> load() async => current;

  @override
  Future<void> save(SearchPreferences preferences) async {
    saves++;
    current = preferences;
    notifyListeners();
  }
}

/// Defaults kept on this device only. Holds the guest's setup.
class DeviceSearchDefaults extends SearchDefaultsStore {
  DeviceSearchDefaults({this.key = 'searchDefaults.guest'});

  final String key;

  @override
  SearchPreferences current = const SearchPreferences();

  /// Whether anything was ever saved here, as opposed to the built-in default.
  bool saved = false;

  @override
  Future<SearchPreferences> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    saved = raw != null;
    current = decodePreferences(raw);
    return current;
  }

  @override
  Future<void> save(SearchPreferences preferences) async {
    current = preferences;
    saved = true;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(preferences.toJson()),
    );
  }
}

SearchPreferences decodePreferences(String? raw) {
  if (raw == null) return const SearchPreferences();
  try {
    return SearchPreferences.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  } on FormatException {
    return const SearchPreferences();
  } on TypeError {
    return const SearchPreferences();
  }
}

/// Where a verified account's defaults live on the server.
abstract class AccountSettings {
  /// The signed-in account, when it is verified; null for guests and
  /// unverified accounts, whose defaults stay on the device.
  String? get verifiedUid;

  /// Nobody is signed in to an account (a guest, or no session yet).
  bool get isGuest;

  /// Fires when someone signs in or out.
  Stream<void> get changes;
  Future<Map<String, dynamic>?> read(String uid);
  Future<void> write(String uid, Map<String, Object> fields);
}

class FirestoreAccountSettings implements AccountSettings {
  FirestoreAccountSettings({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  @override
  String? get verifiedUid {
    final user = _auth.currentUser;
    return user != null && !user.isAnonymous && user.emailVerified
        ? user.uid
        : null;
  }

  @override
  bool get isGuest => _auth.currentUser?.isAnonymous ?? true;

  @override
  Stream<void> get changes => _auth.authStateChanges();

  @override
  Future<Map<String, dynamic>?> read(String uid) async =>
      (await _db.doc('userSettings/$uid').get()).data();

  @override
  Future<void> write(String uid, Map<String, Object> fields) => _db
      .doc('userSettings/$uid')
      .set({...fields, 'updatedAt': FieldValue.serverTimestamp()});
}

/// Defaults that follow a verified account between devices. The device keeps
/// two copies apart, like the lists: the guest's own setup, and the signed-in
/// account's copy marked with whose it is, so one account's setup never shows
/// for another. A guest's setup is carried into an account that has none yet
/// (someone who just signed up keeps what they chose). The most recent save
/// wins, and signing in or out reloads.
class AccountSearchDefaults extends SearchDefaultsStore {
  AccountSearchDefaults({required this.device, required this.account}) {
    _changes = account.changes.listen((_) => load().catchError((_) => current));
  }

  /// The guest's setup on this device.
  final DeviceSearchDefaults device;
  final AccountSettings account;
  late final StreamSubscription<void> _changes;

  static const _accountKey = 'searchDefaults.account';
  // Before the copies were kept apart, one shared copy lived here.
  static const _legacyKey = 'searchDefaults';

  SearchPreferences _current = const SearchPreferences();

  @override
  SearchPreferences get current => _current;

  @override
  void dispose() {
    _changes.cancel();
    super.dispose();
  }

  void _show(SearchPreferences preferences) {
    if (preferences == _current) return;
    _current = preferences;
    notifyListeners();
  }

  Future<(String?, SearchPreferences)> _readAccountCopy() async {
    final raw = (await SharedPreferences.getInstance()).getString(_accountKey);
    if (raw == null) return (null, const SearchPreferences());
    try {
      final data = jsonDecode(raw);
      if (data is Map && data['uid'] is String && data['preferences'] is Map) {
        return (
          data['uid'] as String,
          SearchPreferences.fromJson(
            Map<String, dynamic>.from(data['preferences'] as Map),
          ),
        );
      }
    } on FormatException {
      // Unreadable: treated as no copy.
    }
    return (null, const SearchPreferences());
  }

  Future<void> _writeAccountCopy(
    String uid,
    SearchPreferences preferences,
  ) async => (await SharedPreferences.getInstance()).setString(
    _accountKey,
    jsonEncode({'uid': uid, 'preferences': preferences.toJson()}),
  );

  // The old shared copy belongs to whoever is signed in when the update
  // arrives; with nobody signed in to an account it becomes the guest's.
  Future<void> _migrate(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
    if (raw == null) return;
    if (uid != null) {
      await _writeAccountCopy(uid, decodePreferences(raw));
    } else if (!prefs.containsKey(device.key)) {
      await prefs.setString(device.key, raw);
    }
    await prefs.remove(_legacyKey);
  }

  @override
  Future<SearchPreferences> load() async {
    final uid = account.verifiedUid;
    await _migrate(uid);
    final guest = await device.load();
    if (uid == null) {
      // Signed out: the account's copy leaves this device with it.
      if (account.isGuest) {
        await (await SharedPreferences.getInstance()).remove(_accountKey);
      }
      _show(guest);
      return _current;
    }
    final (copyUid, copy) = await _readAccountCopy();
    var mine = copyUid == uid ? copy : const SearchPreferences();
    _show(mine);
    try {
      final stored = await account.read(uid);
      if (stored != null) {
        mine = SearchPreferences.fromJson(stored);
      } else if (copyUid != uid && device.saved) {
        // A guest who just signed up brings the setup they already used.
        mine = guest;
        final carried = guest.toJson();
        unawaited(Future(() => account.write(uid, carried)).catchError((_) {}));
      }
    } catch (_) {
      // Offline or not yet allowed: the device copy still works.
    }
    await _writeAccountCopy(uid, mine);
    _show(mine);
    return _current;
  }

  @override
  Future<void> save(SearchPreferences preferences) async {
    final uid = account.verifiedUid;
    if (uid == null) {
      await device.save(preferences);
      _show(preferences);
      return;
    }
    _show(preferences);
    await _writeAccountCopy(uid, preferences);
    // Not awaited: an offline Firestore write only completes once it reaches
    // the server, and starting a search should not wait for that. A failed
    // write leaves the device copy, and the next save tries again.
    unawaited(
      Future(() => account.write(uid, preferences.toJson())).catchError((_) {}),
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/own_spot.dart';
import '../models/restaurant.dart';
import 'device_location.dart';
import 'live_search.dart';
import 'lobby_backstop.dart';
import 'room_backend.dart';
import 'search_defaults.dart';
import 'site_links.dart';

export 'device_location.dart' show SearchOrigin;

/// Turns what someone typed into a join request: a six-character join code for
/// new members, or the longer room ID that existing members reconnect with.
Map<String, String>? joinRequestFor(String typed) {
  final cleaned = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (RegExp(r'^[A-HJKMNP-Z2-9]{6}$').hasMatch(cleaned)) {
    return {'joinCode': cleaned};
  }
  if (RegExp(r'^[A-F0-9]{24}$').hasMatch(cleaned)) return {'roomId': cleaned};
  return null;
}

/// Thrown for input that cannot be a join code, before contacting the server.
class InvalidJoinCode implements Exception {
  @override
  String toString() =>
      'Enter the 6-character code shown on the host\'s screen.';
}

const _metersPerMile = 1609.344;

/// The search the server's startRoom expects. The location is rounded to
/// about 100 m first: plenty for a search measured in miles, and less
/// precise than where the person actually is. A [zip] code is sent instead
/// of a location, and the server searches around its centre.
Map<String, Object?> startSearchFor(
  SearchOrigin? origin,
  SearchPreferences search, {
  String? zip,
}) => {
  'origin':
      zip != null
          ? {'zip': zip}
          : {
            'lat': double.parse(origin!.lat.toStringAsFixed(3)),
            'lng': double.parse(origin.lng.toStringAsFixed(3)),
          },
  'radius': {'value': search.radius, 'unit': search.unit.label},
  'deckSize': search.deckSize,
  'includedCuisineIds': search.includedCuisineIds,
  'excludedCuisineIds': search.excludedCuisineIds,
  'openNowPreferred': search.openNowPreferred,
};

/// One card as the server stores it, in a deck or a room's results. Cards keep
/// meters; the app works in miles and shows the person's own unit.
Restaurant cardRestaurant(Map raw) => Restaurant(
  id: raw['id'] as String,
  name: raw['name'] as String,
  address: (raw['address'] as String?) ?? '',
  distance: ((raw['distanceMeters'] as num?) ?? 0) / _metersPerMile,
  latitude: (raw['latitude'] as num?)?.toDouble(),
  longitude: (raw['longitude'] as num?)?.toDouble(),
  phone: raw['phone'] as String?,
  website: raw['website'] as String?,
  userEntered: raw['userEntered'] == true,
  note: raw['note'] as String?,
);

/// The cards of a stored deck, in deck order.
List<Restaurant> deckRestaurants(Map<String, dynamic> deck) => [
  for (final raw in deck['candidates'] as List) cardRestaurant(raw as Map),
];

RoomResults? callableResults(Object? raw, int members) {
  if (raw is! Map) return null;
  final likes = <String, int>{
    for (final entry in Map<String, dynamic>.from(raw['likes'] as Map).entries)
      entry.key: (entry.value as num).toInt(),
  };
  final winnerCard = raw['winnerCard'];
  final backupCard = raw['backupCard'];
  return RoomResults(
    winnerId: raw['winner'] as String?,
    backupId: raw['backup'] as String?,
    likes: likes,
    participants: members,
    winnerCard: winnerCard is Map ? cardRestaurant(winnerCard) : null,
    backupCard: backupCard is Map ? cardRestaurant(backupCard) : null,
  );
}

/// Rooms managed by the server-side room callables. The server owns
/// membership, the deck and results; clients only write their own ballots.
class CallableRoomBackend implements RoomBackend {
  CallableRoomBackend({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    Future<SearchOrigin> Function()? locate,
    DeviceLocator? locator,
    this.usesFictionalRestaurants = false,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _locator = locator ?? DeviceLocator(),
       _fixedLocate = locate;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final DeviceLocator _locator;
  final Future<SearchOrigin> Function()? _fixedLocate;

  Future<SearchOrigin> _locate() => _fixedLocate?.call() ?? _locator.locate();
  final _expiries = <String, Timestamp>{};

  String get _uid => _auth.currentUser!.uid;

  @override
  bool get usesDeviceLocation => true;
  // Only the local emulators deal decks from the server's fake provider.
  @override
  final bool usesFictionalRestaurants;
  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, Object?> data,
  ) async {
    final result = await _functions.httpsCallable(name).call(data);
    return Map<String, dynamic>.from(result.data as Map);
  }

  @override
  Future<CreatedRoom> createRoom() async {
    final result = await _call('createRoom', {'requestId': const Uuid().v4()});
    return CreatedRoom(
      result['roomId'] as String,
      result['joinCode'] as String,
    );
  }

  @override
  Future<String> joinRoom(String typedCode) async {
    final request = joinRequestFor(typedCode);
    if (request == null) throw InvalidJoinCode();
    return (await _call('joinRoom', request))['roomId'] as String;
  }

  @override
  Stream<RoomState> watch(String roomId) {
    final room = _db.doc('rooms/$roomId');
    late final StreamController<RoomState> controller;
    final subscriptions = <StreamSubscription<Object?>>[];
    Map<String, dynamic>? roomData;
    var deck = <Restaurant>[];
    var myVotes = <String>{};
    var deckRequested = false;

    void emit() {
      final data = roomData;
      if (data == null || controller.isClosed) return;
      final status = data['status'] as String;
      final members = (data['memberCount'] as num?)?.toInt() ?? 1;
      controller.add(
        RoomState(
          id: roomId,
          joinCode: data['joinCode'] as String?,
          creatorId: data['creator'] as String,
          status: status,
          memberCount: members,
          restaurants: deck,
          myVoteCount: myVotes.length,
          votedIds: myVotes,
          resultsReady: status == 'closed',
          results: callableResults(data['results'], members),
          votingEndsAt: (data['votingEndsAt'] as Timestamp?)?.toDate(),
        ),
      );
    }

    // Decks never change once stored, so one read is enough.
    void loadDeck(String deckId) {
      if (deckRequested) return;
      deckRequested = true;
      _db
          .doc('restaurantDecks/$deckId')
          .get()
          .then((snapshot) {
            final stored = snapshot.data();
            if (stored != null) deck = deckRestaurants(stored);
            emit();
          })
          .catchError((Object error) {
            if (!controller.isClosed) controller.addError(error);
          });
    }

    late final LobbyBackstop backstop;
    void apply(Map<String, dynamic>? data) {
      roomData = data;
      if (data == null) return;
      // The host starts the room, so only guests can be left behind waiting.
      if (data['status'] == 'lobby' && data['creator'] != _uid) {
        backstop.start();
      } else {
        backstop.stop();
      }
      _expiries[roomId] = data['expiresAt'] as Timestamp;
      final deckId = data['deckId'] as String?;
      // A closed room's deck is removed soon after; its results carry
      // the winner and backup instead.
      if (deckId != null && data['status'] != 'closed') loadDeck(deckId);
      emit();
    }

    backstop = LobbyBackstop(
      status:
          () async =>
              (await _call('roomResults', {'roomId': roomId}))['status']
                  as String,
      // Reconnecting makes Firestore resend the room as it is now.
      onBehind: () async {
        await _db.disableNetwork();
        await _db.enableNetwork();
      },
    );

    controller = StreamController<RoomState>(
      onListen: () {
        subscriptions.add(
          room.snapshots().listen(
            (snapshot) => apply(snapshot.data()),
            onError: controller.addError,
          ),
        );
        subscriptions.add(
          room.collection('votes/$_uid/ballot').snapshots().listen((snapshot) {
            myVotes = {for (final doc in snapshot.docs) doc.id};
            emit();
          }, onError: controller.addError),
        );
      },
      onCancel: () async {
        backstop.stop();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
    String? zip,
    DeckLists lists = DeckLists.none,
  }) async {
    final origin = zip == null ? await _locate() : null;
    final started = await _call('startRoom', {
      'roomId': roomId,
      'search': startSearchFor(origin, search, zip: zip),
      'lists': lists.toJson(),
    });
    // A fresh start returns its cards; a repeat start points at the stored deck.
    if (started['candidates'] is List) return deckRestaurants(started);
    final deck = await _db.doc('restaurantDecks/${started['deckId']}').get();
    return deckRestaurants(deck.data()!);
  }

  @override
  Future<void> shareLists(
    String roomId, {
    required List<String> favorites,
    required List<String> never,
  }) => _call('shareRoomLists', {
    'roomId': roomId,
    'favorites': favorites,
    'never': never,
  });

  @override
  Future<List<Restaurant>> startFromList(
    String roomId,
    List<OwnSpot> spots,
  ) async {
    final started = await _call('startRoomFromList', {
      'roomId': roomId,
      'spots': [for (final spot in spots) spot.toJson()],
    });
    if (started['candidates'] is List) return deckRestaurants(started);
    final deck = await _db.doc('restaurantDecks/${started['deckId']}').get();
    return deckRestaurants(deck.data()!);
  }

  Future<Timestamp> _expiryOf(String roomId) async {
    final known = _expiries[roomId];
    if (known != null) return known;
    final room = await _db.doc('rooms/$roomId').get();
    return _expiries[roomId] = room.data()!['expiresAt'] as Timestamp;
  }

  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  }) async {
    // Ballots carry the room's expiry so they are cleaned up with it.
    await _db.doc('rooms/$roomId/votes/$_uid/ballot/${restaurant.id}').set({
      'liked': liked,
      'at': FieldValue.serverTimestamp(),
      'expiresAt': await _expiryOf(roomId),
    });
  }

  @override
  Future<void> nudge(String roomId) async {
    // Closes the room on the server once everyone has voted or time is up.
    await _call('roomResults', {'roomId': roomId});
  }

  // Finds the location while the host waits for guests, so Start does not.
  @override
  Future<void> prepareStart() async {
    if (_fixedLocate == null) await _locator.warmUp();
  }

  String get _siteOrigin => siteOrigin(
    _functions.app.options.projectId,
    current: kIsWeb ? Uri.base : null,
  );

  @override
  Uri? joinLinkFor(String joinCode) => joinLink(_siteOrigin, joinCode);

  @override
  Uri sitePage(String path) => sitePageLink(_siteOrigin, path);

  @override
  Future<bool> updateRequired(int build) async =>
      (await _call('appStatus', {'build': build}))['updateRequired'] == true;

  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async =>
      LiveSearchAllowance.fromCallable(await _call('liveSearchStatus', {}));

  @override
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  }) async {
    final origin = zip == null ? await _locate() : null;
    final view = await _call('createQuickPick', {
      'requestId': requestId,
      'search': startSearchFor(origin, search, zip: zip),
    });
    final deck = await _db.doc('restaurantDecks/${view['deckId']}').get();
    return quickPickFrom(view, {
      for (final card in deckRestaurants(deck.data()!)) card.id: card,
    });
  }

  @override
  Future<QuickPick> rerollQuickPick(QuickPick pick) async {
    // `from` is the card on screen, so a retried reroll cannot skip one.
    final view = await _call('rerollQuickPick', {
      'quickPickId': pick.id,
      'from': pick.position,
    });
    return quickPickFrom(view, pick.cards);
  }
}

/// A Quick Pick as the server reports it, with the deck's cards.
QuickPick quickPickFrom(
  Map<String, dynamic> view,
  Map<String, Restaurant> cards,
) => QuickPick(
  id: view['quickPickId'] as String,
  position: (view['position'] as num).toInt(),
  restaurant: cards[view['candidateId']]!,
  rerollsLeft: (view['rerollsLeft'] as num).toInt(),
  cards: cards,
);

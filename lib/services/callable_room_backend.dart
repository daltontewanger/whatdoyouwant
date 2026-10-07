import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/restaurant.dart';
import 'room_backend.dart';

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

typedef SearchOrigin = ({double lat, double lng});

/// The search the server's startRoom expects. The location is rounded to
/// about 100 m first: plenty for a search measured in miles, and less
/// precise than where the person actually is.
Map<String, Object?> startSearchFor(
  SearchOrigin origin, {
  required double radiusMiles,
  required int deckSize,
}) => {
  'origin': {
    'lat': double.parse(origin.lat.toStringAsFixed(3)),
    'lng': double.parse(origin.lng.toStringAsFixed(3)),
  },
  'radius': {'value': radiusMiles.round(), 'unit': 'mi'},
  'deckSize': deckSize,
};

/// The cards of a stored deck, in deck order. Decks keep meters; the app
/// still shows miles.
List<Restaurant> deckRestaurants(Map<String, dynamic> deck) => [
  for (final raw in deck['candidates'] as List)
    Restaurant(
      id: (raw as Map)['id'] as String,
      name: raw['name'] as String,
      address: (raw['address'] as String?) ?? '',
      distance: ((raw['distanceMeters'] as num?) ?? 0) / _metersPerMile,
      latitude: (raw['latitude'] as num?)?.toDouble(),
      longitude: (raw['longitude'] as num?)?.toDouble(),
      phone: raw['phone'] as String?,
      website: raw['website'] as String?,
    ),
];

Future<SearchOrigin> _deviceLocation() async {
  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
  );
  return (lat: position.latitude, lng: position.longitude);
}

RoomResults? callableResults(Object? raw, int members) {
  if (raw is! Map) return null;
  final likes = <String, int>{
    for (final entry in Map<String, dynamic>.from(raw['likes'] as Map).entries)
      entry.key: (entry.value as num).toInt(),
  };
  return RoomResults(
    winnerId: raw['winner'] as String?,
    backupId: raw['backup'] as String?,
    likes: likes,
    participants: members,
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
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _locate = locate ?? _deviceLocation;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final Future<SearchOrigin> Function() _locate;
  final _expiries = <String, Timestamp>{};

  String get _uid => _auth.currentUser!.uid;

  @override
  bool get requiresVerifiedHost => true;
  @override
  bool get usesDeviceLocation => true;
  // Local and staging decks come from the server's fake provider for now.
  @override
  bool get usesFictionalRestaurants => true;
  @override
  bool get clientClosesRooms => false;

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
            deck = deckRestaurants(snapshot.data()!);
            emit();
          })
          .catchError((Object error) {
            if (!controller.isClosed) controller.addError(error);
          });
    }

    controller = StreamController<RoomState>(
      onListen: () {
        subscriptions.add(
          room.snapshots().listen((snapshot) {
            roomData = snapshot.data();
            final data = roomData;
            if (data == null) return;
            _expiries[roomId] = data['expiresAt'] as Timestamp;
            final deckId = data['deckId'] as String?;
            if (deckId != null) loadDeck(deckId);
            emit();
          }, onError: controller.addError),
        );
        subscriptions.add(
          room.collection('votes/$_uid/ballot').snapshots().listen((snapshot) {
            myVotes = {for (final doc in snapshot.docs) doc.id};
            emit();
          }, onError: controller.addError),
        );
      },
      onCancel: () async {
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
    required double radiusMiles,
    required int maxOptions,
  }) async {
    final origin = await _locate();
    final started = await _call('startRoom', {
      'roomId': roomId,
      'search': startSearchFor(
        origin,
        radiusMiles: radiusMiles,
        deckSize: maxOptions,
      ),
    });
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

  @override
  Future<void> close(String roomId) async {
    await _call('closeRoom', {'roomId': roomId});
  }
}

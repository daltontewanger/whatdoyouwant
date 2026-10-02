import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

Restaurant candidateRestaurant(String id, Map<String, dynamic> data) =>
    Restaurant(
      id: id,
      name: data['title'] as String,
      address: (data['address'] as String?) ?? '',
      distance: (data['distanceMiles'] as num?)?.toDouble() ?? 0,
    );

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
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final _expiries = <String, Timestamp>{};

  String get _uid => _auth.currentUser!.uid;

  @override
  bool get requiresVerifiedHost => true;
  @override
  bool get usesDeviceLocation => false;
  @override
  bool get clientClosesRooms => false;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, String> data,
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
    var myVotes = 0;
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
          myVoteCount: myVotes,
          resultsReady: status == 'closed',
          results: callableResults(data['results'], members),
        ),
      );
    }

    void listenToDeck() {
      if (deckRequested) return;
      deckRequested = true;
      subscriptions.add(
        room.collection('candidates').orderBy('order').snapshots().listen((
          snapshot,
        ) {
          deck = [
            for (final doc in snapshot.docs)
              candidateRestaurant(doc.id, doc.data()),
          ];
          emit();
        }, onError: controller.addError),
      );
    }

    controller = StreamController<RoomState>(
      onListen: () {
        subscriptions.add(
          room.snapshots().listen((snapshot) {
            roomData = snapshot.data();
            final data = roomData;
            if (data == null) return;
            _expiries[roomId] = data['expiresAt'] as Timestamp;
            if (data['status'] != 'lobby') listenToDeck();
            emit();
          }, onError: controller.addError),
        );
        subscriptions.add(
          room.collection('votes/$_uid/ballot').snapshots().listen((snapshot) {
            myVotes = snapshot.size;
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
    // Search settings are not sent yet: the deck is fixed fictional data until
    // a reviewed restaurant provider exists, and no location is ever sent.
    await _call('startRoom', {'roomId': roomId});
    final deck =
        await _db.collection('rooms/$roomId/candidates').orderBy('order').get();
    return [
      for (final doc in deck.docs) candidateRestaurant(doc.id, doc.data()),
    ];
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

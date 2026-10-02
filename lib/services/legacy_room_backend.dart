import 'package:firebase_auth/firebase_auth.dart';

import '../models/restaurant.dart';
import 'location_services.dart';
import 'room_backend.dart';
import 'room_service.dart';

/// The original rooms: clients write the room document directly and work out
/// results themselves. Production still runs on this until its migration.
class LegacyRoomBackend implements RoomBackend {
  LegacyRoomBackend({RoomService? rooms, FirebaseAuth? auth})
    : _rooms = rooms ?? RoomService(),
      _auth = auth ?? FirebaseAuth.instance;

  final RoomService _rooms;
  final FirebaseAuth _auth;

  String get _uid => _auth.currentUser?.uid ?? 'guest';

  @override
  bool get requiresVerifiedHost => false;
  @override
  bool get usesDeviceLocation => true;
  @override
  bool get clientClosesRooms => true;

  @override
  Future<CreatedRoom> createRoom() async {
    final code = await _rooms.createRoom(_uid);
    return CreatedRoom(code, code);
  }

  @override
  Future<String> joinRoom(String typedCode) async {
    final code = typedCode.trim().toUpperCase();
    await _rooms.joinRoom(code, _uid);
    return code;
  }

  @override
  Stream<RoomState> watch(String roomId) => _rooms
      .roomStream(roomId)
      .where((snapshot) => snapshot.exists)
      .map(
        (snapshot) => legacyRoomState(
          roomId,
          snapshot.data() as Map<String, dynamic>,
          _uid,
        ),
      );

  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required double radiusMiles,
    required int maxOptions,
  }) async {
    final fetched = await LocationService.fetchNearbyRestaurantsTiled(
      radiusMiles: radiusMiles,
    );
    final deck = LocationService.filterAndRandomizeRestaurants(
      allRestaurants: fetched,
      radiusMiles: radiusMiles,
      maxOptions: maxOptions,
    );
    await _rooms.setRoomOptionsAndStart(
      roomCode: roomId,
      radius: radiusMiles,
      maxOptions: maxOptions,
      options: deck,
    );
    return deck;
  }

  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  }) => _rooms.submitIncrementalVote(
    roomCode: roomId,
    userId: _uid,
    restaurantId: restaurant.id,
    liked: liked,
    currentIndex: index,
    totalCount: total,
  );

  @override
  Future<void> nudge(String roomId) =>
      _rooms.timeoutStaleByVote(roomCode: roomId);

  @override
  Future<void> close(String roomId) => _rooms.closeRoom(roomId);
}

int _asInt(Object? value, int fallback) => value is int ? value : fallback;

/// Reads the original room document. Kept free of Firebase calls for tests.
RoomState legacyRoomState(String code, Map<String, dynamic> data, String uid) {
  final participants = Map<String, dynamic>.from(data['participants'] ?? {});
  final votes = Map<String, dynamic>.from(data['votes'] ?? {});
  final stats = Map<String, dynamic>.from(data['stats'] ?? {});
  final restaurants =
      List<dynamic>.from(data['restaurants'] ?? const [])
          .map((r) => Restaurant.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
  final status = (data['status'] ?? 'closed') as String;
  final participantsCount = _asInt(
    stats['participantsCount'],
    participants.length,
  );
  final restaurantsCount = _asInt(
    stats['restaurantsCount'],
    restaurants.length,
  );
  int votesOf(String id) =>
      Map<String, dynamic>.from((votes[id] as Map?) ?? {}).length;

  var doneCount = _asInt(stats['doneCount'], 0);
  if (doneCount == 0 && participantsCount > 0 && restaurantsCount > 0) {
    doneCount =
        participants.keys.where((id) => votesOf(id) >= restaurantsCount).length;
  }
  final waiting =
      status == 'voting' &&
      participantsCount > 0 &&
      restaurantsCount > 0 &&
      doneCount < participantsCount;
  final everyoneDone =
      participants.isNotEmpty &&
      restaurants.isNotEmpty &&
      participants.keys.every((id) => votesOf(id) >= restaurants.length);

  return RoomState(
    id: code,
    joinCode: code,
    creatorId: (data['creator'] ?? '') as String,
    status: status,
    memberCount: participants.length,
    restaurants: restaurants,
    myVoteCount: votesOf(uid),
    everyoneDone: everyoneDone,
    resultsReady: !waiting,
    remainingVoters: waiting ? participantsCount - doneCount : null,
    results: legacyResults(votes, restaurants, participantsCount),
  );
}

/// Most likes wins; ties, or no likes at all, go to the closest restaurant.
RoomResults? legacyResults(
  Map<String, dynamic> votes,
  List<Restaurant> restaurants,
  int participants,
) {
  final likes = <String, int>{};
  votes.forEach((_, userVotes) {
    if (userVotes is Map) {
      userVotes.forEach((restaurantId, liked) {
        if (liked == true) {
          likes[restaurantId as String] = (likes[restaurantId] ?? 0) + 1;
        }
      });
    }
  });
  final byId = {for (final r in restaurants) r.id: r};
  List<Restaurant> closestFirst(List<Restaurant> list) =>
      [...list]..sort((a, b) => a.distance.compareTo(b.distance));

  Restaurant? winner;
  var winnerVotes = 0;
  if (likes.isEmpty) {
    if (restaurants.isNotEmpty) winner = closestFirst(restaurants).first;
  } else {
    final top = likes.values.reduce((a, b) => a > b ? a : b);
    final topIds = [
      for (final entry in likes.entries)
        if (entry.value == top) entry.key,
    ];
    if (topIds.length == 1) {
      winner = byId[topIds.first];
      winnerVotes = top;
    } else {
      final tied = [
        for (final id in topIds)
          if (byId[id] != null) byId[id]!,
      ];
      final pool = tied.isNotEmpty ? tied : restaurants;
      if (pool.isNotEmpty) {
        winner = closestFirst(pool).first;
        winnerVotes = likes[winner.id] ?? top;
      }
    }
  }
  if (winner == null) return null;
  return RoomResults(
    winnerId: winner.id,
    likes: likes,
    participants: participants,
    winnerVotes: winnerVotes,
  );
}

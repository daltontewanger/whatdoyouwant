import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

class FakeRoomBackend implements RoomBackend {
  FakeRoomBackend({this.clientClosesRooms = false});

  final room = StreamController<RoomState>.broadcast();
  final joined = <String>[];
  int closes = 0;

  @override
  final bool clientClosesRooms;
  @override
  bool get requiresVerifiedHost => true;
  @override
  bool get usesDeviceLocation => false;

  @override
  Future<String> joinRoom(String typedCode) async {
    joined.add(typedCode);
    return 'ROOM-ID';
  }

  @override
  Stream<RoomState> watch(String roomId) => room.stream;
  @override
  Future<void> nudge(String roomId) async {}
  @override
  Future<void> close(String roomId) async => closes++;
  @override
  Future<CreatedRoom> createRoom() => throw UnimplementedError();
  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required double radiusMiles,
    required int maxOptions,
  }) => throw UnimplementedError();
  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  }) async {}
}

final deck = [
  Restaurant(id: 'a', name: 'Demo Pizza', address: '1 Example', distance: 0.25),
  Restaurant(id: 'b', name: 'Demo Tacos', address: '2 Example', distance: 0.5),
];

RoomState state({
  String status = 'voting',
  bool ready = false,
  int? remaining,
  RoomResults? results,
}) => RoomState(
  id: 'ROOM-ID',
  joinCode: null,
  creatorId: 'host',
  status: status,
  memberCount: 3,
  restaurants: deck,
  myVoteCount: 2,
  resultsReady: ready,
  remainingVoters: remaining,
  results: results,
);

Widget app(FakeRoomBackend backend, Widget home) =>
    RoomBackendScope(backend: backend, child: MaterialApp(home: home));

void main() {
  testWidgets('a guest joins by code, waits, then reaches the deck', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(
        backend,
        JoinRoomScreen(currentUser: AppUser(id: 'guest', name: 'Guest')),
      ),
    );
    await tester.enterText(find.byType(TextField), 'ab3k7x');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
    // The waiting screen's spinner never settles, so pump through the route change.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(backend.joined, ['AB3K7X']);
    expect(find.byType(WaitingForOptionsScreen), findsOneWidget);

    backend.room.add(state(status: 'lobby').copyWithDeck(const []));
    await tester.pump();
    expect(find.byType(SwipeScreen), findsNothing);

    // Rebuild with the deck, run the post-frame navigation, then the transition.
    backend.room.add(state());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SwipeScreen), findsOneWidget);
    expect(find.text('Demo Pizza'), findsWidgets);
  });

  testWidgets('results wait for the server, then show the winner', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    backend.room.add(state());
    await tester.pump();
    expect(find.text('Waiting for everyone to finish voting...'), findsOne);

    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        results: const RoomResults(
          winnerId: 'b',
          likes: {'a': 1, 'b': 2},
          participants: 3,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Demo Tacos'), findsOneWidget);
    expect(find.text('Votes: 2 of 3'), findsOneWidget);
    expect(backend.closes, 0, reason: 'the server closes these rooms');
  });

  testWidgets('legacy rooms are closed by the client once results show', (
    tester,
  ) async {
    final backend = FakeRoomBackend(clientClosesRooms: true);
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    backend.room.add(state(remaining: 2));
    await tester.pump();
    expect(find.text('Waiting for 2 more votes...'), findsOneWidget);
    backend.room.add(
      state(
        ready: true,
        results: const RoomResults(
          winnerId: 'a',
          likes: {'a': 1},
          participants: 2,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Demo Pizza'), findsOneWidget);
    expect(backend.closes, 1);
  });
}

extension on RoomState {
  RoomState copyWithDeck(List<Restaurant> restaurants) => RoomState(
    id: id,
    joinCode: joinCode,
    creatorId: creatorId,
    status: status,
    memberCount: memberCount,
    restaurants: restaurants,
    myVoteCount: myVoteCount,
    resultsReady: resultsReady,
    remainingVoters: remainingVoters,
    results: results,
  );
}

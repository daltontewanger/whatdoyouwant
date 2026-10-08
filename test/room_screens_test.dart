import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/active_room_store.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/live_search.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

class FakeRoomBackend implements RoomBackend {
  FakeRoomBackend({this.clientClosesRooms = false});

  final room = StreamController<RoomState>.broadcast();
  final joined = <String>[];
  int closes = 0;
  int nudges = 0;
  Object? createError;
  Object? startError;
  Object? voteError;

  @override
  final bool clientClosesRooms;
  @override
  bool get requiresVerifiedHost => true;
  @override
  bool get usesDeviceLocation => false;
  @override
  bool get usesFictionalRestaurants => true;

  @override
  Future<String> joinRoom(String typedCode) async {
    joined.add(typedCode);
    return 'ROOM-ID';
  }

  @override
  Stream<RoomState> watch(String roomId) => room.stream;
  @override
  Future<void> nudge(String roomId) async => nudges++;
  @override
  Future<void> close(String roomId) async => closes++;
  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async => null;
  @override
  Future<CreatedRoom> createRoom() async =>
      throw createError ?? UnimplementedError();
  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required double radiusMiles,
    required int maxOptions,
  }) async => throw startError ?? UnimplementedError();
  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  }) async {
    if (voteError != null) throw voteError!;
  }
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
  Set<String> voted = const {},
  List<Restaurant>? restaurants,
  DateTime? votingEndsAt,
}) => RoomState(
  id: 'ROOM-ID',
  joinCode: null,
  creatorId: 'host',
  status: status,
  memberCount: 3,
  restaurants: restaurants ?? deck,
  myVoteCount: voted.length,
  votedIds: voted,
  resultsReady: ready,
  remainingVoters: remaining,
  results: results,
  votingEndsAt: votingEndsAt,
);

Widget app(FakeRoomBackend backend, Widget home, {ActiveRoomStore? rooms}) =>
    RoomBackendScope(
      backend: backend,
      activeRooms: rooms,
      child: MaterialApp(home: home),
    );

Widget waiting(FakeRoomBackend backend, {ActiveRoomStore? rooms}) => app(
  backend,
  WaitingForOptionsScreen(
    roomCode: 'ROOM-ID',
    currentUser: AppUser(id: 'guest', name: 'Guest'),
  ),
  rooms: rooms,
);

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

  testWidgets('a returning voter continues with the cards not yet voted on', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(waiting(backend));
    backend.room.add(state(voted: {'a'}));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SwipeScreen), findsOneWidget);
    expect(find.text('Demo Tacos'), findsWidgets);
    expect(find.text('Demo Pizza'), findsNothing);
    expect(find.text('Option 1 of 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('someone who already voted on everything goes to results', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(waiting(backend));
    backend.room.add(state(voted: {'a', 'b'}));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ResultsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a guest waiting in a room the host closed is told so', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    final rooms =
        MemoryActiveRoomStore()
          ..room = const ActiveRoom('ROOM-ID', host: false);
    await tester.pumpWidget(waiting(backend, rooms: rooms));
    backend.room.add(state(status: 'closed', restaurants: const []));
    await tester.pump();
    expect(find.text('The host closed this room.'), findsOneWidget);
    expect(find.text('Back to Home'), findsOneWidget);
    expect(rooms.room, isNull);
  });

  testWidgets('a room that can no longer be read is reported as unavailable', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(waiting(backend));
    backend.room.addError(Exception('permission-denied'));
    await tester.pump();
    expect(find.text('This room is no longer available.'), findsOneWidget);
  });

  test('join failures read as guidance, not errors', () {
    expect(
      joinErrorMessage(
        FirebaseFunctionsException(code: 'permission-denied', message: ''),
      ),
      startsWith('No open room uses that code.'),
    );
    expect(
      joinErrorMessage(
        FirebaseFunctionsException(code: 'resource-exhausted', message: ''),
      ),
      'Too many attempts. Wait a minute and try again.',
    );
    expect(
      joinErrorMessage(
        FirebaseFunctionsException(code: 'failed-precondition', message: ''),
      ),
      'This room is full. Rooms hold up to 15 people.',
    );
    expect(joinErrorMessage(InvalidJoinCode()), contains('6-character code'));
    expect(
      joinErrorMessage(Exception('offline')),
      startsWith('Could not join'),
    );
  });

  testWidgets('a host who cannot create a room is told why in plain words', (
    tester,
  ) async {
    final backend =
        FakeRoomBackend()
          ..createError = FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Room action unavailable.',
          );
    await tester.pumpWidget(
      app(backend, RoomScreen(currentUser: AppUser(id: 'host', name: 'Host'))),
    );
    await tester.pump();
    expect(
      find.text(
        'Only verified accounts can host a room. Open Account to sign in or verify your email.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Room action unavailable'), findsNothing);
  });

  testWidgets('a host whose room cannot start sees a plain message', (
    tester,
  ) async {
    final backend =
        FakeRoomBackend()
          ..startError = FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Room action unavailable.',
          );
    await tester.pumpWidget(
      app(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
      ),
    );
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    await tester.ensureVisible(find.text('Start Swiping'));
    await tester.tap(find.text('Start Swiping'));
    await tester.pump();
    expect(
      find.text(
        'This room can no longer be started. It may have expired or been closed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a rejected vote is explained without the raw error', (
    tester,
  ) async {
    final backend =
        FakeRoomBackend()
          ..voteError = FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
            message: 'Missing or insufficient permissions.',
          );
    await tester.pumpWidget(
      app(
        backend,
        SwipeScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          radius: 1,
          maxOptions: 2,
          restaurants: deck,
        ),
      ),
    );
    await tester.pump();
    await tester.timedDrag(
      find.byType(Card).last,
      const Offset(500, 0),
      const Duration(milliseconds: 300),
    );
    // The countdown timer never settles; pump through the swipe animation.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text(
        'That vote was not counted. Voting may have ended for this room.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('insufficient permissions'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('room, start and vote failures map to plain messages', () {
    FirebaseFunctionsException callable(String code) =>
        FirebaseFunctionsException(code: code, message: 'raw');
    expect(
      createRoomErrorMessage(callable('resource-exhausted')),
      startsWith('You have created several rooms recently.'),
    );
    expect(
      createRoomErrorMessage(Exception('offline')),
      'Could not create the room. Check your connection and try again.',
    );
    expect(
      startRoomErrorMessage(callable('resource-exhausted')),
      startsWith('Restaurant search is busy'),
    );
    expect(
      startRoomErrorMessage(callable('failed-precondition')),
      'Not enough restaurants nearby match. Try a wider distance.',
    );
    expect(
      startRoomErrorMessage(callable('unavailable')),
      startsWith('Restaurant search is unavailable'),
    );
    expect(
      startRoomErrorMessage(Exception('Failed to load restaurants: x')),
      'Could not load restaurants. Check your connection and try again.',
    );
    expect(
      voteErrorMessage(callable('unauthenticated')),
      startsWith('This device could not be verified.'),
    );
    expect(
      voteErrorMessage(Exception('offline')),
      'Your vote could not be saved. Check your connection.',
    );
  });

  testWidgets('a joined room is remembered for returning after a restart', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    final rooms = MemoryActiveRoomStore();
    await tester.pumpWidget(
      app(
        backend,
        JoinRoomScreen(currentUser: AppUser(id: 'guest', name: 'Guest')),
        rooms: rooms,
      ),
    );
    await tester.enterText(find.byType(TextField), 'ab3k7x');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(rooms.room?.id, 'ROOM-ID');
    expect(rooms.room?.host, isFalse);
  });

  testWidgets('swipe cards share one size and are centered', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font is wide; at full scale every card's text wraps and fills
    // the space regardless, hiding a card that is not stretched or centered.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final names = [
      Restaurant(id: 'a', name: 'Pho', address: '1', distance: 0.25),
      Restaurant(
        id: 'b',
        name: 'Tacos',
        address: '2 Example Street',
        distance: 0.5,
      ),
    ];
    await tester.pumpWidget(
      app(
        FakeRoomBackend(),
        SwipeScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          radius: 1,
          maxOptions: 2,
          restaurants: names,
        ),
      ),
    );
    await tester.pump();
    final cards = tester.widgetList<Card>(find.byType(Card)).toList();
    expect(cards, hasLength(2));
    final sizes = [for (final c in cards) tester.getSize(find.byWidget(c))];
    expect(sizes[0], sizes[1]);
    final front = tester.getRect(find.byWidget(cards.last));
    expect(front.center.dx, closeTo(375 / 2, 1));
    // Dispose the screen so its countdown and watchdog timers stop.
    await tester.pumpWidget(const SizedBox());
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

  testWidgets(
    'results ask the server once, at the end of voting, then rarely',
    (tester) async {
      final backend = FakeRoomBackend();
      await tester.pumpWidget(
        app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
      );
      expect(backend.nudges, 1);

      final endsAt = DateTime.now().add(const Duration(seconds: 30));
      // Room updates while others vote must not each trigger a tally.
      for (var i = 0; i < 5; i++) {
        backend.room.add(state(votingEndsAt: endsAt));
        await tester.pump();
        await tester.pump(const Duration(seconds: 5));
      }
      expect(backend.nudges, 1);
      await tester.pump(const Duration(seconds: 7));
      expect(backend.nudges, 2, reason: 'voting window ended');
      await tester.pump(const Duration(seconds: 30));
      expect(backend.nudges, 3, reason: 'one-minute fallback');

      backend.room.add(
        state(
          status: 'closed',
          ready: true,
          results: const RoomResults(
            winnerId: 'a',
            likes: {'a': 1},
            participants: 1,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(minutes: 3));
      expect(backend.nudges, 3, reason: 'stops once results are in');
    },
  );

  testWidgets('a result still shows after the deck is gone', (tester) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: const [])),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        restaurants: const [],
        results: RoomResults(
          winnerId: 'gone',
          likes: const {'gone': 2},
          participants: 2,
          winnerCard: Restaurant(
            id: 'gone',
            name: 'Demo Noodle House',
            address: '6 Example Street',
            distance: 1,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Demo Noodle House'), findsOneWidget);
  });

  testWidgets('legacy rooms keep the frequent nudge for idle voters', (
    tester,
  ) async {
    final backend = FakeRoomBackend(clientClosesRooms: true);
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    await tester.pump(const Duration(seconds: 18));
    expect(backend.nudges, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('voters nudge only after their last card or when time is up', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(
        backend,
        SwipeScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          radius: 1,
          maxOptions: 2,
          restaurants: deck,
        ),
      ),
    );
    await tester.pump();
    final endsAt = DateTime.now().add(const Duration(minutes: 2));
    backend.room.add(state(votingEndsAt: endsAt));
    await tester.pump();

    await tester.timedDrag(
      find.byType(Card).last,
      const Offset(500, 0),
      const Duration(milliseconds: 300),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 30));
    expect(backend.nudges, 0, reason: 'one card left to vote on');

    await tester.pump(const Duration(seconds: 90));
    expect(backend.nudges, 1, reason: 'voting window ended');
    backend.room.add(state(status: 'closed', votingEndsAt: endsAt));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ResultsScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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

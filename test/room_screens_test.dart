import 'package:firebase_auth/firebase_auth.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/screens/main_shell.dart';
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/screens/help_links.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/screens/update_gate.dart';
import 'package:whatdoyouwant/services/active_room_store.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/live_search.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';
import 'package:geolocator/geolocator.dart';

class FakeRoomBackend implements RoomBackend {
  final room = StreamController<RoomState>.broadcast();
  final joined = <String>[];
  int nudges = 0;
  Object? createError;
  Object? startError;
  Object? voteError;

  @override
  bool usesDeviceLocation = false;
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
  LiveSearchAllowance? allowance;
  @override
  Future<LiveSearchAllowance?> liveSearchAllowance() async => allowance;
  @override
  Uri? joinLinkFor(String joinCode) =>
      Uri.parse('https://example.test/app/join/$joinCode');
  @override
  Uri sitePage(String path) => Uri.parse('https://example.test$path');
  bool tooOld = false;
  @override
  Future<bool> updateRequired(int build) async => tooOld;
  int prepared = 0;
  @override
  Future<void> prepareStart() async => prepared++;
  @override
  Future<CreatedRoom> createRoom() async =>
      throw createError ?? UnimplementedError();
  final started = <SearchPreferences>[];
  @override
  Future<List<Restaurant>> start(
    String roomId, {
    required SearchPreferences search,
  }) async {
    started.add(search);
    throw startError ?? UnimplementedError();
  }

  @override
  Future<void> vote(
    String roomId,
    Restaurant restaurant, {
    required bool liked,
    required int index,
    required int total,
  }) async {
    if (voteError != null) throw voteError!;
    votes.add((index, liked));
  }

  final votes = <(int, bool)>[];
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

Widget app(
  FakeRoomBackend backend,
  Widget home, {
  ActiveRoomStore? rooms,
  SearchDefaultsStore? defaults,
}) => RoomBackendScope(
  backend: backend,
  activeRooms: rooms,
  searchDefaults: defaults,
  child: MaterialApp(home: home),
);

Widget hostLobby(FakeRoomBackend backend, {SearchDefaultsStore? defaults}) =>
    app(
      backend,
      RoomScreen(
        currentUser: AppUser(id: 'host', name: 'Host'),
        roomCode: 'ROOM-ID',
        joinCode: 'AB3K7X',
      ),
      defaults: defaults,
    );

class LobbyLocation extends GeolocatorPlatform {
  LobbyLocation(this.permission, {this.afterRequest});
  LocationPermission permission;
  final LocationPermission? afterRequest;
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = afterRequest ?? permission;
  }
}

Widget waiting(FakeRoomBackend backend, {ActiveRoomStore? rooms}) => app(
  backend,
  WaitingForOptionsScreen(
    roomCode: 'ROOM-ID',
    currentUser: AppUser(id: 'guest', name: 'Guest'),
  ),
  rooms: rooms,
);

void main() {
  for (final (button, liked) in [('Yes', true), ('No', false)]) {
    testWidgets('the $button button votes without swiping', (tester) async {
      // A phone-sized screen: the buttons must be reachable without scrolling.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      await tester.tap(find.bySemanticsLabel('Vote $button'));
      // The countdown timer never settles; pump through the swipe animation.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(backend.votes, [(0, liked)]);
      expect(find.text('Option 2 of 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('the floating bar switches between Home and Account', (
    tester,
  ) async {
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        accounts: AccountService(ShellAuth()),
        child: const MaterialApp(home: MainShell(currentUid: 'guest')),
      ),
    );
    await tester.pump();
    expect(find.text('Create Room'), findsOneWidget);
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AppBar, 'Account').hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Account').hitTestable(), findsNothing);
  });

  testWidgets('leaving results returns to the first screen, bar and all', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      RoomBackendScope(
        backend: backend,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Text('First screen'),
        ),
      ),
    );
    // As in a real room: the room screen is under the swiping screen, which
    // hands over to results in its place.
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Room screen')),
    );
    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Swiping')),
    );
    await tester.pump(const Duration(milliseconds: 400));
    navigator.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        results: const RoomResults(
          winnerId: 'a',
          backupId: 'b',
          likes: {'a': 2, 'b': 1},
          participants: 2,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('Back to Home'));
    await tester.tap(find.text('Back to Home'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('First screen'), findsOneWidget);
    expect(find.byType(ResultsScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('help and legal pages are listed', (tester) async {
    await tester.pumpWidget(
      app(FakeRoomBackend(), const Scaffold(body: HelpList())),
    );
    for (final (_, label, _) in HelpList.pages) {
      expect(
        find.widgetWithText(ListTile, label),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('joining with an empty code stays on the form and explains why', (
    tester,
  ) async {
    // No Firebase initialization: invalid input must not reach the backend.
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          currentUser: AppUser(id: 'fixture-guest', name: 'Guest'),
        ),
      ),
    );
    expect(find.text('Join a Room'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
    await tester.pump();
    expect(find.text('Please enter a room code.'), findsOneWidget);
    expect(find.byType(JoinRoomScreen), findsOneWidget);
    expect(find.byType(WaitingForOptionsScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('the lobby shows a QR code and a join link while it is open', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = FakeRoomBackend();
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
    expect(
      find.bySemanticsLabel('QR code that opens the join link for this room'),
      findsOneWidget,
    );
    expect(find.text('Copy join link'), findsOneWidget);
    backend.room.add(state(status: 'voting'));
    await tester.pump();
    expect(find.text('Copy join link'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
  });

  testWidgets('a join link joins with its code straight away', (tester) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(
        backend,
        JoinRoomScreen(
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          initialCode: 'AB3K7X',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(backend.joined, ['AB3K7X']);
    await tester.pumpWidget(const SizedBox());
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

  testWidgets(
    'the lobby opens with the saved search, and changes become the new default',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeRoomBackend();
      final defaults = MemorySearchDefaults(
        const SearchPreferences(
          unit: DistanceUnit.km,
          radius: 10,
          deckSize: 15,
        ),
      );
      await tester.pumpWidget(hostLobby(backend, defaults: defaults));
      backend.room.add(state(status: 'lobby'));
      await tester.pump();
      expect(find.text('Within 10 km · 15 options'), findsOneWidget);
      expect(find.text('Any cuisine'), findsOneWidget);

      await tester.tap(find.text('Change search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 km'));
      await tester.tap(find.text('Thai').first);
      await tester.pump();
      // Leaving a preferred cuisine out takes it off the preferred list.
      await tester.tap(find.text('Thai').last);
      await tester.tap(find.text('Pizza').first);
      await tester.tap(find.text('Show places open now first'));
      await tester.pump();
      await tester.tap(find.text('Use these settings'));
      await tester.pumpAndSettle();

      const chosen = SearchPreferences(
        unit: DistanceUnit.km,
        radius: 3,
        deckSize: 15,
        includedCuisineIds: ['pizza'],
        excludedCuisineIds: ['thai'],
        openNowPreferred: true,
      );
      expect(find.text('Within 3 km · 15 options'), findsOneWidget);
      expect(
        find.text('Prefer Pizza · No Thai · Open now first'),
        findsOneWidget,
      );
      expect((defaults.current, defaults.saves), (chosen, 1));

      await tester.tap(find.text('Start Swiping'));
      await tester.pump();
      expect(backend.started, [chosen]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the lobby shows the searches left and blocks Start when none are',
    (tester) async {
      final backend =
          FakeRoomBackend()
            ..allowance = LiveSearchAllowance(
              weeklyCap: 20,
              used: 17,
              remaining: 3,
              resetsAt: DateTime.utc(2026, 11, 2),
              paused: false,
            );
      await tester.pumpWidget(hostLobby(backend));
      backend.room.add(state(status: 'lobby'));
      await tester.pump();
      expect(
        find.text('3 of 20 live searches left this week. Starting uses one.'),
        findsOneWidget,
      );
      ElevatedButton start() => tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Start Swiping'),
      );
      expect(start().onPressed, isNotNull);

      for (final (allowance, message) in [
        (
          LiveSearchAllowance(
            weeklyCap: 20,
            used: 20,
            remaining: 0,
            resetsAt: DateTime.utc(2026, 11, 2),
            paused: false,
          ),
          "You've used this week's live searches.",
        ),
        (
          LiveSearchAllowance(
            weeklyCap: 20,
            used: 2,
            remaining: 18,
            resetsAt: DateTime.utc(2026, 11, 2),
            paused: true,
          ),
          'Live restaurant search is paused for now.',
        ),
      ]) {
        backend.allowance = allowance;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(hostLobby(backend));
        backend.room.add(state(status: 'lobby'));
        await tester.pump();
        expect(find.textContaining(message), findsOneWidget);
        expect(start().onPressed, isNull);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'location is explained before the prompt; a block says how to undo it',
    (tester) async {
      final original = GeolocatorPlatform.instance;
      addTearDown(() => GeolocatorPlatform.instance = original);
      final backend = FakeRoomBackend()..usesDeviceLocation = true;
      final location = LobbyLocation(
        LocationPermission.denied,
        afterRequest: LocationPermission.deniedForever,
      );
      GeolocatorPlatform.instance = location;
      await tester.pumpWidget(hostLobby(backend));
      backend.room.add(state(status: 'lobby'));
      await tester.pump();

      // The spinner behind the dialog never settles.
      Future<void> settle() async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      await tester.ensureVisible(find.text('Start Swiping'));
      await tester.tap(find.text('Start Swiping'));
      await settle();
      expect(find.text('Use your location?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await settle();
      expect(location.requests, 0);
      expect(backend.started, isEmpty);

      await tester.tap(find.text('Start Swiping'));
      await settle();
      await tester.tap(find.text('Continue'));
      await settle();
      expect(location.requests, 1);
      expect(backend.started, isEmpty);
      expect(find.textContaining('Allow it in Settings'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('the host lobby gets the location ready once; guests do not', (
    tester,
  ) async {
    final backend = FakeRoomBackend()..usesDeviceLocation = true;
    Widget lobby({required bool host}) => app(
      backend,
      RoomScreen(
        currentUser: AppUser(id: host ? 'host' : 'guest', name: 'Someone'),
        isCreator: host,
        roomCode: 'ROOM-ID',
        joinCode: 'AB3K7X',
      ),
    );
    await tester.pumpWidget(lobby(host: true));
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    expect(backend.prepared, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(lobby(host: false));
    await tester.pump();
    expect(backend.prepared, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'an old build is asked to update; a current one goes straight in',
    (tester) async {
      Future<int> build() async => 2;
      final current = FakeRoomBackend();
      await tester.pumpWidget(
        app(
          current,
          UpdateGate(installedBuild: build, child: const Text('Home')),
        ),
      );
      await tester.pump();
      expect(find.text('Home'), findsOneWidget);

      final old = FakeRoomBackend()..tooOld = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(old, UpdateGate(installedBuild: build, child: const Text('Home'))),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Home'), findsNothing);
      expect(find.text('A newer version is ready'), findsOneWidget);
    },
  );

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

/// Signed out, with nothing else needed to draw the Account tab.
class ShellAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;

  @override
  Stream<User?> userChanges() => Stream.value(null);
}

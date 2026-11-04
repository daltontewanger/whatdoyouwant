import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/saved_place.dart';
import 'package:whatdoyouwant/screens/my_places_screen.dart';
import 'package:whatdoyouwant/screens/quick_pick_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/services/my_places.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/room_lists.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

import 'my_places_test.dart' show place, placeId, scoped;
import 'room_screens_test.dart' show FakeRoomBackend, state;

/// A pick whose cards came from a search, so they can be reported.
class _PickBackend extends FakeRoomBackend {
  _PickBackend(this.card);

  final Restaurant card;

  @override
  Future<QuickPick> createQuickPick({
    required String requestId,
    required SearchPreferences search,
    String? zip,
  }) async => QuickPick(
    id: 'PICK',
    position: 0,
    restaurant: card,
    rerollsLeft: 0,
    cards: {card.id: card},
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final taco = Restaurant(
    id: placeId(1),
    name: 'Demo Taco',
    address: '1 Example St',
    distance: 1,
    website: 'https://example.test',
  );

  Future<void> showResults(
    WidgetTester tester,
    FakeRoomBackend backend,
    MemoryMyPlaces store,
  ) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cards = [taco, place(2, 'Demo Fish')];
    await tester.pumpWidget(
      scoped(
        backend,
        ResultsScreen(roomCode: 'ROOM-ID', restaurants: cards),
        places: store,
      ),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        restaurants: cards,
        results: RoomResults(
          winnerId: placeId(1),
          likes: {placeId(1): 2},
          participants: 2,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'a closed winner leaves the lists, is reported, and can be undone',
    (tester) async {
      final backend = FakeRoomBackend();
      final store = MemoryMyPlaces(
        MyPlaces(favorites: [SavedPlace(id: placeId(1))]),
      )..synced = true;
      await showResults(tester, backend, store);
      await tester.tap(find.text('Closed or wrong info?'));
      await tester.pumpAndSettle();
      expect(find.text("What's wrong with Demo Taco?"), findsOneWidget);
      expect(find.text('The website is wrong'), findsOneWidget);
      expect(
        find.text('The phone number is wrong'),
        findsNothing,
        reason: 'the card has no phone to be wrong',
      );
      await tester.tap(find.text("It's closed for good"));
      await tester.pumpAndSettle();
      expect(store.isClosed(placeId(1)), isTrue);
      expect(store.isFavorite(placeId(1)), isFalse);
      expect(backend.reports, [(placeId(1), PlaceProblem.closed, 'ROOM-ID')]);
      expect(
        find.text("Thanks. Demo Taco won't come up for you again."),
        findsOneWidget,
      );
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(store.isClosed(placeId(1)), isFalse);
      expect(store.isFavorite(placeId(1)), isTrue);
    },
  );

  testWidgets('a guest hides a closed place on the device without reporting', (
    tester,
  ) async {
    final backend = FakeRoomBackend();
    final store = MemoryMyPlaces();
    await showResults(tester, backend, store);
    await tester.tap(find.text('Closed or wrong info?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("It's closed for good"));
    await tester.pumpAndSettle();
    expect(store.isClosed(placeId(1)), isTrue);
    expect(backend.reports, isEmpty);
  });

  testWidgets('a wrong website is reported without hiding the place', (
    tester,
  ) async {
    final backend = FakeRoomBackend()..reportError = Exception('offline');
    final store = MemoryMyPlaces()..synced = true;
    await showResults(tester, backend, store);
    await tester.tap(find.text('Closed or wrong info?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('The website is wrong'));
    await tester.pumpAndSettle();
    expect(store.places.closed, isEmpty);
    expect(
      find.text('Thanks for letting us know.'),
      findsOneWidget,
      reason: 'a report that fails to send changes nothing on screen',
    );
  });

  testWidgets('a picked place can be reported before choosing it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = _PickBackend(taco);
    final store = MemoryMyPlaces()..synced = true;
    await tester.pumpWidget(
      scoped(
        backend,
        const QuickPickScreen(),
        places: store,
        defaults: MemorySearchDefaults(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed or wrong info?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("It's somewhere else on the map"));
    await tester.pumpAndSettle();
    expect(backend.reports, [(placeId(1), PlaceProblem.location, 'PICK')]);
  });

  testWidgets('typed spots have nothing to report', (tester) async {
    final backend = FakeRoomBackend();
    final typed = Restaurant(
      id: 'own-1',
      name: 'Pizza Place',
      address: '',
      distance: 0,
      userEntered: true,
    );
    await tester.pumpWidget(
      scoped(
        backend,
        ResultsScreen(roomCode: 'ROOM-ID', restaurants: [typed]),
        places: MemoryMyPlaces(),
      ),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        restaurants: [typed],
        results: RoomResults(winnerId: 'own-1', likes: {}, participants: 1),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Pizza Place'), findsWidgets);
    expect(find.text('Closed or wrong info?'), findsNothing);
  });

  testWidgets('Your lists shows reported places and takes one back', (
    tester,
  ) async {
    final store = MemoryMyPlaces(
      MyPlaces(closed: [SavedPlace(id: placeId(1), name: 'Demo Taco')]),
    );
    await tester.pumpWidget(
      scoped(FakeRoomBackend(), const MyPlacesScreen(), places: store),
    );
    expect(find.text('Reported closed'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Demo Taco'));
    await tester.pump();
    expect(store.places.closed, isEmpty);
    expect(find.text('Reported closed'), findsNothing);
  });

  test(
    'closed places survive a save and are always shared with rooms',
    () async {
      final places = MyPlaces(
        never: [SavedPlace(id: placeId(2))],
        closed: [SavedPlace(id: placeId(1), name: 'Demo Taco')],
        useNever: false,
      );
      final json = jsonDecode(jsonEncode(places.toJson()));
      expect(json['closed'], [
        {'id': placeId(1), 'name': 'Demo Taco'},
      ]);
      expect(MyPlaces.fromJson(json), places);
      expect(
        const MyPlaces().merged(places).closed.single.id,
        placeId(1),
        reason: "a guest's reports go with them into a new account",
      );

      final backend = FakeRoomBackend();
      final sharer = RoomListSharer(
        backend: backend,
        places: MemoryMyPlaces(places),
        roomId: 'ROOM-ID',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        backend.shared.single.$3,
        isEmpty,
        reason: 'the never switch is off',
      );
      expect(backend.sharedClosed.single, [placeId(1)]);
      sharer.dispose();
    },
  );
}

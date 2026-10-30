import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/saved_place.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/my_places_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/live_search.dart';
import 'package:whatdoyouwant/services/my_places.dart';
import 'package:whatdoyouwant/services/own_list.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/room_lists.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

import 'room_screens_test.dart' show FakeRoomBackend, state;

String placeId(int n) => 'c${n.toRadixString(16).padLeft(20, '0')}';

Restaurant place(int n, String name) => Restaurant(
  id: placeId(n),
  name: name,
  address: '$n Example Street',
  distance: 0.5,
);

final now = DateTime.utc(2026, 10, 30, 12);

class FakeMyPlacesAccount implements MyPlacesAccount {
  @override
  String? verifiedUid;
  @override
  bool isGuest = false;
  final signIns = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => signIns.stream;
  MyPlaces? server;
  bool offline = false;
  final writes = <MyPlaces>[];

  @override
  Future<MyPlaces?> read(String uid) async {
    if (offline) throw Exception('offline');
    return server;
  }

  @override
  Future<void> write(MyPlaces places) async {
    if (offline) throw Exception('offline');
    writes.add(places);
    server = places;
  }
}

/// Lets a card fly off and a snack bar slide in.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String sharedText(FakeRoomBackend backend) => [
  for (final (room, favorites, never) in backend.shared)
    '$room $favorites $never',
].join(' | ');

Widget scoped(
  FakeRoomBackend backend,
  Widget home, {
  MyPlacesStore? places,
  OwnListStore? ownList,
  SearchDefaultsStore? defaults,
}) => RoomBackendScope(
  backend: backend,
  myPlaces: places,
  ownList: ownList,
  searchDefaults: defaults,
  child: MaterialApp(home: home),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('saved places', () {
    test('only search cards can be saved', () {
      expect(SavedPlace.canSave(place(1, 'Demo Taco')), isTrue);
      expect(
        SavedPlace.canSave(
          Restaurant(
            id: 'a1b2',
            name: 'Typed',
            address: '',
            distance: 0,
            userEntered: true,
          ),
        ),
        isFalse,
      );
    });

    test('favorite details last 30 days; never keeps only a name', () {
      final favorite = SavedPlace.favorite(place(1, 'Demo Taco'), now);
      expect(favorite.favoriteJson(), {
        'id': placeId(1),
        'name': 'Demo Taco',
        'address': '1 Example Street',
        'seenAt': now.millisecondsSinceEpoch,
      });
      expect(SavedPlace.never(place(2, 'Demo Fish')).neverJson(), {
        'id': placeId(2),
        'name': 'Demo Fish',
      });
      final later = now.add(SavedPlace.detailsFor);
      expect(favorite.current(later), SavedPlace(id: placeId(1)));
      expect(favorite.current(later).favoriteJson(), {'id': placeId(1)});
      final places = MyPlaces(favorites: [favorite], useNever: false);
      expect(
        MyPlaces.fromJson(jsonDecode(jsonEncode(places.toJson()))),
        places,
      );
    });

    test('merging adds new places only, and keeps the switches', () {
      final mine = MyPlaces(
        favorites: [SavedPlace(id: placeId(1))],
        useFavorites: false,
      );
      final guest = MyPlaces(
        favorites: [SavedPlace(id: placeId(1)), SavedPlace(id: placeId(2))],
        never: [SavedPlace(id: placeId(3))],
      );
      final merged = mine.merged(guest);
      expect(merged.favorites.map((p) => p.id), [placeId(1), placeId(2)]);
      expect(merged.never.map((p) => p.id), [placeId(3)]);
      expect(merged.useFavorites, isFalse);
    });
  });

  group('store', () {
    test('a place is on one list at a time', () async {
      final store = MemoryMyPlaces(const MyPlaces(), () => now);
      await store.addNever(place(1, 'Demo Taco'));
      expect(store.isNever(placeId(1)), isTrue);
      await store.addFavorite(place(1, 'Demo Taco'));
      expect(
        (store.isFavorite(placeId(1)), store.isNever(placeId(1))),
        (true, false),
      );
      await store.addNever(place(1, 'Demo Taco'));
      expect(
        (store.isFavorite(placeId(1)), store.isNever(placeId(1))),
        (false, true),
      );
      await store.remove(placeId(1));
      expect(store.places.isEmpty, isTrue);
    });

    test('a full list says so instead of dropping a place', () async {
      final store = MemoryMyPlaces(
        MyPlaces(
          favorites: [
            for (var i = 0; i < MyPlaces.maxPlaces; i++)
              SavedPlace(id: placeId(i)),
          ],
        ),
      );
      expect(
        () => store.addFavorite(place(999, 'One too many')),
        throwsA(isA<ListFull>()),
      );
    });

    test(
      'favorites in a new deck refresh their details at most daily',
      () async {
        var clock = now;
        final store = MemoryMyPlaces(
          MyPlaces(
            favorites: [
              SavedPlace(id: placeId(1)),
              SavedPlace.favorite(place(2, 'Demo Noodle'), now),
            ],
          ),
          () => clock,
        );
        await store.seen([place(1, 'Demo Taco'), place(2, 'Demo Noodle')]);
        expect(store.saves, 1);
        expect(store.places.favorites.first.name, 'Demo Taco');
        await store.seen([place(1, 'Demo Taco')]);
        expect(store.saves, 1, reason: 'already fresh today');
        clock = now.add(const Duration(days: 2));
        await store.seen([place(2, 'Demo Noodle'), place(3, 'Not saved')]);
        expect(store.saves, 2);
        expect(store.places.favorites.length, 2);
      },
    );
  });

  group('synced lists', () {
    test(
      'a guest list merges into the account once; sign-out clears it',
      () async {
        final account = FakeMyPlacesAccount()..isGuest = true;
        final store = SyncedMyPlaces(account: account, now: () => now);
        addTearDown(store.dispose);
        await store.load();
        await store.addNever(place(1, 'Demo Fish'));
        expect(
          account.writes,
          isEmpty,
          reason: 'guests keep lists on the device',
        );

        account
          ..isGuest = false
          ..verifiedUid = 'u1'
          ..server = MyPlaces(favorites: [SavedPlace(id: placeId(2))]);
        await store.load();
        expect(store.places.never.single.id, placeId(1));
        expect(store.places.favorites.single.id, placeId(2));
        expect(account.server, store.places);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('myPlaces.guest'),
          isNull,
          reason: 'merged only once',
        );

        account
          ..verifiedUid = null
          ..isGuest = true;
        account.signIns.add(null);
        await pumpEventQueue();
        expect(prefs.getString('myPlaces.account'), isNull);
        expect(store.places.isEmpty, isTrue);
      },
    );

    test('edits made offline reach the account on the next load', () async {
      final account =
          FakeMyPlacesAccount()
            ..verifiedUid = 'u1'
            ..server = const MyPlaces();
      final store = SyncedMyPlaces(account: account, now: () => now);
      addTearDown(store.dispose);
      await store.load();
      account.offline = true;
      await expectLater(
        store.addFavorite(place(1, 'Demo Taco')),
        throwsException,
      );
      expect(store.isFavorite(placeId(1)), isTrue);
      account.offline = false;
      final next = SyncedMyPlaces(account: account, now: () => now);
      addTearDown(next.dispose);
      await next.load();
      expect(account.server!.favorites.single.name, 'Demo Taco');
    });

    test('a room gets the lists its switches allow, again on change', () async {
      final backend = FakeRoomBackend();
      final store = MemoryMyPlaces(
        MyPlaces(
          favorites: [SavedPlace(id: placeId(1))],
          never: [SavedPlace(id: placeId(2))],
          useNever: false,
        ),
      );
      final sharer = RoomListSharer(
        backend: backend,
        places: store,
        roomId: 'ROOM-ID',
      );
      await pumpEventQueue();
      await store.save(store.places.copyWith(useNever: true));
      await pumpEventQueue();
      sharer.dispose();
      await store.save(const MyPlaces());
      await pumpEventQueue();
      expect(
        sharedText(backend),
        'ROOM-ID [${placeId(1)}] [] | ROOM-ID [${placeId(1)}] [${placeId(2)}]',
      );
    });
  });

  Widget swiping(
    FakeRoomBackend backend,
    MyPlacesStore store,
    List<Restaurant> cards,
  ) => scoped(
    backend,
    SwipeScreen(
      roomCode: 'ROOM-ID',
      currentUser: AppUser(id: 'guest', name: 'Guest'),
      radius: 1,
      maxOptions: cards.length,
      restaurants: cards,
    ),
    places: store,
  );

  const favoriteButton = 'I know what I want: vote yes and save it';
  const neverButton = 'Never what I want: vote no and save it';

  testWidgets('Favorite votes yes and Never votes no, both saving the place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    final store = MemoryMyPlaces(const MyPlaces(), () => now);
    await tester.pumpWidget(
      swiping(backend, store, [
        place(1, 'Demo Taco'),
        place(2, 'Demo Fish'),
        Restaurant(
          id: 'typed-1',
          name: 'Our usual',
          address: '',
          distance: 0,
          userEntered: true,
        ),
      ]),
    );
    await tester.pump();
    // The buttons sit on the card; its text stays centred above them.
    final card = tester.getRect(find.byType(Card).last);
    final name = tester.getRect(find.text('Demo Taco'));
    expect(name.center.dx, closeTo(card.center.dx, 1));

    await tester.tap(find.byTooltip(favoriteButton).hitTestable());
    await settle(tester);
    expect(backend.votes, [(0, true)]);
    expect(store.isFavorite(placeId(1)), isTrue);
    expect(
      find.text('Saved to your "I know what I want" list'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip(neverButton).hitTestable());
    await settle(tester);
    expect(backend.votes, [(0, true), (1, false)]);
    expect(store.isNever(placeId(2)), isTrue);
    expect(find.text('Saved to your "Never what I want" list'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget, reason: 'it can be closed');
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(
      store.isNever(placeId(2)),
      isFalse,
      reason: 'Undo takes it back off',
    );

    // The host's own typed spot cannot go on either list.
    expect(find.byTooltip(favoriteButton).hitTestable(), findsNothing);
    expect(find.byTooltip(neverButton).hitTestable(), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a place already on a list shows its mark instead of buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryMyPlaces(
      MyPlaces(favorites: [SavedPlace.favorite(place(1, 'Demo Taco'), now)]),
    );
    await tester.pumpWidget(
      swiping(FakeRoomBackend(), store, [place(1, 'Demo Taco')]),
    );
    await tester.pump();
    const badge = 'This is on your "I know what I want" list';
    expect(find.byTooltip(favoriteButton), findsNothing);
    expect(find.byTooltip(neverButton), findsNothing);
    await tester.tap(find.byTooltip(badge));
    await settle(tester);
    expect(find.text(badge), findsOneWidget, reason: 'tapping says which list');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('arrow keys vote no and yes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      swiping(backend, MemoryMyPlaces(), [
        place(1, 'Demo Taco'),
        place(2, 'Demo Fish'),
      ]),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(backend.votes, [(0, true), (1, false)]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results save a favorite and add it to the own list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    final store = MemoryMyPlaces(const MyPlaces(), () => now);
    final ownList = MemoryOwnList();
    final cards = [place(1, 'Demo Taco'), place(2, 'Demo Fish')];
    await tester.pumpWidget(
      scoped(
        backend,
        ResultsScreen(roomCode: 'ROOM-ID', restaurants: cards),
        places: store,
        ownList: ownList,
      ),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        restaurants: cards,
        results: RoomResults(
          winnerId: placeId(1),
          likes: {placeId(1): 3},
          participants: 3,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Save as favorite'));
    await tester.pump();
    expect(store.isFavorite(placeId(1)), isTrue);
    expect(find.text('Saved to favorites'), findsOneWidget);
    await tester.tap(find.text('Add to my list'));
    await tester.pump();
    expect(ownList.spots.single.name, 'Demo Taco');
    expect(find.text('On my list'), findsOneWidget);
    await tester.tap(find.text('Saved to favorites'));
    await tester.pump();
    expect(
      store.isFavorite(placeId(1)),
      isFalse,
      reason: 'tapping again removes it',
    );
  });

  testWidgets('the host lobby switches decide what the deck uses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend =
        FakeRoomBackend()
          ..startError = FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'raw',
            details: {
              'reason': 'too-few-results',
              'eligible': 2,
              'minimum': 5,
              'neverLeftOut': 9,
            },
          );
    final store = MemoryMyPlaces(MyPlaces(never: [SavedPlace(id: placeId(7))]));
    await tester.pumpWidget(
      scoped(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
        places: store,
        defaults: MemorySearchDefaults(),
      ),
    );
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    expect(sharedText(backend), 'ROOM-ID [] [${placeId(7)}]');

    expect(find.text('I know what I want ›'), findsOneWidget);
    expect(
      find.text("Everyone's exclusion list combined, kept private"),
      findsOneWidget,
    );
    // The first switch is the favorites one.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.tap(find.text('Start Swiping'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Never lists left out 9 places'), findsOne);
    backend.startError = null;
    await tester.tap(find.text('Start without them'));
    await tester.pumpAndSettle();
    expect(backend.startedLists, [
      const DeckLists(favorites: false, never: true),
      const DeckLists(favorites: false, never: false),
    ]);
    await tester.pumpWidget(const SizedBox());
  });

  test('a short search names what never lists took out', () {
    FirebaseFunctionsException failure(Map<String, Object> details) =>
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'raw',
          details: details,
        );
    expect(
      neverLeftOut(failure({'reason': 'too-few-results', 'neverLeftOut': 4})),
      4,
    );
    expect(neverLeftOut(failure({'reason': 'too-few-results'})), isNull);
    expect(neverLeftOut(Exception('other')), isNull);
  });

  testWidgets('Your lists shows both lists with switches and Undo', (
    tester,
  ) async {
    final store = MemoryMyPlaces(
      MyPlaces(
        favorites: [
          SavedPlace(id: placeId(1)),
          SavedPlace.favorite(place(2, 'Demo Noodle'), now),
        ],
        never: [SavedPlace.never(place(3, 'Demo Fish'))],
      ),
    );
    await tester.pumpWidget(
      scoped(FakeRoomBackend(), const MyPlacesScreen(), places: store),
    );
    expect(find.text('A saved favorite'), findsOneWidget);
    expect(find.text('Demo Noodle'), findsOneWidget);
    expect(
      find.text('Saved on this device.', findRichText: true),
      findsNothing,
    );
    await tester.tap(find.byTooltip('Remove Demo Fish'));
    await settle(tester);
    expect(store.places.never, isEmpty);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(store.places.never.single.name, 'Demo Fish');
    await tester.tap(find.text('Leave these out of rooms and picks'));
    await tester.pump();
    expect(store.places.useNever, isFalse);
  });
}

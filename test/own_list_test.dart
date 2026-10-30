import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/link.dart';
import 'package:whatdoyouwant/models/own_spot.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/main_shell.dart';
import 'package:whatdoyouwant/screens/own_list_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/own_list.dart';
import 'package:whatdoyouwant/services/place_links.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'room_screens_test.dart' show FakeRoomBackend, ShellAuth, app, state;

OwnSpot spot(String id, String name, {String address = '', String note = ''}) =>
    OwnSpot(id: id, name: name, address: address, note: note);

class FakeOwnListAccount implements OwnListAccount {
  @override
  String? verifiedUid;
  List<OwnSpot>? server;
  bool offline = false;
  final writes = <List<OwnSpot>>[];

  @override
  Future<List<OwnSpot>?> read(String uid) async {
    if (offline) throw Exception('offline');
    return server;
  }

  @override
  Future<void> write(List<OwnSpot> spots) async {
    if (offline) throw Exception('offline');
    writes.add(spots);
    server = [...spots];
  }
}

/// Hands out the given numbers in order, so a test decides the shuffle.
class FirstRandom implements Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('merging adds new names only, and keeps what does not fit', () {
    final base = [for (var i = 0; i < 49; i++) spot('b$i', 'Spot $i')];
    final (merged, left) = mergeSpots(base, [
      spot('x', '  spot   3 '),
      spot('y', 'Pho Real'),
      spot('z', 'Taco Truck'),
    ]);
    expect(merged.length, OwnSpot.maxSpots);
    expect(merged.last.name, 'Pho Real');
    expect(left.map((s) => s.name), ['Taco Truck']);
  });

  test(
    'a guest list stays on the device and merges into the account once',
    () async {
      final account = FakeOwnListAccount();
      final store = SyncedOwnList(account: account);
      await store.load();
      await store.save([spot('g1', 'Pho Real'), spot('g2', 'Tony\'s Pizza')]);
      expect(
        account.writes,
        isEmpty,
        reason: 'guests never write to the server',
      );
      expect(store.synced, isFalse);

      account
        ..verifiedUid = 'u1'
        ..server = [spot('s1', "TONY'S PIZZA"), spot('s2', 'Taco Truck')];
      await store.load();
      expect(store.spots.map((s) => s.name), [
        "TONY'S PIZZA",
        'Taco Truck',
        'Pho Real',
      ]);
      expect(store.leftOver, isEmpty);

      // Removing a merged spot on another device sticks: the guest list was
      // used up by the merge, so it is not merged again.
      account.server = [spot('s2', 'Taco Truck')];
      await store.load();
      expect(store.spots.map((s) => s.name), ['Taco Truck']);

      account.verifiedUid = null;
      await store.load();
      expect(
        store.spots,
        isEmpty,
        reason: "the next guest does not see the account's list",
      );
    },
  );

  test('edits made offline reach the account on the next load', () async {
    final account =
        FakeOwnListAccount()
          ..verifiedUid = 'u1'
          ..server = [spot('s1', 'Taco Truck')];
    final store = SyncedOwnList(account: account);
    await store.load();
    account.offline = true;
    await expectLater(
      store.save([spot('s1', 'Taco Truck'), spot('s2', 'Pho Real')]),
      throwsException,
    );
    account.offline = false;
    await SyncedOwnList(account: account).load();
    expect(account.server!.map((s) => s.name), ['Taco Truck', 'Pho Real']);
  });

  test('typed spots open a Google Maps search, never HERE', () {
    final links = placeLinksFor(
      spot(
        'a',
        'Pho Real',
        address: '100 Main St',
        note: 'get the #4',
      ).toRestaurant(),
    );
    expect(
      links.map.toString(),
      'https://www.google.com/maps/search/?api=1&query=Pho+Real%2C+100+Main+St',
    );
    expect(
      links.directions.toString(),
      'https://www.google.com/maps/dir/?api=1&destination=Pho+Real%2C+100+Main+St',
    );
    expect(links.mapsName, 'Google Maps');
    expect(links.website, isNull);
  });

  Future<MemoryOwnList> openList(
    WidgetTester tester, [
    List<OwnSpot> spots = const [],
  ]) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryOwnList(spots);
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        ownList: store,
        child: MaterialApp(home: OwnListScreen(random: FirstRandom())),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('spots are added, edited and removed', (tester) async {
    final store = await openList(tester);
    expect(find.text('0 of 50 · saved on this device'), findsOneWidget);
    expect(find.text('Add at least 2 spots to pick from.'), findsOneWidget);

    await tester.tap(find.text('Add a spot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Pho Real');
    await tester.enterText(
      find.widgetWithText(TextField, 'Note (optional)'),
      'get the #4',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.spots.single.name, 'Pho Real');
    expect(find.text('get the #4'), findsOneWidget);

    await tester.tap(find.text('Pho Real'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Pho Realer',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.spots.single.name, 'Pho Realer');

    await tester.tap(find.text('Pho Realer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(store.spots, isEmpty);
  });

  testWidgets('a pick goes through every spot before repeating', (
    tester,
  ) async {
    await openList(tester, [
      spot('a', 'Pho Real'),
      spot('b', 'Taco Truck'),
      spot('c', "Tony's Pizza"),
    ]);
    await tester.tap(find.text('Pick one for me'));
    await tester.pumpAndSettle();
    expect(find.text('How about:'), findsOneWidget);
    final seen = <String>{};
    for (var i = 0; i < 3; i++) {
      for (final name in ['Pho Real', 'Taco Truck', "Tony's Pizza"]) {
        if (find.text(name).evaluate().isNotEmpty) seen.add(name);
      }
      await tester.tap(find.text('Not feeling it'));
      await tester.pumpAndSettle();
    }
    expect(seen.length, 3);
    expect(find.textContaining('Distance'), findsNothing);
    expect(find.text('Place details from HERE'), findsNothing);

    await tester.tap(find.text("Let's go here"));
    await tester.pumpAndSettle();
    expect(find.text("You're going to:"), findsOneWidget);
    final links = tester.widgetList<Link>(find.byType(Link));
    expect(links.single.uri!.host, 'www.google.com', reason: 'map only');
    await tester.tap(find.text('Back to my list'));
    await tester.pumpAndSettle();
    expect(find.text('Add a spot'), findsOneWidget);
  });

  testWidgets('spots that did not fit can be brought over', (tester) async {
    final store = await openList(tester, [spot('a', 'Pho Real')]);
    store.leftOver = [spot('b', 'Taco Truck')];
    store.notifyListeners();
    await tester.pump();
    expect(find.textContaining("didn't fit"), findsOneWidget);
    await tester.tap(find.text('Bring them over'));
    await tester.pump();
    expect(store.spots.map((s) => s.name), ['Pho Real', 'Taco Truck']);
    expect(find.textContaining("didn't fit"), findsNothing);
  });

  testWidgets('home shows the steps; the bar menu offers the other ways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        accounts: AccountService(ShellAuth()),
        ownList: MemoryOwnList(),
        child: const MaterialApp(home: MainShell(currentUid: 'guest')),
      ),
    );
    await tester.pump();
    for (final title in [
      'Start a room',
      'Everyone swipes',
      'See where to eat',
      'Tell Me What I Want',
      "We'll Decide What We Want",
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    expect(
      find.text(
        "I know, it's not that simple. Swipe together and let the group decide where to eat.",
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('More ways to decide'));
    await tester.pumpAndSettle();
    expect(find.text("You've been found wanting"), findsOneWidget);
    expect(find.text('Search settings'), findsOneWidget);
    expect(find.text('Join a room'), findsOneWidget);
    await tester.tap(find.text("We'll Decide What We Want").last);
    await tester.pumpAndSettle();
    expect(find.byType(OwnListScreen), findsOneWidget);
  });

  testWidgets('a room from the list swipes on the chosen spots, no search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final started = <List<OwnSpot>>[];
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        ownList: MemoryOwnList([
          spot('a', 'Pho Real'),
          spot('b', 'Taco Truck'),
          spot('c', "Tony's Pizza"),
        ]),
        child: MaterialApp(
          home: OwnListScreen(onStartRoom: (spots) async => started.add(spots)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a room with these'));
    await tester.pumpAndSettle();
    expect(find.text('Which spots?'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Taco Truck'));
    await tester.tap(find.widgetWithText(CheckboxListTile, "Tony's Pizza"));
    await tester.pump();
    expect(find.text('Pick at least 2.'), findsOneWidget);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Taco Truck'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Create Room'));
    await tester.pumpAndSettle();
    expect(started.single.map((s) => s.name), ['Pho Real', 'Taco Truck']);
  });

  testWidgets('a list lobby shows the spots and starts without a search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend()..startError = Exception('stop here');
    final spots = [spot('a', 'Pho Real'), spot('b', 'Taco Truck')];
    await tester.pumpWidget(
      app(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
          ownSpots: spots,
        ),
      ),
    );
    backend.room.add(state());
    await tester.pump();
    await tester.pump();
    expect(find.text('From your list'), findsOneWidget);
    expect(find.text('Pho Real, Taco Truck'), findsOneWidget);
    expect(find.text('Change search'), findsNothing);
    await tester.tap(find.text('Start Swiping'));
    await tester.pump();
    await tester.pump();
    expect(backend.startedFromList.single, spots);
    expect(backend.started, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}

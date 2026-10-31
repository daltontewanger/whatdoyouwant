import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/screens/place_card.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'room_screens_test.dart' show FakeRoomBackend, app, state;

/// Hands out the given numbers in order, so a test decides the pick and
/// whether the tease shows.
class ScriptedRandom implements Random {
  ScriptedRandom(this.ints);
  final List<int> ints;

  @override
  int nextInt(int max) => ints.removeAt(0) % max;
  @override
  double nextDouble() => throw UnimplementedError();
  @override
  bool nextBool() => throw UnimplementedError();
}

final places = [
  for (final (id, name) in [
    ('a', 'Demo Pizza'),
    ('b', 'Demo Tacos'),
    ('c', 'Demo Noodles'),
    ('d', 'Demo Curry'),
  ])
    Restaurant(
      id: id,
      name: name,
      address: '1 Example',
      distance: 1,
      latitude: 38.5,
      longitude: -98.5,
    ),
];

void main() {
  Future<FakeRoomBackend> showResults(
    WidgetTester tester,
    RoomResults results, {
    List<Restaurant>? deck,
    Random? random,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    final cards = deck ?? places;
    await tester.pumpWidget(
      app(
        backend,
        ResultsScreen(roomCode: 'ROOM-ID', restaurants: cards, random: random),
      ),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        restaurants: cards,
        results: results,
      ),
    );
    await tester.pump();
    await tester.pump();
    return backend;
  }

  test('the banner follows how many voters liked the winner', () {
    expect(resultBanner(likes: 4, voters: 4), 'Everyone wanted it');
    expect(resultBanner(likes: 1, voters: 1), 'Everyone wanted it');
    expect(resultBanner(likes: 5, voters: 10), 'Well, most of you wanted it');
    expect(resultBanner(likes: 9, voters: 10), 'Well, most of you wanted it');
    expect(resultBanner(likes: 4, voters: 10), 'Some of you wanted it');
    expect(resultBanner(likes: 1, voters: 10), 'Some of you wanted it');
    expect(resultBanner(likes: 0, voters: 10), 'Oops, no one wanted anything');
  });

  test('shared text names the place and links its HERE WeGo map', () {
    expect(
      placeShareText(places.first),
      "We're going to Demo Pizza, 1 Example. Picked with What Do You Want?!\n"
      'https://share.here.com/l/38.500000,-98.500000,'
      'Demo%20Pizza%2C%201%20Example?z=17',
    );
    expect(
      placeShareText(
        Restaurant(id: 'x', name: 'Legacy', address: '', distance: 1),
      ),
      "We're going to Legacy. Picked with What Do You Want?!",
    );
  });

  testWidgets('a voted backup opens in place of the winner and back', (
    tester,
  ) async {
    await showResults(
      tester,
      const RoomResults(
        winnerId: 'a',
        backupId: 'b',
        likes: {'a': 3, 'b': 2},
        participants: 4,
      ),
    );
    expect(find.text('Well, most of you wanted it'), findsOneWidget);
    expect(find.textContaining('3 of 4 liked it'), findsOneWidget);
    expect(find.text('Demo Tacos'), findsNothing, reason: 'backup is folded');
    expect(find.text('Place details from HERE'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);

    await tester.tap(find.text("It's always good to have a backup plan..."));
    // The winner fades out, then the backup grows into place.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Your backup plan'), findsOneWidget);
    expect(find.text('Demo Tacos'), findsOneWidget);
    expect(find.textContaining('2 of 4 liked it'), findsOneWidget);
    expect(find.text('Winner'), findsOneWidget);

    await tester.tap(find.byTooltip('Close the backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Demo Tacos'), findsNothing);
    expect(find.text('Well, most of you wanted it'), findsOneWidget);
  });

  testWidgets('with no voted backup, one random pick, teased first', (
    tester,
  ) async {
    // Pick the second of the other places, then roll the 1 in 4 tease.
    await showResults(
      tester,
      const RoomResults(
        winnerId: 'a',
        backupId: 'b',
        likes: {'a': 1, 'b': 0, 'c': 0, 'd': 0},
        participants: 3,
      ),
      random: ScriptedRandom([1, 0]),
    );
    expect(find.text('Some of you wanted it'), findsOneWidget);
    await tester.tap(find.text("It's always good to have a backup plan..."));
    await tester.pump();
    expect(
      find.textContaining('You were all too picky to have a backup plan!'),
      findsOneWidget,
    );

    await tester.tap(find.text('Pick a random one for me'));
    await tester.pumpAndSettle();
    expect(find.text('Haha! You fell for it!'), findsOneWidget);
    expect(find.text('Demo Noodles'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Your random backup plan'), findsOneWidget);
    expect(find.text('Demo Noodles'), findsOneWidget);
    expect(find.textContaining('picked at random'), findsOneWidget);
    expect(find.text('Pick a random one for me'), findsNothing);
  });

  testWidgets('most random picks come straight up', (tester) async {
    await showResults(
      tester,
      const RoomResults(
        winnerId: 'a',
        backupId: 'b',
        likes: {'a': 0, 'b': 0},
        participants: 2,
      ),
      random: ScriptedRandom([2, 3]),
    );
    expect(find.text('Oops, no one wanted anything'), findsOneWidget);
    await tester.tap(find.text("It's always good to have a backup plan..."));
    await tester.pump();
    await tester.tap(find.text('Pick a random one for me'));
    await tester.pumpAndSettle();
    expect(find.text('Haha! You fell for it!'), findsNothing);
    expect(find.text('Demo Curry'), findsOneWidget);
  });

  testWidgets('once the deck is gone there is nothing to pick from', (
    tester,
  ) async {
    await showResults(
      tester,
      RoomResults(
        winnerId: 'a',
        backupId: 'b',
        likes: const {'a': 2, 'b': 0},
        participants: 2,
        winnerCard: places[0],
        backupCard: places[1],
      ),
      deck: const [],
    );
    expect(find.text('Everyone wanted it'), findsOneWidget);
    await tester.tap(find.text("It's always good to have a backup plan..."));
    await tester.pump();
    expect(
      find.textContaining('Nothing else had even 1 vote.'),
      findsOneWidget,
    );
    expect(find.text('Pick a random one for me'), findsNothing);
  });

  testWidgets('copy says whether the browser allowed it', (tester) async {
    String? copied;
    var allow = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method != 'Clipboard.setData') return null;
        if (!allow) throw PlatformException(code: 'copy_fail');
        copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await showResults(
      tester,
      const RoomResults(winnerId: 'a', likes: {'a': 1}, participants: 1),
    );
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(copied, startsWith("We're going to Demo Pizza"));
    expect(find.text('Copied'), findsOneWidget);

    allow = false;
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(find.text('Could not copy. Try again.'), findsOneWidget);
  });

  testWidgets('a room with one place has no backup tile', (tester) async {
    await showResults(
      tester,
      const RoomResults(winnerId: 'a', likes: {'a': 1}, participants: 1),
      deck: [places.first],
    );
    expect(
      find.text("It's always good to have a backup plan..."),
      findsNothing,
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/screens/demo_screen.dart';
import 'package:whatdoyouwant/screens/intro_screen.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/demo_room_backend.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

import 'support/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('demo backend', () {
    test('friends join, vote, and the room settles on a winner', () async {
      final demo = DemoRoomBackend(pace: Duration.zero);
      final room = await demo.createRoom();
      final lobby = await demo.watch(room.id).first;
      expect(lobby.status, 'lobby');
      expect(lobby.people.map((p) => p.name), [null, ...demoFriends]);

      final deck = await demo.start(
        room.id,
        search: const SearchPreferences(radius: 3, deckSize: 5),
      );
      expect(deck, hasLength(5));
      expect(deck.every((card) => card.distance <= 3), isTrue);
      for (final (i, card) in deck.indexed) {
        await demo.vote(
          room.id,
          card,
          liked: i == 0,
          index: i,
          total: deck.length,
        );
      }
      final closed = await demo.watch(room.id).first;
      expect(closed.status, 'closed');
      expect(closed.results!.participants, 4);
      expect(deck.map((card) => card.id), contains(closed.results!.winnerId));
      demo.dispose();
    });

    test('a search leaves out excluded cuisines and stays in range', () async {
      final demo = DemoRoomBackend(pace: Duration.zero);
      final room = await demo.createRoom();
      final deck = await demo.start(
        room.id,
        search: const SearchPreferences(
          radius: 10,
          deckSize: 25,
          excludedCuisineIds: ['mexican'],
        ),
      );
      final names = deck.map((card) => card.name);
      expect(names, isNot(contains('Taco Spot')));
      expect(names, isNot(contains('Cantina Sol')));
      expect(names, isNot(contains('Mezze Table')), reason: 'over 10 mi');
      demo.dispose();
    });

    test('Tell Me What I Want rerolls five times from one pick', () async {
      final demo = DemoRoomBackend(pace: Duration.zero);
      var pick = await demo.createQuickPick(
        requestId: 'r',
        search: const SearchPreferences(),
      );
      final seen = {pick.restaurant.id};
      while (pick.rerollsLeft > 0) {
        pick = await demo.rerollQuickPick(pick);
        seen.add(pick.restaurant.id);
      }
      expect(seen, hasLength(6));
      demo.dispose();
    });
  });

  testWidgets('the demo hosts a room through to results, and links explain', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final demo = DemoRoomBackend(pace: Duration.zero);
    addTearDown(demo.dispose);
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        child: MaterialApp(home: DemoScreen(backend: demo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Demo: made-up places, nothing is saved'), findsOneWidget);

    await tester.tap(find.text('Host a room'));
    await tester.pumpAndSettle();
    for (final friend in demoFriends) {
      expect(find.text(friend), findsOneWidget);
    }
    // The other side: what friends see while the host gets ready.
    await tester.tap(find.text('What joining looks like'));
    // The food loader never settles; step past the page transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Waiting for the host...'), findsOneWidget);
    expect(find.text('What to expect'), findsOneWidget);
    expect(find.text("Who's deciding?"), findsOneWidget);
    await tester.tap(find.byTooltip('Back to the host view'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(find.text('Start Swiping'));
    await tester.tap(find.text('Start Swiping'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(SwipeScreen), findsOneWidget);
    expect(
      find.text('Demo: made-up places, nothing is saved'),
      findsOneWidget,
      reason: 'the banner stays over every screen',
    );

    for (
      var i = 0;
      i < 10 && find.byType(ResultsScreen).evaluate().isEmpty;
      i++
    ) {
      await tester.tap(find.byTooltip('Vote Yes'));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    for (var i = 0; i < 10 && find.text('Map').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(ResultsScreen), findsOneWidget);
    expect(find.text('Place details from HERE'), findsNothing);
    expect(find.text('Made-up places for the demo'), findsOneWidget);
    await tester.tap(find.text('Map'));
    await tester.pump();
    expect(find.textContaining('Demo places are made up'), findsOneWidget);

    await tester.tap(find.text('Exit demo'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoScreen), findsNothing);
  });

  testWidgets("the intro's last page opens the demo", (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        child: MaterialApp(
          home: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const IntroScreen(),
                        ),
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < IntroScreen.pages.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Try the demo'));
    await tester.pumpAndSettle();
    expect(find.byType(DemoScreen), findsOneWidget);
    expect(find.byType(IntroScreen), findsNothing);
    await tester.tap(find.text('Exit demo'));
    await tester.pumpAndSettle();
  });
}

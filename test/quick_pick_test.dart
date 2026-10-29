import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/quick_pick_screen.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/live_search.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';

import 'room_screens_test.dart' show FakeRoomBackend, app, deck;

void main() {
  Future<void> openQuickPick(
    WidgetTester tester,
    FakeRoomBackend backend, {
    SearchDefaultsStore? defaults,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        backend,
        const QuickPickScreen(),
        defaults: defaults ?? MemorySearchDefaults(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a Quick Pick spends one search and rerolls from the same deck', (
    tester,
  ) async {
    final backend =
        FakeRoomBackend()
          ..allowance = LiveSearchAllowance(
            weeklyCap: 20,
            used: 3,
            remaining: 17,
            resetsAt: DateTime.utc(2026, 11, 2),
            paused: false,
          );
    final defaults = MemorySearchDefaults(
      const SearchPreferences(
        unit: DistanceUnit.km,
        radius: 10,
        deckSize: 25,
        includedCuisineIds: ['thai'],
      ),
    );
    await openQuickPick(tester, backend, defaults: defaults);
    expect(find.text('Tell Me What I Want'), findsOneWidget);
    // One card shows at a time, so the setup has no number of options.
    expect(find.text('Within 10 km'), findsOneWidget);
    expect(find.text('Prefer Thai'), findsOneWidget);
    expect(
      find.text(
        '17 of 20 live searches left this week. A pick uses one; rerolls are free.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Change search'));
    await tester.pumpAndSettle();
    expect(find.text('Number of options'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    expect(backend.picks.single.$2, defaults.current.copyWith(deckSize: 10));
    expect(find.text('Demo Pizza'), findsOneWidget);
    expect(find.text('Distance: 0.40 km'), findsOneWidget);

    await tester.tap(find.text('Not feeling it (1 left)'));
    await tester.pumpAndSettle();
    expect(find.text('Demo Tacos'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'No more from this search'),
          )
          .onPressed,
      isNull,
    );
    expect((backend.picks.length, backend.rerolls), (1, 1));

    await tester.tap(find.text("Let's go here"));
    await tester.pumpAndSettle();
    expect(find.text("You're going to:"), findsOneWidget);
    expect(
      find.text('This listing has no map or contact details.'),
      findsOneWidget,
    );

    await tester.tap(find.text('New search'));
    await tester.pumpAndSettle();
    expect(find.text('Go Ahead, Tell Me'), findsOneWidget);
  });

  testWidgets('a retried Quick Pick reuses its request, a new one does not', (
    tester,
  ) async {
    final backend =
        FakeRoomBackend()
          ..pickError = FirebaseFunctionsException(
            code: 'unavailable',
            message: 'down',
          );
    await openQuickPick(tester, backend);
    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Restaurant search is unavailable right now. Try again in a minute.',
      ),
      findsOneWidget,
    );

    backend.pickError = null;
    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New search'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    final ids = [for (final (id, _) in backend.picks) id];
    expect(ids[0], ids[1], reason: 'a retry after a lost reply is free');
    expect(ids[2], isNot(ids[1]));
  });

  testWidgets('leaving a pick before choosing asks first', (tester) async {
    final backend = FakeRoomBackend();
    await openQuickPick(tester, backend);
    await tester.tap(find.text('Go Ahead, Tell Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Leave this pick?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(find.text(deck.first.name), findsOneWidget);
  });

  test('Quick Pick errors say what happened', () {
    FirebaseFunctionsException callable(String code, [Object? details]) =>
        FirebaseFunctionsException(code: code, message: code, details: details);
    expect(
      quickPickErrorMessage(callable('permission-denied')),
      startsWith('Only verified accounts can use Tell Me What I Want.'),
    );
    expect(
      rerollErrorMessage(
        callable('failed-precondition', {'reason': 'no-rerolls'}),
      ),
      startsWith('That was the last pick from this search.'),
    );
    expect(
      rerollErrorMessage(callable('permission-denied')),
      'This pick has expired. Start a new search.',
    );
  });

  test('a Quick Pick view becomes the card it points at', () {
    final pick = quickPickFrom(
      {
        'quickPickId': 'p1',
        'position': 1,
        'candidateId': 'b',
        'rerollsLeft': 3,
      },
      {for (final card in deck) card.id: card},
    );
    expect(
      (pick.id, pick.position, pick.restaurant.name, pick.rerollsLeft),
      ('p1', 1, 'Demo Tacos', 3),
    );
  });
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/insights.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/screens/account_screen.dart';
import 'package:whatdoyouwant/screens/insights_screen.dart';
import 'package:whatdoyouwant/screens/intro_screen.dart';
import 'package:whatdoyouwant/screens/place_card.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/place_links.dart';
import 'package:whatdoyouwant/services/room_backend.dart';
import 'package:whatdoyouwant/services/site_links.dart';
import 'package:whatdoyouwant/services/usage_counts.dart';

import 'account_service_test.dart' show FakeAuth, FakeUser;
import 'room_screens_test.dart' show FakeRoomBackend;

final today = DateTime.utc(2026, 11, 20);

InsightsReport sample() => InsightsReport.fromCallable({
  'days': {
    // An earlier period, for the comparison.
    '2026-11-10': {'roomsCompleted': 1, 'searchesQuickPick': 1},
    '2026-11-14': {
      'roomsCompleted': 2,
      'roomsUnanimous': 1,
      'roomsMajority': 1,
      'searchesRoom': 2,
      'searchesQuickPick': 2,
      'providerCalls': 4,
      'newGuests': 4,
      'newAccounts': 1,
      'returned_d1': 2,
      'returned_d7': 1,
      'activeGuests': 3,
      'activeAccounts': 1,
      'cuisinePicked_thai': 3,
      'cuisinePicked_pizza': 5,
      'tap_resultDirections': 2,
      'ballotsCast': 10,
      'ballotsLiked': 4,
    },
    '2026-11-20': {
      'searchesQuickPick': 1,
      'providerCalls': 1,
      'newGuests': 10,
      'weeklyCapHits': 1,
    },
    'not a day': {'roomsCompleted': 99},
  },
  'months': {
    '2026-11': {'providerCalls': 5, 'decks': 5},
  },
  'live': {'enabled': true, 'weeklyCap': 4, 'monthlyCallStop': 3500},
});

Widget scoped(
  FakeRoomBackend backend,
  Widget home, {
  UsageCounts? counts,
  bool demo = false,
}) => RoomBackendScope(
  backend: backend,
  usageCounts: counts,
  demo: demo,
  child: MaterialApp(home: home),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a period adds up its days and the shares the page shows', () {
    final week = sample().period(
      DateTime.utc(2026, 11, 14),
      today,
      today: today,
    );
    expect(week.decisions, 2 + 2 + 1);
    expect(week.providerCalls, 5);
    expect(week.decisionsPerCall, 1);
    expect(week.capHitShare, closeTo(1 / 6, 1e-9));
    expect(week.yesShare, 0.4);
    expect(week.directionsShare, closeTo(2 / 5, 1e-9));
    expect(week.averageDailySessions, closeTo(4 / 7, 1e-9));
    expect(week.top('cuisinePicked_'), [('pizza', 5), ('thai', 3)]);
    expect(week.daily((c) => c['providerCalls'] ?? 0), [4, 0, 0, 0, 0, 0, 1]);
    // Today's new guests can't have come back yet, so only the 14th counts.
    expect(week.returned(1), closeTo(2 / 5, 1e-9));
    expect(week.returned(7), null, reason: 'the 14th is not a week old');
    expect(week.returned(30), null);
    final before = sample().period(
      DateTime.utc(2026, 11, 7),
      DateTime.utc(2026, 11, 13),
      today: today,
    );
    expect(before.decisions, 2);
    expect(InsightsPeriod.share(1, 0), null);
  });

  test('the report ignores malformed entries', () {
    final report = InsightsReport.fromCallable({
      'days': {
        '2026-11-01': {'a': 1, 'b': 'x', 7: 2},
        'bad': 'x',
      },
      'months': {'2026-11': 'x'},
      'live': 'x',
    });
    expect(report.days, {
      '2026-11-01': {'a': 1},
    });
    expect(report.months, isEmpty);
    expect(report.weeklyCap, null);
    expect(insightsDay(DateTime(2026, 3, 9, 23)), '2026-03-09');
  });

  test('the insights page and site arrivals have their own links', () {
    expect(
      appLinkFrom(Uri.parse('https://example.test/app/insights'))?.target,
      AppLinkTarget.insights,
    );
    expect(
      takeSiteArrival(Uri.parse('https://example.test/app?from=site')),
      isTrue,
    );
    expect(
      takeSiteArrival(Uri.parse('https://example.test/app?from=site')),
      isFalse,
      reason: 'once per load',
    );
  });

  testWidgets('the owner sees the totals and can pick a longer range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend()..insights = sample();
    await tester.pumpWidget(scoped(backend, InsightsScreen(today: today)));
    await tester.pump();
    expect(backend.insightsAsked.single, (DateTime.utc(2026, 11, 7), today));
    expect(find.text('Decisions made'), findsOneWidget);
    expect(find.text('5'), findsWidgets);
    expect(find.text('+150% vs before'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Pizza'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pizza'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('30 days'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('30 days'));
    await tester.pump();
    expect(backend.insightsAsked.last, (DateTime.utc(2026, 9, 22), today));
  });

  for (final code in ['permission-denied', 'unauthenticated', 'unavailable']) {
    testWidgets('anyone else is quietly sent back home ($code)', (
      tester,
    ) async {
      final backend =
          FakeRoomBackend()
            ..insightsError = FirebaseFunctionsException(
              code: code,
              message: 'no',
            );
      await tester.pumpWidget(
        scoped(
          backend,
          Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => InsightsScreen(today: today),
                        ),
                      ),
                  child: const Text('Home'),
                ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(
        find.text('Insights'),
        findsNothing,
        reason: 'no title while asking',
      );
      await tester.pumpAndSettle();
      expect(find.byType(InsightsScreen), findsNothing);
      expect(find.text('Home'), findsOneWidget);
      expect(find.textContaining('owner'), findsNothing);
      expect(find.textContaining('Google'), findsNothing);
    });
  }

  testWidgets(
    'taps are counted only while the switch is on, and never in the demo',
    (tester) async {
      final backend = FakeRoomBackend();
      final counts = UsageCounts();
      final links = placeLinksFor(
        Restaurant(
          id: 'c1',
          name: 'Demo',
          address: '1 Main St',
          distance: 1,
          latitude: 40,
          longitude: -75,
        ),
      );
      Future<void> tapDirections({bool demo = false}) async {
        await tester.pumpWidget(
          scoped(
            backend,
            Scaffold(body: PlaceActions(links: links)),
            counts: counts,
            demo: demo,
          ),
        );
        await tester.tap(find.text('Directions'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      await tapDirections();
      expect(backend.events, ['resultDirections']);
      await counts.setEnabled(false);
      await tapDirections();
      expect(backend.events, ['resultDirections'], reason: 'switched off');
      await counts.setEnabled(true);
      await tapDirections(demo: true);
      expect(backend.events, [
        'resultDirections',
      ], reason: 'the demo counts nothing');
      final typed = placeLinksFor(
        Restaurant(
          id: 'own1',
          name: 'Our spot',
          address: '',
          distance: 0,
          userEntered: true,
        ),
      );
      await tester.pumpWidget(
        scoped(
          backend,
          Scaffold(body: PlaceActions(links: typed)),
          counts: counts,
        ),
      );
      await tester.tap(find.text('Directions'));
      await tester.pumpAndSettle();
      expect(backend.events.last, 'ownResultDirections');
    },
  );

  testWidgets('skipping the intro is counted', (tester) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(backend, const IntroScreen(), counts: UsageCounts()),
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(backend.events, ['introSkipped']);
  });

  test('only the switch is kept on the device; a sign-up after the demo '
      'counts once', () async {
    final counts = UsageCounts();
    await counts.setEnabled(false);
    final again = UsageCounts();
    await again.load();
    expect(again.enabled, isFalse);
    await again.setEnabled(true);
    final prefs = await SharedPreferences.getInstance();
    final backend = FakeRoomBackend();
    await again.signedUp(backend);
    await Future<void>.delayed(Duration.zero);
    expect(backend.events, isEmpty, reason: 'no demo first');
    again.markDemoSeen();
    expect(prefs.getKeys(), {
      'usageCounts.off',
    }, reason: 'the demo is not remembered on the device');
    await again.signedUp(backend);
    await again.signedUp(backend);
    await Future<void>.delayed(Duration.zero);
    expect(backend.events, ['signUpAfterDemo']);
    final nextVisit = UsageCounts();
    await nextVisit.load();
    await nextVisit.signedUp(backend);
    await Future<void>.delayed(Duration.zero);
    expect(backend.events, ['signUpAfterDemo']);
  });

  testWidgets('the usage counts switch sits under Privacy choices', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final counts = UsageCounts();
    final backend = FakeRoomBackend();
    final accounts = AccountService(
      FakeAuth(
        FakeUser()
          ..anonymous = false
          ..verified = true,
      ),
    );
    await tester.pumpWidget(
      RoomBackendScope(
        backend: backend,
        accounts: accounts,
        usageCounts: counts,
        child: MaterialApp(home: AccountScreen(accounts: accounts)),
      ),
    );
    await tester.pump();
    expect(find.text('Share anonymous usage counts'), findsNothing);
    await tester.tap(find.text('Privacy choices'));
    await tester.pumpAndSettle();
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Share anonymous usage counts',
    );
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pump();
    expect(counts.enabled, isFalse);
  });
}

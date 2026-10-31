import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/accessibility_screen.dart';
import 'package:whatdoyouwant/screens/account_screen.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/accessibility.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'account_service_test.dart' show FakeAuth, FakeUser;
import 'room_screens_test.dart' show FakeRoomBackend, deck, state;

Widget scoped(
  FakeRoomBackend backend,
  Widget home, {
  AccessibilitySettings? accessibility,
}) => RoomBackendScope(
  backend: backend,
  accessibility: accessibility,
  child: MaterialApp(home: home),
);

Widget swiping(FakeRoomBackend backend, {AccessibilitySettings? settings}) =>
    scoped(
      backend,
      SwipeScreen(
        roomCode: 'ROOM-ID',
        currentUser: AppUser(id: 'guest', name: 'Guest'),
        radius: 1,
        maxOptions: deck.length,
        restaurants: deck,
      ),
      accessibility: settings,
    );

Future<void> phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> wait(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a No cast by the timer is marked as the app\'s, not a tap', (
    tester,
  ) async {
    await phone(tester);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(swiping(backend));
    await tester.pump();
    await wait(tester, 16);
    expect(backend.votes, [(0, false)]);
    await tester.tap(find.bySemanticsLabel('Vote No'));
    await wait(tester, 1);
    expect(backend.votes, [(0, false), (1, false)]);
    expect(backend.autoVotes, [true, false]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with the setting on there is no countdown and no timer vote', (
    tester,
  ) async {
    await phone(tester);
    final backend = FakeRoomBackend();
    final settings = AccessibilitySettings()..noTimer = true;
    await tester.pumpWidget(swiping(backend, settings: settings));
    await tester.pump();
    expect(find.text('No timer'), findsOneWidget);
    expect(find.textContaining('No timer for you'), findsOneWidget);
    await wait(tester, 20);
    expect(backend.votes, isEmpty, reason: 'nothing is voted for them');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a screen reader turns the timer off by itself', (tester) async {
    await phone(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(swiping(backend));
    await tester.pump();
    await wait(tester, 20);
    expect(backend.votes, isEmpty);
    expect(find.text('No timer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the room is told, and the lobby says someone has no timer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
        accessibility: AccessibilitySettings()..noTimer = true,
      ),
    );
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    expect(backend.noTimers, [true]);
    expect(find.textContaining('votes without a timer'), findsNothing);
    backend.room.add(state(status: 'lobby', untimed: true));
    await tester.pump();
    await tester.pump();
    expect(
      find.text(
        'Someone in this room votes without a timer, so it may take a little longer.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('everyone else is not announced', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
        accessibility: AccessibilitySettings(),
      ),
    );
    backend.room.add(state(status: 'lobby'));
    await tester.pump();
    expect(backend.noTimers, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Account switch is kept on this device', (tester) async {
    final settings = AccessibilitySettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccessibilitySection(settings: settings)),
      ),
    );
    await tester.tap(find.text('No vote timer'));
    await tester.pump();
    expect(settings.noTimer, isTrue);
    final again = AccessibilitySettings();
    await again.load();
    expect(again.noTimer, isTrue);
  });

  testWidgets('with a screen reader the switch shows on and cannot be undone', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final settings = AccessibilitySettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AccessibilitySection(settings: settings)),
      ),
    );
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect((tile.value, tile.onChanged), (true, null));
    expect(find.textContaining('screen reader'), findsOneWidget);
  });

  testWidgets('the text size is kept on this device and enlarges the app', (
    tester,
  ) async {
    final settings = AccessibilitySettings();
    await tester.pumpWidget(
      MaterialApp(
        builder:
            (context, child) => AppTextSize(settings: settings, child: child!),
        home: AccessibilityScreen(settings: settings),
      ),
    );
    double scale() => MediaQuery.textScalerOf(
      tester.element(find.text('Text size')),
    ).scale(10);
    expect(scale(), 10);
    expect(find.text('100%'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(1000, 0));
    await tester.pump();
    expect(settings.textSize, AccessibilitySettings.maxTextSize);
    expect(find.text('200%'), findsOneWidget);
    expect(scale(), 20);
    final again = AccessibilitySettings();
    await again.load();
    expect(again.textSize, AccessibilitySettings.maxTextSize);
  });

  testWidgets('the app text size multiplies the device text size', (
    tester,
  ) async {
    final settings = AccessibilitySettings()..textSize = 1.5;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: AppTextSize(
          settings: settings,
          child: Builder(
            builder:
                (context) => Text(
                  '${MediaQuery.textScalerOf(context).scale(10)}',
                  textDirection: TextDirection.ltr,
                ),
          ),
        ),
      ),
    );
    expect(find.text('30.0'), findsOneWidget);
  });

  testWidgets('Account opens Accessibility features as a page of its own', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final user =
        FakeUser()
          ..anonymous = false
          ..verified = true;
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        accessibility: AccessibilitySettings(),
        child: MaterialApp(
          home: AccountScreen(accounts: AccountService(FakeAuth(user))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No vote timer'), findsNothing);
    // Verified shows as a check by the account type, explained on a tap.
    expect(find.text('Email verified'), findsNothing);
    expect(find.byTooltip('Email verified'), findsOneWidget);
    await tester.tap(find.text('Text size · Vote timer'));
    await tester.pumpAndSettle();
    expect(find.text('Accessibility features'), findsOneWidget);
    expect(find.text('No vote timer'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
  });
}

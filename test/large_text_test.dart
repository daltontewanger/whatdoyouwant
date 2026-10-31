import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/accessibility_screen.dart';
import 'package:whatdoyouwant/screens/account_screen.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/main_shell.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/search_setup_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/accessibility.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/search_defaults.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'room_screens_test.dart'
    show FakeRoomBackend, ShellAuth, app, deck, hostLobby, state;

/// Every main screen still fits a phone with big text: any overflow fails
/// the test.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.5, 2.0]) {
    Future<void> bigText(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    group('at ${(scale * 100).round()}% text', () {
      testWidgets('Home and Account', (tester) async {
        await bigText(tester);
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
        expect(find.byType(AccountScreen), findsOneWidget);
      });

      testWidgets('the host lobby', (tester) async {
        await bigText(tester);
        final backend = FakeRoomBackend();
        await tester.pumpWidget(hostLobby(backend));
        backend.room.add(state(status: 'lobby', untimed: true));
        await tester.pump();
        await tester.pump();
      });

      testWidgets('waiting for the host', (tester) async {
        await bigText(tester);
        final backend = FakeRoomBackend();
        await tester.pumpWidget(
          app(
            backend,
            WaitingForOptionsScreen(
              roomCode: 'ROOM-ID',
              currentUser: AppUser(id: 'guest', name: 'Guest'),
            ),
          ),
        );
        backend.room.add(state(status: 'lobby'));
        await tester.pump();
        await tester.pump();
      });

      testWidgets('swiping', (tester) async {
        await bigText(tester);
        await tester.pumpWidget(
          app(
            FakeRoomBackend(),
            SwipeScreen(
              roomCode: 'ROOM-ID',
              currentUser: AppUser(id: 'guest', name: 'Guest'),
              radius: 1,
              maxOptions: deck.length,
              restaurants: deck,
            ),
          ),
        );
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('results', (tester) async {
        await bigText(tester);
        final backend = FakeRoomBackend();
        await tester.pumpWidget(
          app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
        );
        backend.room.add(
          state(
            status: 'closed',
            ready: true,
            restaurants: deck,
            results: RoomResults(
              winnerId: deck.first.id,
              backupId: deck.last.id,
              likes: {deck.first.id: 2, deck.last.id: 1},
              participants: 2,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        final backup = find.text("It's always good to have a backup plan...");
        await tester.ensureVisible(backup);
        await tester.tap(backup);
        await tester.pumpAndSettle();
        final close = find.text('Winner');
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(backup, findsOneWidget);
      });

      testWidgets('joining, search settings and accessibility', (tester) async {
        await bigText(tester);
        final settings = AccessibilitySettings();
        for (final screen in [
          JoinRoomScreen(currentUser: AppUser(id: 'guest', name: 'Guest')),
          const SearchSetupScreen(initial: SearchPreferences()),
          AccessibilityScreen(settings: settings),
        ]) {
          await tester.pumpWidget(app(FakeRoomBackend(), screen));
          await tester.pump();
        }
      });
    });
  }
}

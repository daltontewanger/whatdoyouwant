import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/screens/intro_screen.dart';
import 'package:whatdoyouwant/screens/main_shell.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/intro_store.dart';
import 'package:whatdoyouwant/services/own_list.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'support/fakes.dart';

class MemoryIntroStore implements IntroStore {
  MemoryIntroStore({this.wasSeen = false});
  bool wasSeen;

  @override
  Future<bool> seen() async => wasSeen;

  @override
  Future<void> markSeen() async => wasSeen = true;
}

Widget shell(IntroStore intro) => RoomBackendScope(
  backend: FakeRoomBackend(),
  accounts: AccountService(ShellAuth()),
  ownList: MemoryOwnList(),
  intro: intro,
  child: const MaterialApp(home: MainShell()),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the first launch shows the intro once; Skip closes it', (
    tester,
  ) async {
    tallScreen(tester);
    final intro = MemoryIntroStore();
    await tester.pumpWidget(shell(intro));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(intro.wasSeen, isTrue);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(shell(intro));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing, reason: 'seen already');
  });

  testWidgets('the pages use the site wording and step with Next and Back', (
    tester,
  ) async {
    tallScreen(tester);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(shell(MemoryIntroStore()));
    await tester.pumpAndSettle();
    expect(IntroScreen.pages.map((page) => page.$1), [
      'Start a room',
      'Share the code',
      'Everyone swipes',
      'See where to eat',
      'More ways to want',
    ]);
    expect(
      find.text('Choose how far to look and how many spots to swipe.'),
      findsOneWidget,
    );
    expect(find.text('Back').hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('Page 1 of 5'), findsOneWidget);

    for (final (title, text) in IntroScreen.pages.skip(1)) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(text), findsOneWidget);
    }
    expect(find.bySemanticsLabel('Page 5 of 5'), findsOneWidget);
    expect(find.text('Tell Me What I Want'), findsOneWidget);
    expect(find.text('Skip').hitTestable(), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('See where to eat'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Let's eat"));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing);
    semantics.dispose();
  });

  testWidgets('the menu reopens the intro', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(shell(MemoryIntroStore(wasSeen: true)));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsNothing);
    await tester.tap(find.byTooltip("You've been found wanting"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How it works'));
    await tester.pumpAndSettle();
    expect(find.byType(IntroScreen), findsOneWidget);
    expect(find.text('Start a room'), findsOneWidget);
  });

  testWidgets('every page fits a small phone at the largest text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        child: MaterialApp(
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
          home: const IntroScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var page = 0; page < IntroScreen.pages.length; page++) {
      expect(tester.takeException(), isNull, reason: 'page ${page + 1}');
      if (page < IntroScreen.pages.length - 1) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
    }
  });
}

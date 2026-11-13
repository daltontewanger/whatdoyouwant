import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'support/fakes.dart';

const yesLine = 'Swipe right or tap "Yes" for a place you want.';
const noLine = 'Swipe left or tap "No" for a place you don\'t want.';
const timerLine =
    'Each place has a 15 second timer to decide. If it runs out, it counts as a no.';

void main() {
  testWidgets('waiting for the host explains what to expect above the lobby', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    backend.room.add(
      state(
        status: 'lobby',
        people: const [
          RoomPerson(name: 'Dee', host: true),
          RoomPerson(you: true),
        ],
      ),
    );
    await tester.pump();
    expect(find.text('Waiting for the host...'), findsOneWidget);
    expect(find.text('What to expect'), findsOneWidget);
    for (final line in [yesLine, noLine, timerLine]) {
      expect(find.text(line), findsOneWidget);
    }
    expect(find.text("Who's deciding?"), findsOneWidget);
    // The list sits between the loader and the lobby.
    expect(
      tester.getTopLeft(find.text('What to expect')).dy,
      lessThan(tester.getTopLeft(find.text("Who's deciding?")).dy),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the swipe screen keeps help folded above the count and card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        FakeRoomBackend(),
        SwipeScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          radius: 1,
          maxOptions: 2,
          restaurants: deck,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Decide what you want'), findsOneWidget);
    expect(find.text(yesLine), findsNothing, reason: 'folded at first');
    final help = find.text('What am I supposed to do?');
    final count = find.text('Option 1 of 2');
    expect(
      tester.getTopLeft(help).dy,
      lessThan(tester.getTopLeft(count).dy),
      reason: 'help comes first, then the count right over the card',
    );
    await tester.tap(help);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(yesLine), findsOneWidget);
    expect(find.text(timerLine), findsOneWidget);
    await tester.tap(help);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(yesLine), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

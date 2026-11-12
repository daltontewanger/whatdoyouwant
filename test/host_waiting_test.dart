import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/food_loader.dart';
import 'package:whatdoyouwant/screens/host_waiting.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'support/fakes.dart';

VoterProgress person({
  String? name,
  bool host = false,
  bool done = false,
  int idleSeconds = 0,
}) => VoterProgress(
  name: name,
  host: host,
  done: done,
  inactive: Duration(seconds: idleSeconds),
);

const hostSeat = [RoomPerson(host: true, you: true, name: 'Dee'), RoomPerson()];

void main() {
  group('who the host is waiting on', () {
    final checked = DateTime(2026, 11, 12, 18, 0);

    test('finishing early is offered only when everyone left has stopped', () {
      final host = person(host: true, done: true);
      expect(canFinishWithoutInactive([host]), isFalse);
      expect(
        canFinishWithoutInactive([host, person(idleSeconds: 30)]),
        isFalse,
      );
      expect(canFinishWithoutInactive([host, person(idleSeconds: 61)]), isTrue);
      // Someone still swiping keeps the room open for everyone.
      expect(
        canFinishWithoutInactive([
          host,
          person(idleSeconds: 90),
          person(idleSeconds: 5),
        ]),
        isFalse,
      );
    });

    test('the automatic finish comes 3 minutes after the last hand vote', () {
      final people = [
        person(host: true, done: true),
        person(idleSeconds: 70),
        person(idleSeconds: 150),
      ];
      expect(
        finishesWithoutThemAt(people, checked),
        checked.add(const Duration(seconds: 110)),
      );
      expect(finishesWithoutThemAt([person(idleSeconds: 10)], checked), isNull);
    });

    test('names: nicknames, one guest as Guest, more guests numbered', () {
      expect(voterLabels([person(host: true), person()]), ['You', 'Guest']);
      expect(
        voterLabels([
          person(name: 'Sam'),
          person(),
          person(),
          person(host: true),
        ]),
        ['Sam', 'Guest 1', 'Guest 2', 'You'],
      );
    });
  });

  Future<FakeRoomBackend> waitAsHost(
    WidgetTester tester,
    List<VoterProgress> people, {
    int votesIn = 0,
    int votesTotal = 0,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend =
        FakeRoomBackend()
          ..progress = HostProgress(
            people: people,
            votesIn: votesIn,
            votesTotal: votesTotal,
          );
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    backend.room.add(state(people: hostSeat));
    await tester.pump();
    await tester.pump();
    return backend;
  }

  testWidgets(
    'the host sees who is still voting; people done fold into one line',
    (tester) async {
      await waitAsHost(
        tester,
        [
          person(name: 'Sam', idleSeconds: 5),
          person(idleSeconds: 75),
          person(name: 'Ari', done: true),
          person(host: true, done: true),
        ],
        votesIn: 23,
        votesTotal: 40,
      );
      expect(find.text("You're done voting"), findsOneWidget);
      expect(find.byType(FoodLoader), findsOneWidget);
      expect(find.text('23 of 40 votes in'), findsOneWidget);
      // Only that someone is still going, never how far they've got.
      expect(find.text('Still voting'), findsOneWidget);
      expect(find.textContaining(' of 10'), findsNothing);
      expect(
        find.text(
          'If everyone still voting goes 3 minutes without a vote, voting stops automatically.',
        ),
        findsOneWidget,
      );
      expect(find.text('Inactive 1 min'), findsOneWidget);
      expect(find.text('You and 1 other'), findsOneWidget);
      // Sam is still swiping, so there is nothing to finish early yet.
      expect(find.text('Finish without inactive people'), findsNothing);
    },
  );

  testWidgets(
    'once only inactive people are left the host can finish without them',
    (tester) async {
      final backend = await waitAsHost(tester, [
        person(idleSeconds: 75),
        person(host: true, done: true),
      ]);
      expect(
        find.textContaining("Guest hasn't voted in a while"),
        findsOneWidget,
      );
      await tester.tap(find.text('Finish without inactive people'));
      await tester.pump();
      expect(backend.finishes, 1);
    },
  );

  testWidgets('everyone but the host keeps the simple waiting message', (
    tester,
  ) async {
    final backend = FakeRoomBackend()..progress = null;
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    backend.room.add(
      state(
        remaining: 2,
        people: const [
          RoomPerson(host: true, name: 'Dee'),
          RoomPerson(you: true),
        ],
      ),
    );
    await tester.pump();
    expect(find.text("You're done voting"), findsNothing);
    expect(find.text('Waiting for 2 more votes...'), findsOneWidget);
  });

  testWidgets('the result says when someone was finished without', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      app(backend, ResultsScreen(roomCode: 'ROOM-ID', restaurants: deck)),
    );
    backend.room.add(
      state(
        status: 'closed',
        ready: true,
        results: RoomResults(
          winnerId: deck.first.id,
          likes: {deck.first.id: 2},
          participants: 3,
          countedOut: 1,
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('One person stopped voting, so we finished without them.'),
      findsOneWidget,
    );
  });
}

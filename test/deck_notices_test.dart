import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/place_card.dart';
import 'package:whatdoyouwant/screens/results_screen.dart';
import 'package:whatdoyouwant/screens/swipe_screen.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';

import 'my_places_test.dart' show place, scoped, settle;
import 'room_screens_test.dart' show FakeRoomBackend;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, Object?> card(int n) => {
    'id': 'c$n',
    'name': 'Place $n',
    'address': '$n Example St',
    'distanceMeters': 1609,
  };

  test('notice cards slot in after their place, never at the end', () {
    final cards = deckRestaurants({
      'candidates': [card(1), card(2), card(3)],
      'notices': [
        {'id': 'n1', 'after': 2, 'title': 'A word', 'text': 'Thanks.'},
        {'id': 'n2', 'after': 3, 'title': 'Last', 'text': 'Never shown.'},
        {'id': 'n3', 'after': 1, 'title': 7, 'text': 'Malformed.'},
      ],
    });
    expect(cards.map((c) => c.id), ['c1', 'c2', 'n1', 'c3']);
    expect(cards[2].votable, isFalse);
    expect(cards[2].name, 'A word');
    expect(
      deckRestaurants({
        'candidates': [card(1)],
      }).single.votable,
      isTrue,
    );
  });

  test('a photo is kept only from a secure link', () {
    expect(
      cardRestaurant({
        ...card(1),
        'photoUrl': 'https://example.test/a.jpg',
      }).photoUrl,
      'https://example.test/a.jpg',
    );
    expect(
      cardRestaurant({
        ...card(1),
        'photoUrl': 'http://example.test/a.jpg',
      }).photoUrl,
      isNull,
    );
    expect(cardRestaurant(card(1)).photoUrl, isNull);
  });

  testWidgets('a notice card is passed without a vote and counts for nothing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    final cards = [
      place(1, 'Demo Taco'),
      Restaurant.notice(id: 'n1', title: 'A word from us', text: 'Thanks.'),
      place(2, 'Demo Fish'),
    ];
    await tester.pumpWidget(
      scoped(
        backend,
        SwipeScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
          radius: 1,
          maxOptions: 2,
          restaurants: cards,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Option 1 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Vote Yes'));
    await settle(tester);
    expect(find.text('Not a place to vote on'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byTooltip('Vote Yes'), findsNothing, reason: 'no vote here');
    expect(find.text('Option 2 of 2'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(backend.votes, [(0, true)], reason: 'passing a notice is no vote');
    await tester.tap(find.byTooltip('Vote No'));
    await settle(tester);
    expect(backend.votes, [(0, true), (1, false)]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('results leave notice cards out', (tester) async {
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        ResultsScreen(
          roomCode: 'ROOM-ID',
          restaurants: [
            Restaurant.notice(id: 'n1', title: 'A word', text: 'Thanks.'),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PlaceCard), findsNothing);
  });
}

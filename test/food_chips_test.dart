import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/restaurant.dart';
import 'package:whatdoyouwant/screens/food_chips.dart';
import 'package:whatdoyouwant/screens/place_card.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';

import 'room_screens_test.dart' show FakeRoomBackend, app;

void main() {
  test('icons match the specific word before the broad one', () {
    expect(foodIcon('Pizza'), Icons.local_pizza);
    expect(foodIcon('Sushi'), Icons.set_meal);
    expect(foodIcon('Japanese'), Icons.ramen_dining);
    expect(foodIcon('Barbecue & Southern'), Icons.outdoor_grill);
    expect(foodIcon('Something new'), Icons.restaurant);
  });

  test('chips fill two rows in order and leave out what needs a third', () {
    double widthOf(String label) => label.length * 10;
    List<String> fit(List<String> labels) =>
        fitInRows(labels, width: 200, rows: 2, widthOf: widthOf);
    expect(fit(['a' * 15, 'b' * 10, 'c' * 8, 'dd']), [
      'a' * 15,
      'b' * 10,
      'c' * 8,
    ], reason: '150 on row one, 100 + 80 on row two, no room for a third row');
    expect(fit(['a' * 18, 'b' * 18, 'c' * 18, 'd']), [
      'a' * 18,
      'b' * 18,
      'd',
    ], reason: 'a long one with no row left is skipped, a short one fits');
    expect(fit(['a' * 30, 'bb']), [
      'a' * 30,
      'bb',
    ], reason: 'the main food type always shows, shortened if it must be');
  });

  testWidgets('a swipe card shows four food types in full on two rows', (
    tester,
  ) async {
    const labels = ['Pizza', 'Italian', 'Wings', 'Sandwiches'];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: FoodChips(
                labels: [...labels, 'Burgers'],
                max: 4,
                maxRows: 2,
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in labels) {
      final text = tester.widget<Text>(find.text(label));
      final painter = TextPainter(
        text: TextSpan(text: label, style: text.style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(
        tester.getSize(find.text(label)).width,
        greaterThanOrEqualTo(painter.width - 0.5),
        reason: '$label is not cut short',
      );
    }
    expect(find.text('Burgers'), findsNothing, reason: 'four at most');
    expect(
      tester.getTopLeft(find.text('Pizza')).dy,
      lessThan(tester.getTopLeft(find.text('Sandwiches')).dy),
      reason: 'two rows',
    );
  });

  test('cards read food labels and dietary hints, ignoring anything else', () {
    final card = cardRestaurant({
      'id': 'c1',
      'name': 'Demo',
      'foodLabels': ['Thai', 7, ''],
      'dietary': ['vegan'],
    });
    expect(card.foodLabels, ['Thai']);
    expect(card.dietary, ['vegan']);
    expect(cardRestaurant({'id': 'c1', 'name': 'Demo'}).foodLabels, isEmpty);
  });

  test('dietary notes repeat the listing and never promise anything', () {
    expect(DietaryNote.textFor([]), isNull);
    expect(
      DietaryNote.textFor(['halal', 'vegan', 'vegetarian']),
      "The listing mentions vegetarian, vegan and halal options. We aren't "
      'connected to this place, so check with them if it matters to you.',
    );
  });

  testWidgets('a result shows three food types and opens the rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        FakeRoomBackend(),
        Scaffold(
          body: PlaceCard(
            restaurant: Restaurant(
              id: 'c1',
              name: 'Saigon Corner',
              address: '88 River Rd',
              distance: 1.2,
              foodLabels: const ['Vietnamese', 'Pho', 'Noodles', 'Sandwiches'],
              dietary: const ['vegetarian'],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Noodles'), findsOneWidget);
    expect(find.text('Sandwiches'), findsNothing);
    await tester.tap(find.text('+1 more'));
    await tester.pump();
    expect(find.text('Sandwiches'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(find.textContaining('mentions vegetarian options'), findsOneWidget);
  });
}

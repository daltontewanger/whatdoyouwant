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

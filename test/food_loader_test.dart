import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/food_loader.dart';

Widget loader(FoodLoader child, {bool calm = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: calm),
    child: Scaffold(body: Center(child: child)),
  ),
);

/// Each bubble's centre and how it is drawn right now.
List<(Offset, double, double)> bubbles(WidgetTester tester) => [
  for (final image in tester.widgetList(find.byType(Image)))
    (
      tester.getCenter(find.byWidget(image)),
      tester.getSize(find.byWidget(image)).width,
      tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.byWidget(image),
              matching: find.byType(Opacity),
            ),
          )
          .fold(1.0, (opacity, widget) => opacity * widget.opacity),
    ),
];

void main() {
  testWidgets('three bubbles pop in, turn together, then pop out', (
    tester,
  ) async {
    await tester.pumpWidget(loader(const FoodLoader()));
    expect(find.byType(Image), findsNWidgets(3));
    expect(
      tester.getSize(find.byType(FoodLoader)),
      const Size.square(FoodLoader.defaultSize),
    );

    // At the start they are still popping in: nothing has turned yet.
    await tester.pump(const Duration(milliseconds: 900));
    final resting = bubbles(tester);
    // Mid-way through the first turn they have moved round the centre.
    await tester.pump(const Duration(milliseconds: 900));
    final turning = bubbles(tester);
    for (var i = 0; i < 3; i++) {
      expect(turning[i].$1, isNot(resting[i].$1));
    }
    // Near the end of the loop all three have popped out.
    await tester.pump(const Duration(milliseconds: 4100));
    for (final image in tester.widgetList(find.byType(Image))) {
      // As drawn on screen, after the pop's scaling.
      final drawn =
          tester.getBottomRight(find.byWidget(image)).dx -
          tester.getTopLeft(find.byWidget(image)).dx;
      expect(drawn.abs(), lessThan(1));
    }
  });

  testWidgets('with reduced motion the bubbles stay put and fade', (
    tester,
  ) async {
    await tester.pumpWidget(loader(const FoodLoader(), calm: true));
    final first = bubbles(tester);
    await tester.pump(const Duration(milliseconds: 600));
    final later = bubbles(tester);
    for (var i = 0; i < 3; i++) {
      expect(later[i].$1, first[i].$1, reason: 'no turning');
      expect(later[i].$2, first[i].$2, reason: 'no popping');
    }
    expect([
      for (final bubble in later) bubble.$3,
    ], everyElement(inInclusiveRange(0.35, 1.0)));
    expect(later.first.$3, isNot(first.first.$3), reason: 'it fades');
    expect(
      find.descendant(
        of: find.byType(FoodLoader),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('screen readers hear one label, not three pictures', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(loader(const FoodLoader(label: 'Finding places')));
    expect(find.bySemanticsLabel('Finding places'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the size and loop length can be changed', (tester) async {
    await tester.pumpWidget(
      loader(
        const FoodLoader(
          size: FoodLoader.largeSize,
          duration: Duration(seconds: 8),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(FoodLoader)),
      const Size.square(FoodLoader.largeSize),
    );
    // Turns start 22% into the loop: 1.76 s of 8 s, later than with 6 s.
    await tester.pump(const Duration(milliseconds: 1600));
    final before = bubbles(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(bubbles(tester)[0].$1, before[0].$1);
    await tester.pump(const Duration(milliseconds: 600));
    expect(bubbles(tester)[0].$1, isNot(before[0].$1));
  });
}

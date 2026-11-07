import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/home_banner.dart';

Widget _host({bool calm = false, double width = 360}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: calm),
    child: Scaffold(
      body: Center(child: SizedBox(width: width, child: const HomeBanner())),
    ),
  ),
);

void main() {
  testWidgets('shows both lines and a food card', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('What do you want?!'), findsOneWidget);
    expect(find.text("It's not that simple!"), findsOneWidget);
    expect(find.text('Pizza'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('What do you want')), findsOneWidget);
  });

  testWidgets('swipes through the foods once, then rests until tapped', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('Pizza'), findsOneWidget);

    // One full swipe moves Burgers to the front, the next brings Sushi.
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.text('Burgers'), findsOneWidget);
    expect(find.text('Pizza'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump();
    expect(find.text('Sushi'), findsOneWidget);

    // The third swipe brings Pizza back and the banner settles there.
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.tap(find.byType(HomeBanner));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('holds still when animations are turned off', (tester) async {
    await tester.pumpWidget(_host(calm: true));
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Pizza'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('fits a narrow phone without overflowing', (tester) async {
    await tester.pumpWidget(_host(width: 260));
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
  });
}

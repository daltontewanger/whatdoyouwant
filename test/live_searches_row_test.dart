import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/live_searches_row.dart';
import 'package:whatdoyouwant/services/live_search.dart';

import 'support/fakes.dart';

LiveSearchAllowance allowance({
  int cap = 10,
  int remaining = 7,
  bool paused = false,
  bool newAccount = false,
}) => LiveSearchAllowance(
  weeklyCap: cap,
  used: cap - remaining,
  remaining: remaining,
  resetsAt: DateTime.utc(2026, 11, 16),
  paused: paused,
  newAccount: newAccount,
);

void main() {
  Future<FakeRoomBackend> show(
    WidgetTester tester,
    LiveSearchAllowance? value,
  ) async {
    final backend = FakeRoomBackend()..allowance = value;
    await tester.pumpWidget(
      app(backend, const Scaffold(body: LiveSearchesRow())),
    );
    await tester.pump();
    return backend;
  }

  int filledDots(WidgetTester tester) =>
      tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (c) =>
                c.decoration is BoxDecoration &&
                (c.decoration as BoxDecoration).shape == BoxShape.circle &&
                (c.decoration as BoxDecoration).color!.a == 1,
          )
          .length;

  testWidgets('shows how many live searches are left, with a dot each', (
    tester,
  ) async {
    await show(tester, allowance());
    expect(find.text('Live searches'), findsOneWidget);
    expect(find.text('7 of 10 left'), findsOneWidget);
    expect(filledDots(tester), 7);
    expect(
      find.text('More arrive ${resetTimeText(DateTime.utc(2026, 11, 16))}.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets('a new account sees its first-day allowance', (tester) async {
    await show(tester, allowance(cap: 3, remaining: 2, newAccount: true));
    expect(find.text('2 of 3 left today'), findsOneWidget);
    expect(find.textContaining('New accounts start with 3.'), findsOneWidget);
  });

  testWidgets('paused live search says so', (tester) async {
    await show(tester, allowance(paused: true));
    expect(find.text('Paused for now'), findsOneWidget);
    expect(filledDots(tester), 0);
  });

  testWidgets('guests and unverified accounts see nothing', (tester) async {
    await show(tester, null);
    expect(find.text('Live searches'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';

void main() {
  testWidgets('joining with an empty code stays on the form and explains why', (
    tester,
  ) async {
    // No Firebase initialization: invalid input must not reach the backend.
    await tester.pumpWidget(
      MaterialApp(
        home: JoinRoomScreen(
          currentUser: AppUser(id: 'fixture-guest', name: 'Guest'),
        ),
      ),
    );
    expect(find.text('Join a Room'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Join'));
    await tester.pump();
    expect(find.text('Please enter a room code.'), findsOneWidget);
    expect(find.byType(JoinRoomScreen), findsOneWidget);
    expect(find.byType(WaitingForOptionsScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

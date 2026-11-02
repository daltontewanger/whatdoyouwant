import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/models/user.dart';
import 'package:whatdoyouwant/screens/account_screen.dart';
import 'package:whatdoyouwant/screens/join_screen.dart';
import 'package:whatdoyouwant/screens/room_roster.dart';
import 'package:whatdoyouwant/screens/room_screen.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/callable_room_backend.dart';
import 'package:whatdoyouwant/services/nickname.dart';
import 'package:whatdoyouwant/services/room_backend.dart';

import 'account_service_test.dart' show FakeAuth, FakeUser;
import 'room_screens_test.dart' show FakeRoomBackend;

FakeUser verifiedAccount() =>
    FakeUser()
      ..anonymous = false
      ..verified = true;

RoomState lobby(List<RoomPerson> people) => RoomState(
  id: 'ROOM-ID',
  joinCode: 'AB3K7X',
  creatorId: 'host',
  status: 'lobby',
  memberCount: people.length,
  restaurants: const [],
  myVoteCount: 0,
  resultsReady: false,
  people: people,
);

Widget scoped(FakeRoomBackend backend, Widget home, {FakeUser? user}) =>
    RoomBackendScope(
      backend: backend,
      accounts: AccountService(FakeAuth(user)),
      child: MaterialApp(home: home),
    );

void main() {
  test('the roster lists the host, then you, then names, then guests', () {
    final people = roomPeople({
      's1': {'name': 'zed', 'host': false},
      's2': {'name': null, 'host': false},
      's3': {'name': 'Dalton', 'host': true},
      's4': {'name': 'Amy', 'host': false},
      's5': {'name': 'WinnerDinner', 'host': false},
      'bad': 'not a person',
    }, 's5');
    expect(
      [
        for (final p in people)
          '${p.name}${p.host ? '*' : ''}${p.you ? '!' : ''}',
      ],
      ['Dalton*', 'WinnerDinner!', 'Amy', 'zed', 'null'],
    );
    expect(roomPeople(null, null), isEmpty);
  });

  test('nickname format matches the server', () {
    for (final ok in ['Dalton', 'J.R.', "O'Brien", 'Zoë', '李小龙', '', '  ']) {
      expect(Nickname.problem(ok), isNull, reason: ok);
    }
    for (final bad in [
      'a',
      'x' * 21,
      '<b>',
      'evil.com',
      'a@b',
      '...',
      'https://x',
    ]) {
      expect(Nickname.problem(bad), isNotNull, reason: bad);
    }
    expect(Nickname.tidy('  Winner   Dinner '), 'Winner Dinner');
  });

  testWidgets('the lobby shows who is here, with guests folded together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
        user: verifiedAccount(),
      ),
    );
    backend.room.add(
      lobby(const [
        RoomPerson(name: 'Dalton', host: true, you: true),
        RoomPerson(name: 'WinnerDinner'),
        RoomPerson(),
        RoomPerson(),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text("Who's here"), findsOneWidget);
    expect(find.text('4 of 15'), findsOneWidget);
    expect(find.text('Dalton'), findsOneWidget);
    expect(find.text('host · you'), findsOneWidget);
    expect(find.text('WinnerDinner'), findsOneWidget);
    expect(find.text('2 guests'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        "Who's here, 4 people: Dalton, host, you; WinnerDinner; 2 guests",
      ),
      findsOneWidget,
    );
    expect(find.byType(NicknameNudge), findsNothing, reason: 'already named');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an account without a nickname is nudged to add one', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        RoomScreen(
          currentUser: AppUser(id: 'host', name: 'Host'),
          roomCode: 'ROOM-ID',
          joinCode: 'AB3K7X',
        ),
        user: verifiedAccount(),
      ),
    );
    backend.room.add(lobby(const [RoomPerson(host: true, you: true)]));
    await tester.pump();
    await tester.pump();
    expect(find.text('Host'), findsOneWidget);
    await tester.tap(find.byType(NicknameNudge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'evil.com');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text("A nickname can't look like a web address."),
      findsOneWidget,
    );
    expect(backend.nicknames, isEmpty, reason: 'checked on the device first');

    backend.nicknameError = FirebaseFunctionsException(
      code: 'invalid-argument',
      message: '',
      details: {'reason': 'nickname-blocked'},
    );
    await tester.enterText(find.byType(TextField), 'Rude Word');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      find.text("That nickname isn't allowed. Try a different one."),
      findsOneWidget,
    );

    backend.nicknameError = null;
    await tester.enterText(find.byType(TextField), '  Dalton  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(backend.nicknames.last, 'Dalton');
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('guests are never nudged; they cannot have a nickname', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend();
    await tester.pumpWidget(
      scoped(
        backend,
        WaitingForOptionsScreen(
          roomCode: 'ROOM-ID',
          currentUser: AppUser(id: 'guest', name: 'Guest'),
        ),
        user: FakeUser(),
      ),
    );
    backend.room.add(
      lobby(const [
        RoomPerson(name: 'Dalton', host: true),
        RoomPerson(you: true),
        RoomPerson(),
      ]),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text("Who's here"), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('you'), findsOneWidget);
    expect(find.text('1 guest'), findsOneWidget);
    expect(find.byType(NicknameNudge), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Account shows the nickname and changes it', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final backend = FakeRoomBackend()..savedNickname = 'Dalton';
    final auth = FakeAuth(verifiedAccount());
    await tester.pumpWidget(
      RoomBackendScope(
        backend: backend,
        accounts: AccountService(auth),
        child: MaterialApp(home: AccountScreen(accounts: AccountService(auth))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dalton · Shown to people in your rooms'), findsOneWidget);
    await tester.tap(find.text('Nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(backend.nicknames, ['']);
    expect(find.text('Not set · You show as "Guest" in rooms'), findsOneWidget);
  });

  testWidgets('guests see no nickname row on Account', (tester) async {
    final auth = FakeAuth(FakeUser());
    await tester.pumpWidget(
      RoomBackendScope(
        backend: FakeRoomBackend(),
        accounts: AccountService(auth),
        child: MaterialApp(home: AccountScreen(accounts: AccountService(auth))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NicknameTile), findsNothing);
  });
}

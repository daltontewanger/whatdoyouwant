import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/services/backend_session.dart';

void main() {
  test('nothing starts until something needs the backend', () async {
    var protected = 0;
    var guests = 0;
    var signedIn = false;
    final session = BackendSession(
      protect: () async => protected++,
      signIn: () async {
        guests++;
        signedIn = true;
      },
      signedIn: () => signedIn,
    );
    expect((protected, guests, session.isStarted), (0, 0, false));

    // Signing in needs App Check but not a guest account.
    await session.protect();
    expect((protected, guests, session.isStarted), (1, 0, false));

    await Future.wait([session.ready(), session.ready()]);
    expect((protected, guests, session.isStarted), (1, 1, true));
    await session.whenStarted;

    // Signed out later: the next call starts a new guest session.
    signedIn = false;
    await session.ready();
    expect((protected, guests), (1, 2));
  });

  test('a failed start is tried again on the next call', () async {
    var attempts = 0;
    final session = BackendSession(
      protect: () async {
        if (++attempts == 1) throw StateError('offline');
      },
      signIn: () async {},
      signedIn: () => true,
    );
    await expectLater(session.ready(), throwsStateError);
    expect(session.isStarted, isFalse);
    await session.ready();
    expect((attempts, session.isStarted), (2, true));
  });

  test(
    'counts wait for the session and are dropped if it never starts',
    () async {
      var signedIn = false;
      final session = BackendSession(
        protect: () async {},
        signIn: () async => signedIn = true,
        signedIn: () => signedIn,
      );
      final sent = <String>[];
      final counts = WaitingCounts(session, (name) async {
        sent.add(name);
      }, limit: 2);
      await counts.count('openedFromSite');
      await counts.count('introFinished');
      await counts.count('introSkipped');
      expect(sent, isEmpty, reason: 'a visit that does nothing sends nothing');
      await session.ready();
      await pumpEventQueue();
      expect(sent, [
        'openedFromSite',
        'introFinished',
      ], reason: 'kept to the limit');
      await counts.count('quickPickChosen');
      expect(sent.last, 'quickPickChosen');
    },
  );
}

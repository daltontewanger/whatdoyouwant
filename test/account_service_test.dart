import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/screens/account_preview_screen.dart';

class FakeUser extends Fake implements User {
  bool anonymous = true;
  bool verified = false;
  bool failLink = false;
  bool failReauth = false;
  String? reloadError;
  String? reloadMessage;
  final calls = <String>[];
  @override
  bool get isAnonymous => anonymous;
  @override
  bool get emailVerified => verified;
  @override
  String get email => 'fixture@example.test';
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    calls.add('link');
    if (failLink) {
      throw FirebaseAuthException(code: 'credential-already-in-use');
    }
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    calls.add('verify');
  }

  @override
  Future<void> reload() async {
    calls.add('reload');
    if (reloadError != null) {
      throw FirebaseAuthException(code: reloadError!, message: reloadMessage);
    }
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    calls.add('token:$forceRefresh');
    return null;
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    calls.add('reauth');
    if (failReauth) throw FirebaseAuthException(code: 'invalid-credential');
    return FakeCredential();
  }

  @override
  Future<void> delete() async {
    calls.add('delete');
  }
}

class FakeCredential extends Fake implements UserCredential {}

class FakeAuth extends Fake implements FirebaseAuth {
  User? user;
  int creates = 0;
  int guests = 0;
  int signOuts = 0;
  String? resetError;
  FakeAuth(this.user);
  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    guests++;
    user = FakeUser();
    return FakeCredential();
  }

  @override
  Stream<User?> userChanges() => Stream.value(user);
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    return FakeCredential();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    if (resetError != null) throw FirebaseAuthException(code: resetError!);
  }
}

void main() {
  testWidgets(
    'short registration password shows guidance without contacting Auth',
    (tester) async {
      final user = FakeUser();
      final auth = FakeAuth(user);
      await tester.pumpWidget(
        MaterialApp(home: AccountPreviewScreen(accounts: AccountService(auth))),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('New accounts require at least 6 characters.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byType(TextField).at(0),
        'fixture@example.test',
      );
      await tester.enterText(find.byType(TextField).at(1), '1234');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use a password with at least 6 characters.'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(user.calls, isEmpty);
      expect(user.isAnonymous, true);
      expect(auth.creates, 0);
    },
  );
  test(
    'signed-out registration rejects short passwords and accepts six characters',
    () async {
      final auth = FakeAuth(null);
      await expectLater(
        AccountService(auth).register('fixture@example.test', '12345'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'weak-password',
          ),
        ),
      );
      expect(auth.creates, 0);
      await AccountService(auth).register('fixture@example.test', '123456');
      expect(auth.creates, 1);
    },
  );
  testWidgets('existing-account sign-in asks before leaving guest identity', (
    tester,
  ) async {
    final user = FakeUser();
    final auth = FakeAuth(user);
    await tester.pumpWidget(
      MaterialApp(home: AccountPreviewScreen(accounts: AccountService(auth))),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Switch to an existing account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.currentUser, same(user));
    expect(user.calls, isEmpty);
  });
  test(
    'registration links guest and never creates a replacement identity',
    () async {
      final user = FakeUser();
      final auth = FakeAuth(user);
      await AccountService(
        auth,
      ).register('fixture@example.test', 'local-fixture-only');
      expect(user.calls, ['link']);
      expect(auth.creates, 0);
      expect(auth.currentUser, same(user));
    },
  );
  test(
    'link conflict preserves guest and does not fall back to sign-in or creation',
    () async {
      final user = FakeUser()..failLink = true;
      final auth = FakeAuth(user);
      await expectLater(
        AccountService(
          auth,
        ).register('fixture@example.test', 'local-fixture-only'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(auth.currentUser, same(user));
      expect(user.isAnonymous, true);
      expect(auth.creates, 0);
    },
  );
  test(
    'registered users cannot accidentally create replacement accounts',
    () async {
      final auth = FakeAuth(FakeUser()..anonymous = false);
      await expectLater(
        AccountService(
          auth,
        ).register('fixture@example.test', 'local-fixture-only'),
        throwsStateError,
      );
      expect(auth.creates, 0);
    },
  );
  test('guest session starts one only when there is no saved user', () async {
    final auth = FakeAuth(null);
    await AccountService(auth).guest();
    expect(auth.guests, 1);
    final saved = FakeUser();
    final restored = FakeAuth(saved);
    await AccountService(restored).guest();
    expect(saved.calls, ['reload']);
    expect(restored.guests, 0);
    expect(restored.currentUser, same(saved));
  });
  test(
    'a saved session for a deleted account is replaced by a new guest',
    () async {
      for (final code in [
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      ]) {
        final stale = FakeUser()..reloadError = code;
        final auth = FakeAuth(stale);
        await AccountService(auth).guest();
        expect(auth.signOuts, 1, reason: code);
        expect(auth.guests, 1, reason: code);
        expect(auth.currentUser, isNot(same(stale)), reason: code);
      }
    },
  );
  test(
    'the emulator refresh-token rejection seen on Android also resets the session',
    () async {
      final stale =
          FakeUser()
            ..reloadError = 'unknown'
            ..reloadMessage =
                'An internal error has occurred. [ INVALID_REFRESH_TOKEN ]';
      final auth = FakeAuth(stale);
      await AccountService(auth).guest();
      expect(auth.guests, 1);
      final other =
          FakeUser()
            ..reloadError = 'unknown'
            ..reloadMessage = 'An internal error has occurred. [ UNAVAILABLE ]';
      final kept = FakeAuth(other);
      await AccountService(kept).guest();
      expect(kept.guests, 0);
      expect(kept.currentUser, same(other));
    },
  );
  test('an offline start keeps the saved session', () async {
    final saved =
        FakeUser()
          ..anonymous = false
          ..reloadError = 'network-request-failed';
    final auth = FakeAuth(saved);
    await AccountService(auth).guest();
    expect(auth.signOuts, 0);
    expect(auth.guests, 0);
    expect(auth.currentUser, same(saved));
  });
  test('verification refresh reloads profile and forces new claims', () async {
    final user = FakeUser()..anonymous = false;
    await AccountService(FakeAuth(user)).refreshVerification();
    expect(user.calls, ['reload', 'token:true']);
  });
  test(
    'reset hides missing-account response but surfaces network failures',
    () async {
      final auth = FakeAuth(null)..resetError = 'user-not-found';
      await AccountService(auth).resetPassword('missing@example.test');
      auth.resetError = 'network-request-failed';
      await expectLater(
        AccountService(auth).resetPassword('missing@example.test'),
        throwsA(isA<FirebaseAuthException>()),
      );
    },
  );
  test(
    'registered account deletion requires successful reauthentication',
    () async {
      final user =
          FakeUser()
            ..anonymous = false
            ..failReauth = true;
      await expectLater(
        AccountService(FakeAuth(user)).deleteLocalAccount('wrong'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(user.calls, ['reauth']);
      user.failReauth = false;
      await AccountService(
        FakeAuth(user),
      ).deleteLocalAccount('local-fixture-only');
      expect(user.calls, ['reauth', 'reauth', 'delete']);
    },
  );
}

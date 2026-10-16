import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/screens/account_screen.dart';
import 'package:whatdoyouwant/screens/create_account_screen.dart';

class FakeUser extends Fake implements User {
  bool anonymous = true;
  bool verified = false;
  bool failLink = false;
  bool failReauth = false;
  String? reloadError;
  String? reloadMessage;
  List<String> providers = ['password'];
  final calls = <String>[];
  @override
  List<UserInfo> get providerData => [for (final id in providers) FakeInfo(id)];
  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) async {
    calls.add('link:${provider.providerId}');
    if (failLink) {
      throw FirebaseAuthException(code: 'credential-already-in-use');
    }
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) async {
    calls.add('popup:${provider.providerId}');
    anonymous = false;
    return FakeCredential();
  }

  @override
  Future<UserCredential> reauthenticateWithProvider(
    AuthProvider provider,
  ) async {
    calls.add('reauth:${provider.providerId}');
    return FakeCredential();
  }

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

class FakeInfo extends Fake implements UserInfo {
  FakeInfo(this.providerId);
  @override
  final String providerId;
}

class FakeAuth extends Fake implements FirebaseAuth {
  User? user;
  int creates = 0;
  int guests = 0;
  int signOuts = 0;
  int providerSignIns = 0;
  int emailSignIns = 0;
  String? resetError;
  String? signInError;
  bool signInVerified = false;
  final _changes = StreamController<User?>.broadcast();
  FakeAuth(this.user);
  void _set(User? next) {
    user = next;
    _changes.add(next);
  }

  @override
  User? get currentUser => user;
  @override
  Future<void> signOut() async {
    signOuts++;
    _set(null);
  }

  @override
  Future<UserCredential> signInAnonymously() async {
    guests++;
    _set(FakeUser());
    return FakeCredential();
  }

  @override
  Stream<User?> userChanges() async* {
    yield user;
    yield* _changes.stream;
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider provider) async {
    providerSignIns++;
    _set(FakeUser()..anonymous = false);
    return FakeCredential();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    emailSignIns++;
    if (signInError != null) throw FirebaseAuthException(code: signInError!);
    _set(
      FakeUser()
        ..anonymous = false
        ..verified = signInVerified,
    );
    return FakeCredential();
  }

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
  group('create account screen', () {
    Future<FakeUser> open(WidgetTester tester, FakeAuth auth) async {
      await tester.pumpWidget(
        MaterialApp(home: CreateAccountScreen(accounts: AccountService(auth))),
      );
      await tester.pumpAndSettle();
      return auth.user as FakeUser;
    }

    Future<void> fill(
      WidgetTester tester,
      String password,
      String repeat,
    ) async {
      await tester.enterText(
        find.byType(TextField).at(0),
        'fixture@example.test',
      );
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.enterText(find.byType(TextField).at(2), repeat);
    }

    testWidgets('short passwords get guidance without contacting Auth', (
      tester,
    ) async {
      final auth = FakeAuth(FakeUser());
      final user = await open(tester, auth);
      await fill(tester, '1234', '1234');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use a password with at least 6 characters.'),
        findsOneWidget,
      );
      expect(user.calls, isEmpty);
      expect(auth.creates, 0);
    });

    testWidgets('mismatched passwords are caught before contacting Auth', (
      tester,
    ) async {
      final auth = FakeAuth(FakeUser());
      final user = await open(tester, auth);
      await fill(tester, 'secret123', 'secret124');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match.'), findsOneWidget);
      expect(user.calls, isEmpty);
    });

    testWidgets(
      'submitting the repeated password links the guest and requests verification',
      (tester) async {
        final auth = FakeAuth(FakeUser());
        final user = await open(tester, auth);
        await fill(tester, 'secret123', 'secret123');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(user.calls, ['link', 'verify']);
        expect(auth.currentUser, same(user), reason: 'the guest UID is kept');
        expect(find.byType(CreateAccountScreen), findsNothing);
      },
    );
  });

  group('sign in', () {
    Future<FakeAuth> openAsGuest(WidgetTester tester) async {
      final auth = FakeAuth(FakeUser());
      await tester.pumpWidget(
        MaterialApp(home: AccountScreen(accounts: AccountService(auth))),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'fixture@example.test',
      );
      await tester.enterText(find.byType(TextField).at(1), 'secret123');
      return auth;
    }

    testWidgets(
      'pressing enter in the password field signs in after the guest confirms',
      (tester) async {
        final auth = await openAsGuest(tester);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        expect(find.text('Sign in to an existing account?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(auth.emailSignIns, 0);

        await tester.showKeyboard(find.byType(TextField).at(1));
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(auth.emailSignIns, 1);
        expect(find.text('Signed in as'), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
      },
    );

    for (final (code, text) in [
      (
        'user-not-found',
        'No account uses that email. If you are new, create an account below.',
      ),
      (
        'wrong-password',
        'That password is incorrect. Try again or use Forgot password.',
      ),
      (
        'invalid-credential',
        'Email or password is incorrect. Check them, or create an account if you are new.',
      ),
    ]) {
      testWidgets('a failed sign-in ($code) explains what to do', (
        tester,
      ) async {
        final auth = await openAsGuest(tester);
        auth.signInError = code;
        await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
        expect(auth.currentUser!.isAnonymous, isTrue);
      });
    }

    for (final verified in [true, false]) {
      testWidgets(
        verified
            ? 'a verified sign-in returns to the screen that opened Account'
            : 'an unverified sign-in stays to finish verifying',
        (tester) async {
          final auth = FakeAuth(null)..signInVerified = verified;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed:
                            () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => AccountScreen(
                                      accounts: AccountService(auth),
                                    ),
                              ),
                            ),
                        child: const Text('Open account'),
                      ),
                    ),
              ),
            ),
          );
          await tester.tap(find.text('Open account'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).at(0),
            'fixture@example.test',
          );
          await tester.enterText(find.byType(TextField).at(1), 'secret123');
          await tester.testTextInput.receiveAction(TextInputAction.go);
          await tester.pumpAndSettle();
          expect(auth.emailSignIns, 1);
          if (verified) {
            expect(find.byType(AccountScreen), findsNothing);
            expect(find.text('Signed in as fixture@example.test.'), findsOne);
          } else {
            expect(find.byType(AccountScreen), findsOneWidget);
            expect(find.text('Email not verified yet'), findsOneWidget);
          }
        },
      );
    }

    testWidgets('signing out leaves a fresh guest session', (tester) async {
      final auth = FakeAuth(FakeUser()..anonymous = false);
      await tester.pumpWidget(
        MaterialApp(home: AccountScreen(accounts: AccountService(auth))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect((auth.signOuts, auth.guests), (1, 1));
      expect(auth.currentUser!.isAnonymous, isTrue);
      expect(find.text('Signed out. You are playing as a guest.'), findsOne);
    });

    testWidgets('deleting an email account asks for the password', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final user = FakeUser()..anonymous = false;
      final auth = FakeAuth(user);
      await tester.pumpWidget(
        MaterialApp(home: AccountScreen(accounts: AccountService(auth))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'secret123');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(user.calls, ['reauth', 'delete']);
      expect(find.text('Account deleted.'), findsOneWidget);
      expect(auth.currentUser!.isAnonymous, isTrue);
    });
  });
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
  test(
    'server deletion runs after reauthentication and then clears the local session',
    () async {
      final user = FakeUser()..anonymous = false;
      final auth = FakeAuth(user);
      var serverCalls = 0;
      final accounts = AccountService(
        auth,
        deleteOnServer: () async {
          serverCalls++;
          expect(user.calls, ['reauth']);
        },
      );
      await accounts.deleteAccount('local-fixture-only');
      expect(serverCalls, 1);
      expect(user.calls, [
        'reauth',
      ], reason: 'the server deletes the Auth user');
      expect(auth.signOuts, 1);

      final wrong =
          FakeUser()
            ..anonymous = false
            ..failReauth = true;
      await expectLater(
        AccountService(
          FakeAuth(wrong),
          deleteOnServer: () async => serverCalls++,
        ).deleteAccount('wrong'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(serverCalls, 1, reason: 'no server call without reauthentication');
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
  test('an empty password stops deletion before contacting Auth', () async {
    final user = FakeUser()..anonymous = false;
    var serverCalls = 0;
    await expectLater(
      AccountService(
        FakeAuth(user),
        deleteOnServer: () async => serverCalls++,
      ).deleteAccount(''),
      throwsA(
        isA<FirebaseAuthException>().having(
          (error) => error.code,
          'code',
          'missing-password',
        ),
      ),
    );
    expect(user.calls, isEmpty);
    expect(serverCalls, 0);
  });
  test(
    'registered account deletion requires successful reauthentication',
    () async {
      final user =
          FakeUser()
            ..anonymous = false
            ..failReauth = true;
      await expectLater(
        AccountService(FakeAuth(user)).deleteAccount('wrong'),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(user.calls, ['reauth']);
      user.failReauth = false;
      await AccountService(FakeAuth(user)).deleteAccount('local-fixture-only');
      expect(user.calls, ['reauth', 'reauth', 'delete']);
    },
  );
  group('Google sign-in', () {
    testWidgets('the buttons appear only where Google is enabled', (
      tester,
    ) async {
      final user = FakeUser();
      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(accounts: AccountService(FakeAuth(user))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue with Google'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accounts: AccountService(
              FakeAuth(user),
              googleEnabled: true,
              web: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(user.calls, ['link:google.com']);
    });

    test('links a guest without replacing or signing out the guest', () async {
      final user = FakeUser();
      final auth = FakeAuth(user);
      await AccountService(auth, web: false).continueWithGoogle();
      expect(user.calls, ['link:google.com']);
      expect(user.isAnonymous, isFalse);
      expect(auth.currentUser, same(user));
      expect((auth.signOuts, auth.guests, auth.providerSignIns), (0, 0, 0));
    });

    testWidgets('an existing Google account is offered as a switch', (
      tester,
    ) async {
      final user = FakeUser()..failLink = true;
      final auth = FakeAuth(user);
      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(
            accounts: AccountService(auth, googleEnabled: true, web: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Continue with Google'));
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(
        find.text('Switch to your existing Google account?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(auth.providerSignIns, 0);
      expect(find.text('Your guest session is unchanged.'), findsOneWidget);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch'));
      await tester.pumpAndSettle();
      expect(auth.providerSignIns, 1);
      expect(find.text('Signed in as'), findsOneWidget);
    });

    testWidgets('a Google-only account sees no password form', (tester) async {
      final user =
          FakeUser()
            ..anonymous = false
            ..verified = true
            ..providers = ['google.com'];
      await tester.pumpWidget(
        MaterialApp(
          home: AccountScreen(accounts: AccountService(FakeAuth(user))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Reset password'), findsNothing);
      expect(find.text('Delete account'), findsOneWidget);
    });

    test('uses a popup on the web', () async {
      final user = FakeUser();
      await AccountService(FakeAuth(user), web: true).continueWithGoogle();
      expect(user.calls, ['popup:google.com']);
    });

    test('an existing Google account is not merged into the guest', () async {
      final user = FakeUser()..failLink = true;
      final auth = FakeAuth(user);
      await expectLater(
        AccountService(auth, web: false).continueWithGoogle(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'credential-already-in-use',
          ),
        ),
      );
      expect(auth.currentUser, same(user));
      expect(user.isAnonymous, isTrue);
      expect((auth.signOuts, auth.providerSignIns), (0, 0));
    });

    test('a registered account must sign out first', () async {
      final auth = FakeAuth(FakeUser()..anonymous = false);
      await expectLater(
        AccountService(auth, web: false).continueWithGoogle(),
        throwsA(isA<StateError>()),
      );
      expect(auth.providerSignIns, 0);
    });

    test('deleting a Google account reauthenticates with Google', () async {
      final user =
          FakeUser()
            ..anonymous = false
            ..providers = ['google.com'];
      final auth = FakeAuth(user);
      var serverCalls = 0;
      await AccountService(
        auth,
        web: false,
        deleteOnServer: () async {
          serverCalls++;
          expect(user.calls, ['reauth:google.com']);
        },
      ).deleteAccount('');
      expect(serverCalls, 1);
      expect(auth.signOuts, 1);
    });
  });
}

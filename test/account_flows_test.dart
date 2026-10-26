import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whatdoyouwant/screens/account_action_screen.dart';
import 'package:whatdoyouwant/screens/create_account_screen.dart';
import 'package:whatdoyouwant/screens/forgot_password_screen.dart';
import 'package:whatdoyouwant/services/account_service.dart';
import 'package:whatdoyouwant/services/email_address.dart';

import 'account_service_test.dart' show FakeAuth, FakeUser;

final returnTo = Uri.parse('https://getwhatdoyouwant.app/app/account');

Future<void> show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  test('email addresses need a name, an @ and a real-looking domain', () {
    for (final ok in ['pat@example.com', 'p.m+food@mail.example.co.uk']) {
      expect(emailProblem(ok), isNull, reason: ok);
    }
    expect(emailProblem(''), 'Enter your email address.');
    for (final bad in [
      'person',
      'pat@',
      '@example.com',
      'pat@example',
      'pat @x.com',
      'pat@x.c',
    ]) {
      expect(emailProblem(bad), 'Enter a valid email address.', reason: bad);
    }
  });

  testWidgets('sign-up fields speak up once left, then update as you type', (
    tester,
  ) async {
    await show(
      tester,
      CreateAccountScreen(accounts: AccountService(FakeAuth(FakeUser()))),
    );
    final fields = find.byType(TextField);

    await tester.tap(fields.at(0));
    await tester.enterText(fields.at(0), 'person');
    await tester.pump();
    expect(
      find.text('Enter a valid email address.'),
      findsNothing,
      reason: 'quiet while typing the first time',
    );

    await tester.tap(fields.at(1)); // leaving the email field
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await tester.enterText(fields.at(0), 'person@example.com');
    await tester.pump();
    expect(
      find.text('Enter a valid email address.'),
      findsNothing,
      reason: 'fixing it clears the error live',
    );

    await tester.enterText(fields.at(1), 'short');
    await tester.tap(fields.at(2));
    await tester.pump();
    expect(
      find.text('Use a password with at least 12 characters.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'submitting shows every problem at once without contacting Auth',
    (tester) async {
      final auth = FakeAuth(FakeUser());
      await show(tester, CreateAccountScreen(accounts: AccountService(auth)));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(
        find.text('Use a password with at least 12 characters.'),
        findsOneWidget,
      );
      expect(find.text('Enter the password again.'), findsOneWidget);
      expect(auth.creates, 0);
    },
  );

  testWidgets('after a mismatch the repeat can be corrected and submitted', (
    tester,
  ) async {
    final user = FakeUser();
    await show(
      tester,
      CreateAccountScreen(accounts: AccountService(FakeAuth(user))),
    );
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'pat@example.com');
    await tester.enterText(fields.at(1), 'blue kettle morning');
    await tester.enterText(fields.at(2), 'blue kettle mornink');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(user.calls, isEmpty);

    final repeat = tester.widget<TextField>(fields.at(2));
    expect(repeat.enabled, isNot(false));
    expect(repeat.maxLength, isNull, reason: 'nothing is cut short');
    // Without a hint the web autofill group dropped this field's text.
    expect(repeat.autofillHints, [AutofillHints.newPassword]);
    await tester.enterText(fields.at(2), 'blue kettle morning');
    await tester.pump();
    expect(
      find.text('The passwords do not match.'),
      findsNothing,
      reason: 'the old complaint clears once the person edits',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(user.calls, ['link', 'verify']);
  });

  testWidgets(
    'signing up keeps the guest and asks for a verification link back to the app',
    (tester) async {
      final user = FakeUser();
      final auth = FakeAuth(user);
      await show(
        tester,
        CreateAccountScreen(accounts: AccountService(auth, returnTo: returnTo)),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'pat@example.com');
      await tester.enterText(fields.at(1), 'blue kettle morning');
      await tester.enterText(fields.at(2), 'blue kettle morning');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(user.calls, ['link', 'verify']);
      expect(auth.currentUser, same(user), reason: 'the guest UID is kept');
      expect(user.verifySettings?.url, returnTo.toString());
      expect(user.verifySettings?.handleCodeInApp, isTrue);
      expect(find.byType(CreateAccountScreen), findsNothing);
    },
  );

  group('email domain check', () {
    Future<void> fillValid(WidgetTester tester, String address) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), address);
      await tester.enterText(fields.at(1), 'blue kettle morning');
      await tester.enterText(fields.at(2), 'blue kettle morning');
    }

    testWidgets(
      'a domain that takes no mail is flagged and nothing is created',
      (tester) async {
        final asked = <String>[];
        final auth = FakeAuth(FakeUser());
        await show(
          tester,
          CreateAccountScreen(
            accounts: AccountService(
              auth,
              mailDomainCheck: (domain) async {
                asked.add(domain);
                return domain != 'gmial.con';
              },
            ),
          ),
        );
        await fillValid(tester, 'Pat@Gmial.con');
        await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            "That email's domain can't receive mail. Check it for typos.",
          ),
          findsOneWidget,
        );
        expect(asked, contains('gmial.con'), reason: 'only the domain is sent');
        expect(asked.any((sent) => sent.contains('@')), isFalse);
        expect(auth.creates, 0);
        expect((auth.user as FakeUser).calls, isEmpty);

        await tester.enterText(find.byType(TextField).at(0), 'pat@gmail.com');
        await tester.pump();
        expect(
          find.text(
            "That email's domain can't receive mail. Check it for typos.",
          ),
          findsNothing,
          reason: 'editing the address clears the flag',
        );
        await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
        await tester.pumpAndSettle();
        expect((auth.user as FakeUser).calls, ['link', 'verify']);
      },
    );

    test('trouble asking lets the address through', () async {
      final accounts = AccountService(
        FakeAuth(null),
        mailDomainCheck: (_) async => throw StateError('offline'),
      );
      expect(await accounts.canReceiveMail('pat@example.com'), isTrue);
      expect(
        await AccountService(FakeAuth(null)).canReceiveMail('pat@x.com'),
        isTrue,
      );
    });
  });

  group('forgot password', () {
    testWidgets('checks the address, then gives the same answer either way', (
      tester,
    ) async {
      final auth = FakeAuth(null)..resetError = 'user-not-found';
      await show(
        tester,
        ForgotPasswordScreen(
          accounts: AccountService(auth, returnTo: returnTo),
          email: 'person',
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send reset link'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'nobody@example.com');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send reset link'));
      await tester.pumpAndSettle();
      expect(
        find.text('Check your email'),
        findsOneWidget,
        reason: 'an unknown address is not revealed',
      );
    });

    testWidgets('sends a reset link that comes back to the app', (
      tester,
    ) async {
      final auth = FakeAuth(null);
      await show(
        tester,
        ForgotPasswordScreen(
          accounts: AccountService(auth, returnTo: returnTo),
          email: 'pat@example.com',
        ),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send reset link'));
      await tester.pumpAndSettle();
      expect(auth.resetSentTo, 'pat@example.com');
      expect(auth.resetSettings?.url, returnTo.toString());
      expect(find.text('Check your email'), findsOneWidget);
    });
  });

  group('emailed links', () {
    testWidgets('a reset link lets the person choose a policy-meeting password', (
      tester,
    ) async {
      final auth = FakeAuth(null)..resetCodes['code1'] = 'pat@example.com';
      await show(
        tester,
        AccountActionScreen(
          accounts: AccountService(auth),
          mode: 'resetPassword',
          code: 'code1',
        ),
      );
      expect(find.text('for pat@example.com'), findsOneWidget);

      final fields = find.byType(TextField);
      // The hidden username for password managers is offstage, so it isn't counted.
      await tester.enterText(fields.at(0), 'Password12345!');
      await tester.enterText(fields.at(1), 'Password12345!');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Save new password'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'That password is too easy to guess. Try a short phrase instead.',
        ),
        findsOneWidget,
      );
      expect(auth.changedPasswords, isEmpty);

      await tester.enterText(fields.at(0), 'blue kettle morning');
      await tester.enterText(fields.at(1), 'blue kettle morning');
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Save new password'),
      );
      await tester.pumpAndSettle();
      expect(auth.changedPasswords, {'pat@example.com': 'blue kettle morning'});
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('a double tap on save still ends on the success screen', (
      tester,
    ) async {
      final auth = FakeAuth(null)..resetCodes['code2'] = 'pat@example.com';
      await show(
        tester,
        AccountActionScreen(
          accounts: AccountService(auth),
          mode: 'resetPassword',
          code: 'code2',
        ),
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'blue kettle morning');
      await tester.enterText(fields.at(1), 'blue kettle morning');
      final save = find.widgetWithText(ElevatedButton, 'Save new password');
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Password changed'), findsOneWidget);
    });

    testWidgets('an email-change link confirms the new email', (tester) async {
      final auth = FakeAuth(null)..applyCodes.add('c1');
      await show(
        tester,
        AccountActionScreen(
          accounts: AccountService(auth),
          mode: 'verifyAndChangeEmail',
          code: 'c1',
        ),
      );
      expect(find.text('Your new email is confirmed'), findsOneWidget);
    });

    testWidgets('a link for a step the app does not offer is not applied', (
      tester,
    ) async {
      final auth = FakeAuth(null)..applyCodes.add('m1');
      await show(
        tester,
        AccountActionScreen(
          accounts: AccountService(auth),
          mode: 'revertSecondFactorAddition',
          code: 'm1',
        ),
      );
      expect(find.text('This link no longer works'), findsOneWidget);
      expect(
        auth.applyCodes,
        contains('m1'),
        reason: 'the code is left unused',
      );
    });

    testWidgets('a used or expired reset link offers a new one', (
      tester,
    ) async {
      await show(
        tester,
        AccountActionScreen(
          accounts: AccountService(FakeAuth(null)),
          mode: 'resetPassword',
          code: 'old',
        ),
      );
      expect(find.text('This link no longer works'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Send a new reset link'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });

    testWidgets(
      'a verification link verifies and refreshes the signed-in account',
      (tester) async {
        final user = FakeUser();
        final auth = FakeAuth(user)..applyCodes.add('v1');
        await show(
          tester,
          AccountActionScreen(
            accounts: AccountService(auth),
            mode: 'verifyEmail',
            code: 'v1',
          ),
        );
        expect(find.text('Your email is verified'), findsOneWidget);
        expect(user.calls, contains('reload'));

        await show(
          tester,
          AccountActionScreen(
            accounts: AccountService(auth),
            mode: 'verifyEmail',
            code: 'v1',
            key: UniqueKey(),
          ),
        );
        expect(
          find.text('This link no longer works'),
          findsOneWidget,
          reason: 'codes work once',
        );
      },
    );
  });
}

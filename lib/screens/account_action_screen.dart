import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/password_policy.dart';
import '../services/site_links.dart';
import 'account_screen.dart';
import 'checked_field.dart';
import 'forgot_password_screen.dart';

/// Finishes a step started by email, in the app's own style: verifying an
/// address, choosing a new password, or undoing an email change.
class AccountActionScreen extends StatefulWidget {
  const AccountActionScreen({
    super.key,
    required this.accounts,
    required this.mode,
    required this.code,
  });

  final AccountService accounts;

  /// `verifyEmail`, `resetPassword` or `recoverEmail`.
  final String mode;

  /// The link's one-time code.
  final String code;

  @override
  State<AccountActionScreen> createState() => _AccountActionScreenState();
}

enum _Stage { checking, choosePassword, done, failed }

class _AccountActionScreenState extends State<AccountActionScreen> {
  final password = TextEditingController();
  final repeat = TextEditingController();
  // Holds the account's email so password managers save the new password
  // against it.
  final username = TextEditingController();
  _Stage stage = _Stage.checking;
  String resetEmail = '';
  bool busy = false;
  bool submitted = false;
  bool showPasswords = false;
  String message = '';

  bool get resetting => widget.mode == 'resetPassword';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    password.dispose();
    repeat.dispose();
    username.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // A kind of link the app doesn't offer yet, such as one for two-step
    // sign-in, can't be finished here.
    if (!accountActionModes.contains(widget.mode)) {
      setState(() => stage = _Stage.failed);
      return;
    }
    try {
      if (resetting) {
        resetEmail = await widget.accounts.checkResetLink(widget.code);
        username.text = resetEmail;
        if (mounted) setState(() => stage = _Stage.choosePassword);
      } else {
        await widget.accounts.applyLink(widget.code);
        if (mounted) setState(() => stage = _Stage.done);
      }
    } catch (_) {
      if (mounted) setState(() => stage = _Stage.failed);
    }
  }

  String? passwordProblem(String text) =>
      PasswordPolicy.problem(text, email: resetEmail);

  String? repeatProblem(String text) {
    if (text.isEmpty) return 'Enter the password again.';
    return text == password.text ? null : 'The passwords do not match.';
  }

  Future<void> save() async {
    // A double click can land before the button disables itself; a second
    // save would spend the used code and report a failure over the success.
    if (busy || stage != _Stage.choosePassword) return;
    if (passwordProblem(password.text) != null ||
        repeatProblem(repeat.text) != null) {
      setState(() => submitted = true);
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await widget.accounts.finishReset(widget.code, password.text);
      if (mounted) setState(() => stage = _Stage.done);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      if (error.code == 'expired-action-code' ||
          error.code == 'invalid-action-code') {
        setState(() => stage = _Stage.failed);
      } else {
        setState(() => message = accountErrorMessage(error));
      }
    } catch (_) {
      if (mounted) {
        setState(() => message = 'The password could not be changed.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(resetting ? 'Reset password' : 'Your account'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: switch (stage) {
              _Stage.checking => const [
                SizedBox(height: 48),
                Center(child: CircularProgressIndicator()),
              ],
              _Stage.choosePassword => _choose(theme),
              _Stage.done => _done(theme),
              _Stage.failed => _failed(theme),
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _choose(ThemeData theme) {
    final visibility = IconButton(
      tooltip: showPasswords ? 'Hide passwords' : 'Show passwords',
      icon: Icon(showPasswords ? Icons.visibility_off : Icons.visibility),
      onPressed: () => setState(() => showPasswords = !showPasswords),
    );
    return [
      Text(
        'Choose a new password',
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text('for $resetEmail', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      AutofillGroup(
        child: Column(
          children: [
            Offstage(
              child: TextField(
                controller: username,
                autofillHints: const [AutofillHints.username],
                readOnly: true,
              ),
            ),
            CheckedField(
              controller: password,
              label: 'New password',
              check: passwordProblem,
              showError: submitted,
              enabled: !busy,
              obscureText: !showPasswords,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              helperText: PasswordPolicy.hint,
              suffixIcon: visibility,
              onChanged: (_) => setState(() => message = ''),
            ),
            const SizedBox(height: 8),
            CheckedField(
              controller: repeat,
              label: 'Re-enter new password',
              check: repeatProblem,
              showError: submitted,
              enabled: !busy,
              obscureText: !showPasswords,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() => message = ''),
              onSubmitted: (_) {
                if (!busy) save();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: busy ? null : save,
        child: const Text('Save new password'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Text(message, textAlign: TextAlign.center),
        ),
    ];
  }

  List<Widget> _done(ThemeData theme) {
    final (title, body) = switch (widget.mode) {
      'resetPassword' => (
        'Password changed',
        'You can now sign in with your new password.',
      ),
      'verifyAndChangeEmail' => (
        'Your new email is confirmed',
        'Sign in with your new email from now on.',
      ),
      'recoverEmail' => (
        'Your email is restored',
        "Your account's email is back to what it was. If you didn't ask for the change, reset your password to be safe.",
      ),
      _ => ('Your email is verified', 'You can now host rooms.'),
    };
    return [
      Icon(
        Icons.check_circle_outline,
        size: 56,
        color: theme.colorScheme.primary,
      ),
      const SizedBox(height: 12),
      Text(
        title,
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(body, textAlign: TextAlign.center),
      const SizedBox(height: 24),
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: Text(resetting ? 'Go to sign in' : 'Continue'),
      ),
    ];
  }

  List<Widget> _failed(ThemeData theme) => [
    Icon(Icons.link_off, size: 56, color: theme.colorScheme.error),
    const SizedBox(height: 12),
    Text(
      'This link no longer works',
      style: theme.textTheme.headlineSmall,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 8),
    Text(
      resetting
          ? 'Reset links work once and for one hour. Ask for a new one and use the newest email.'
          : 'It may have expired or already been used. Open Account to send a new link, using the newest email.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    if (resetting)
      ElevatedButton(
        onPressed:
            () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ForgotPasswordScreen(accounts: widget.accounts),
              ),
            ),
        child: const Text('Send a new reset link'),
      )
    else
      ElevatedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Continue'),
      ),
  ];
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../services/email_address.dart';
import '../services/password_policy.dart';
import 'account_screen.dart';
import 'checked_field.dart';

/// Sign-up on its own screen so it is clear an account is being made. A guest
/// keeps their identity: the new email account is linked to the guest session.
/// Pops with `true` once the account exists and a verification email was asked for.
class CreateAccountScreen extends StatefulWidget {
  final AccountService accounts;
  const CreateAccountScreen({super.key, required this.accounts});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final repeat = TextEditingController();
  bool busy = false;
  bool showPasswords = false;
  // Set by a submit, so every field shows what still needs fixing.
  bool submitted = false;
  // What the server said, such as an address that is already registered.
  String message = '';
  // An address whose domain the backend said can't receive mail.
  String? undeliverable;

  String? emailCheck(String text) {
    final shape = emailProblem(text);
    if (shape != null) return shape;
    return text.trim().toLowerCase() == undeliverable
        ? "That email's domain can't receive mail. Check it for typos."
        : null;
  }

  /// Asks whether the domain takes mail; returns false and flags the field
  /// when it clearly doesn't.
  Future<bool> checkDomain(String text) async {
    if (emailProblem(text) != null) return true;
    final address = text.trim().toLowerCase();
    final ok = await widget.accounts.canReceiveMail(address);
    if (mounted && email.text.trim().toLowerCase() == address) {
      setState(() => undeliverable = ok ? null : address);
    }
    return ok;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  String? passwordProblem(String text) =>
      PasswordPolicy.problem(text, email: email.text.trim());

  String? repeatProblem(String text) {
    if (text.isEmpty) return 'Enter the password again.';
    return text == password.text ? null : 'The passwords do not match.';
  }

  // Any edit can change another field's verdict (the email name inside the
  // password, or the repeat against the password), and an old server
  // complaint shouldn't linger once the person starts fixing things.
  void edited(String _) => setState(() => message = '');

  Future<void> create() async {
    // A double click can land before the button disables itself.
    if (busy) return;
    if (emailCheck(email.text) != null ||
        passwordProblem(password.text) != null ||
        repeatProblem(repeat.text) != null) {
      setState(() => submitted = true);
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
      if (!await checkDomain(email.text)) {
        if (mounted) setState(() => submitted = true);
        return;
      }
      await widget.accounts.register(email.text, password.text);
      try {
        await widget.accounts.sendVerification();
      } on FirebaseAuthException {
        // The account exists either way; the Account screen can resend.
      }
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => message = accountErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => message = 'The account could not be created.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibility = IconButton(
      tooltip: showPasswords ? 'Hide passwords' : 'Show passwords',
      icon: Icon(showPasswords ? Icons.visibility_off : Icons.visibility),
      onPressed: () => setState(() => showPasswords = !showPasswords),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Create your account',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                const Text(
                  'An account lets you host rooms. We will send a link to verify your email.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                CheckedField(
                  controller: email,
                  label: 'Email',
                  check: emailCheck,
                  showError: submitted,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  onChanged: edited,
                  onLeft: checkDomain,
                ),
                const SizedBox(height: 8),
                CheckedField(
                  controller: password,
                  label: 'Password',
                  check: passwordProblem,
                  showError: submitted,
                  enabled: !busy,
                  obscureText: !showPasswords,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  helperText: PasswordPolicy.hint,
                  suffixIcon: visibility,
                  onChanged: edited,
                ),
                const SizedBox(height: 8),
                CheckedField(
                  controller: repeat,
                  label: 'Re-enter password',
                  check: repeatProblem,
                  showError: submitted,
                  enabled: !busy,
                  obscureText: !showPasswords,
                  textInputAction: TextInputAction.done,
                  // On the web a field without a hint inside an autofill group
                  // loses its input after the form rebuilds and stops taking
                  // typing; password managers also expect the confirmation to
                  // be marked as a new password.
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: edited,
                  onSubmitted: (_) {
                    if (!busy) create();
                  },
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: busy ? null : create,
                  child: const Text('Create account'),
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context, false),
                  child: const Text('I already have an account'),
                ),
                if (busy) const LinearProgressIndicator(),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(message, textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

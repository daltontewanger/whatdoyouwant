import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import 'account_screen.dart';

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
  String message = '';

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  String? problem() {
    if (email.text.trim().isEmpty) return 'Enter your email address.';
    if (password.text.length < 6) {
      return 'Use a password with at least 6 characters.';
    }
    if (password.text != repeat.text) return 'The passwords do not match.';
    return null;
  }

  Future<void> create() async {
    final issue = problem();
    if (issue != null) {
      setState(() => message = issue);
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
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
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: !showPasswords,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 6 characters.',
                    suffixIcon: visibility,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: repeat,
                  enabled: !busy,
                  obscureText: !showPasswords,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!busy) create();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Re-enter password',
                  ),
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

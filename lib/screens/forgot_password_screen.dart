import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/account_service.dart';
import '../services/email_address.dart';
import 'account_screen.dart';
import 'checked_field.dart';

/// Asks for the address to send a reset link to. The answer is the same
/// whether or not an account uses it, so the screen can't be used to find
/// out who has an account.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.accounts,
    this.email = '',
  });

  final AccountService accounts;

  /// What was already typed on the sign-in screen.
  final String email;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final email = TextEditingController(text: widget.email.trim());
  bool busy = false;
  bool submitted = false;
  bool sent = false;
  String message = '';

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> send() async {
    // A double click can land before the button disables itself.
    if (busy || sent) return;
    if (emailProblem(email.text) != null) {
      setState(() => submitted = true);
      return;
    }
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await widget.accounts.resetPassword(email.text);
      if (mounted) setState(() => sent = true);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => message = accountErrorMessage(error));
    } catch (_) {
      if (mounted) setState(() => message = 'The email could not be sent.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: sent ? _sent(theme) : _form(theme),
          ),
        ),
      ),
    );
  }

  List<Widget> _form(ThemeData theme) => [
    Text(
      'Forgot your password?',
      style: theme.textTheme.headlineSmall,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 4),
    const Text(
      "Enter the email you signed up with and we'll send you a link to choose a new password.",
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    AutofillGroup(
      child: CheckedField(
        controller: email,
        label: 'Email',
        check: emailProblem,
        showError: submitted,
        enabled: !busy,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.send,
        autofillHints: const [AutofillHints.email],
        onChanged: (_) => setState(() => message = ''),
        onSubmitted: (_) {
          if (!busy) send();
        },
      ),
    ),
    const SizedBox(height: 16),
    ElevatedButton(
      onPressed: busy ? null : send,
      child: const Text('Send reset link'),
    ),
    TextButton(
      onPressed: busy ? null : () => Navigator.pop(context),
      child: const Text('Back to sign in'),
    ),
    if (busy) const LinearProgressIndicator(),
    if (message.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text(message, textAlign: TextAlign.center),
      ),
  ];

  List<Widget> _sent(ThemeData theme) => [
    Icon(
      Icons.mark_email_read_outlined,
      size: 56,
      color: theme.colorScheme.primary,
    ),
    const SizedBox(height: 12),
    Text(
      'Check your email',
      style: theme.textTheme.headlineSmall,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 8),
    Text(
      widget.accounts.usesEmulator
          ? 'If an account uses ${email.text.trim()}, its reset link is in the local Auth emulator.'
          : "If an account uses ${email.text.trim()}, we've sent it a link to choose a new password. The link works for one hour; check your spam folder if it doesn't arrive.",
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    ElevatedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Back to sign in'),
    ),
    TextButton(
      onPressed: () => setState(() => sent = false),
      child: const Text('Use a different email'),
    ),
  ];
}

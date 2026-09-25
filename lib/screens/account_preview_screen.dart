import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import 'room_preview_screen.dart';

class AccountPreviewScreen extends StatefulWidget {
  final AccountService accounts;
  const AccountPreviewScreen({super.key, required this.accounts});

  @override
  State<AccountPreviewScreen> createState() => _AccountPreviewScreenState();
}

class _AccountPreviewScreenState extends State<AccountPreviewScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String message = '';

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<bool> confirm(String title, String explanation) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(title),
              content: Text(explanation),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
      ) ??
      false;

  Future<void> perform(Future<void> Function() action, String success) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
    } on FirebaseAuthException catch (error) {
      const messages = {
        'email-already-in-use':
            'This email cannot be linked. Your guest session is unchanged. Sign in explicitly if this is your account.',
        'credential-already-in-use':
            'This credential belongs to another account. Your guest session is unchanged.',
        'weak-password': 'Use a password with at least 6 characters.',
        'invalid-email': 'Enter a valid email address.',
        'too-many-requests': 'Too many attempts. Please wait and try again.',
        'network-request-failed': 'Connection failed. Please try again.',
      };
      if (mounted) {
        setState(
          () =>
              message =
                  messages[error.code] ??
                  'The account operation failed. Check your details and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'The account operation could not be completed.',
        );
      }
    } finally {
      if (mounted) {
        password.clear();
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Local account preview')),
    body: StreamBuilder<User?>(
      stream: widget.accounts.auth.userChanges(),
      initialData: widget.accounts.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final registered = user != null && !user.isAnonymous;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Local test accounts and fictional restaurants only.',
                ),
                const SizedBox(height: 16),
                Text(
                  user == null
                      ? 'Signed out'
                      : user.isAnonymous
                      ? 'Guest session'
                      : user.emailVerified
                      ? 'Email verified'
                      : 'Email verification needed',
                ),
                if (registered) Text(user.email ?? ''),
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'New accounts require at least 6 characters.',
                  ),
                ),
                const SizedBox(height: 16),
                if (!registered) ...[
                  ElevatedButton(
                    onPressed:
                        busy
                            ? null
                            : () => perform(
                              () => widget.accounts.register(
                                email.text,
                                password.text,
                              ),
                              'Account created. Use Send verification to verify your email.',
                            ),
                    child: const Text('Create account'),
                  ),
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () async {
                              if (user?.isAnonymous == true &&
                                  !await confirm(
                                    'Switch to an existing account?',
                                    'Your guest activity will not be merged. Creating a new account instead preserves your guest identity.',
                                  )) {
                                return;
                              }
                              if (!mounted) return;
                              await perform(
                                () => widget.accounts.signIn(
                                  email.text,
                                  password.text,
                                ),
                                'Signed in.',
                              );
                            },
                    child: const Text('Sign in'),
                  ),
                ],
                if (registered && !user.emailVerified) ...[
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () => perform(
                              widget.accounts.sendVerification,
                              'Verification requested. Open the local Auth emulator verification link.',
                            ),
                    child: const Text('Send verification'),
                  ),
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () => perform(
                              widget.accounts.refreshVerification,
                              'Verification status refreshed.',
                            ),
                    child: const Text('I verified my email'),
                  ),
                ],
                TextButton(
                  onPressed:
                      busy
                          ? null
                          : () => perform(
                            () => widget.accounts.resetPassword(email.text),
                            'If an account exists, password reset instructions are available in the local Auth emulator.',
                          ),
                  child: const Text('Reset password'),
                ),
                if (user == null)
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () => perform(
                              widget.accounts.guest,
                              'Guest session started.',
                            ),
                    child: const Text('Continue as guest'),
                  ),
                if (user != null) ...[
                  ElevatedButton(
                    onPressed:
                        busy
                            ? null
                            : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const RoomPreviewScreen(),
                              ),
                            ),
                    child: const Text('Open test rooms'),
                  ),
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () async {
                              if (user.isAnonymous &&
                                  !await confirm(
                                    'Leave this guest session?',
                                    'You may lose access to activity tied to this guest identity.',
                                  )) {
                                return;
                              }
                              if (!mounted) return;
                              await perform(
                                widget.accounts.auth.signOut,
                                'Signed out.',
                              );
                            },
                    child: const Text('Sign out'),
                  ),
                  TextButton(
                    onPressed:
                        busy
                            ? null
                            : () async {
                              if (!await confirm(
                                'Delete this local test account?',
                                'This deletes only the Auth emulator account. Full app data deletion is not implemented yet. Enter your password first for a registered account.',
                              )) {
                                return;
                              }
                              if (!mounted) return;
                              await perform(
                                () => widget.accounts.deleteLocalAccount(
                                  password.text,
                                ),
                                'Local test account deleted.',
                              );
                            },
                    child: const Text('Delete local test account'),
                  ),
                ],
                if (busy) const LinearProgressIndicator(),
                if (message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(message),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

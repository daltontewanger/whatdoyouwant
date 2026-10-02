import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import 'create_account_screen.dart';
import 'room_preview_screen.dart';

/// Turns Auth errors into guidance. Projects with email enumeration protection
/// report an unknown email and a wrong password the same way, so the specific
/// messages only appear where Auth itself distinguishes them.
String accountErrorMessage(FirebaseAuthException error) {
  const googleCancelled = 'Google sign-in was cancelled.';
  const wrongDetails =
      'Email or password is incorrect. Check them, or create an account if you are new.';
  const messages = {
    'user-not-found':
        'No account uses that email. If you are new, create an account below.',
    'wrong-password':
        'That password is incorrect. Try again or use Forgot password.',
    'invalid-credential': wrongDetails,
    'INVALID_LOGIN_CREDENTIALS': wrongDetails,
    'missing-password': 'Enter your password.',
    'email-already-in-use':
        'An account already uses this email. Sign in instead; your guest session is unchanged.',
    'credential-already-in-use':
        'This credential belongs to another account. Your guest session is unchanged.',
    'weak-password': 'Use a password with at least 6 characters.',
    'invalid-email': 'Enter a valid email address.',
    'user-disabled': 'This account has been disabled.',
    'too-many-requests': 'Too many attempts. Please wait and try again.',
    'network-request-failed': 'Connection failed. Please try again.',
    'requires-recent-login': 'Please sign in again, then retry.',
    'popup-closed-by-user': googleCancelled,
    'cancelled-popup-request': googleCancelled,
    'web-context-canceled': googleCancelled,
    'canceled': googleCancelled,
    'unauthorized-domain':
        'This site is not authorized for Google sign-in in this environment.',
    'operation-not-allowed':
        'This sign-in method is not enabled for this environment.',
  };
  return messages[error.code] ??
      'The account operation failed. Check your details and try again.';
}

class AccountPreviewScreen extends StatefulWidget {
  final AccountService accounts;

  /// The preview builds link to the stand-alone room preview; the app uses its
  /// own room screens instead.
  final bool showRoomPreview;
  const AccountPreviewScreen({
    super.key,
    required this.accounts,
    this.showRoomPreview = true,
  });

  @override
  State<AccountPreviewScreen> createState() => _AccountPreviewScreenState();
}

class _AccountPreviewScreenState extends State<AccountPreviewScreen> {
  AccountService get accounts => widget.accounts;
  bool get local => accounts.usesEmulator;
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

  Future<bool> confirm(
    String title,
    String explanation, {
    String action = 'Continue',
  }) async =>
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
                  child: Text(action),
                ),
              ],
            ),
      ) ??
      false;

  /// Runs an account action and reports the result; returns whether it worked.
  Future<bool> perform(Future<void> Function() action, String success) async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await action();
      if (mounted) setState(() => message = success);
      return true;
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => message = accountErrorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'The account operation could not be completed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    return false;
  }

  Future<void> signIn(User? user) async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => message = 'Enter your email and password.');
      return;
    }
    if (user?.isAnonymous == true &&
        !await confirm(
          'Sign in to an existing account?',
          'Activity from this guest session will not move to that account. To keep it, create an account instead.',
        )) {
      return;
    }
    if (!mounted) return;
    final signedIn = await perform(
      () => accounts.signIn(email.text, password.text),
      'Signed in.',
    );
    if (signedIn) {
      password.clear();
      returnIfReady();
    }
  }

  /// Goes back once the account can host, so whatever sent the user here (such
  /// as Create Room) carries on. Unverified accounts stay to finish verifying.
  void returnIfReady() {
    final user = accounts.auth.currentUser;
    if (!mounted ||
        user == null ||
        user.isAnonymous ||
        !user.emailVerified ||
        !Navigator.canPop(context)) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Signed in as ${user.email ?? 'your account'}.')),
    );
    Navigator.pop(context);
  }

  Future<void> continueWithGoogle() async {
    setState(() {
      busy = true;
      message = '';
    });
    try {
      await accounts.continueWithGoogle();
      if (mounted) setState(() => message = 'Signed in with Google.');
      returnIfReady();
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      if (error.code != 'credential-already-in-use') {
        setState(() => message = accountErrorMessage(error));
        return;
      }
      // That Google account already exists; switching is allowed but never merges.
      if (await confirm(
        'Switch to your existing Google account?',
        'This Google account already has an account here. Activity from this guest session will not move to it.',
        action: 'Switch',
      )) {
        if (!mounted) return;
        if (await perform(
          accounts.signInWithGoogle,
          'Signed in with Google.',
        )) {
          returnIfReady();
        }
      } else if (mounted) {
        setState(() => message = 'Your guest session is unchanged.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message = 'The account operation could not be completed.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createAccount() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAccountScreen(accounts: accounts),
      ),
    );
    if (created == true && mounted) {
      setState(
        () =>
            message =
                local
                    ? 'Account created. Open the Auth emulator verification link, then press I have verified my email.'
                    : 'Account created. We sent you a verification email; open the link in it, then press I have verified my email.',
      );
    }
  }

  Future<void> deleteAccount(User user) async {
    // Null when cancelled; an empty string for accounts without a password.
    final entered = await showDialog<String>(
      context: context,
      builder:
          (_) =>
              _DeletePrompt(needsPassword: AccountService.usesPassword(user)),
    );
    if (entered == null || !mounted) return;
    await perform(() => accounts.deleteAccount(entered), 'Account deleted.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.showRoomPreview ? 'Local account preview' : 'Account'),
    ),
    body: StreamBuilder<User?>(
      stream: accounts.auth.userChanges(),
      initialData: accounts.auth.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final registered = user != null && !user.isAnonymous;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AutofillGroup(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    local
                        ? 'Local test accounts (Auth emulator) and fictional restaurants only.'
                        : 'Test accounts in the staging project and fictional restaurants only.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  if (registered)
                    ..._signedIn(context, user)
                  else
                    ..._signedOut(context, user),
                  if (busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(message, textAlign: TextAlign.center),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  List<Widget> _signedIn(BuildContext context, User user) {
    final theme = Theme.of(context);
    final google = !AccountService.usesPassword(user);
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.account_circle,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 8),
              const Text('Signed in as'),
              Text(
                user.email ?? user.displayName ?? 'your account',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                google ? 'Google account' : 'Email account',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    user.emailVerified
                        ? Icons.verified
                        : Icons.mark_email_unread_outlined,
                    size: 18,
                    color:
                        user.emailVerified
                            ? theme.colorScheme.primary
                            : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    user.emailVerified
                        ? 'Email verified'
                        : 'Email not verified yet',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (!user.emailVerified) ...[
        const SizedBox(height: 8),
        const Text(
          'Verify your email to host rooms.',
          textAlign: TextAlign.center,
        ),
        TextButton(
          onPressed:
              busy
                  ? null
                  : () => perform(
                    accounts.sendVerification,
                    local
                        ? 'Verification requested. Open the local Auth emulator verification link.'
                        : 'Verification email sent. Open the link in it, then press I have verified my email.',
                  ),
          child: const Text('Send verification email'),
        ),
        ElevatedButton(
          onPressed:
              busy
                  ? null
                  : () async {
                    if (await perform(
                      accounts.refreshVerification,
                      'Verification status refreshed.',
                    )) {
                      returnIfReady();
                    }
                  },
          child: const Text('I have verified my email'),
        ),
      ],
      const SizedBox(height: 16),
      if (widget.showRoomPreview)
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
      OutlinedButton(
        onPressed:
            busy
                ? null
                : () => perform(
                  accounts.signOut,
                  'Signed out. You are playing as a guest.',
                ),
        child: const Text('Sign out'),
      ),
      const SizedBox(height: 24),
      TextButton(
        onPressed: busy ? null : () => deleteAccount(user),
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
        child: const Text('Delete account'),
      ),
    ];
  }

  List<Widget> _signedOut(BuildContext context, User? user) {
    final theme = Theme.of(context);
    return [
      Text(
        'Sign in',
        style: theme.textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        user == null
            ? 'Sign in or create an account to host rooms.'
            : 'You are playing as a guest. Sign in or create an account to host rooms.',
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
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.go,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) {
          if (!busy) signIn(user);
        },
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed:
              busy
                  ? null
                  : () {
                    if (email.text.trim().isEmpty) {
                      setState(
                        () =>
                            message =
                                'Enter your email above, then press Forgot password.',
                      );
                      return;
                    }
                    perform(
                      () => accounts.resetPassword(email.text),
                      local
                          ? 'If an account exists, password reset instructions are available in the local Auth emulator.'
                          : 'If an account exists for that email, a password reset email is on its way.',
                    );
                  },
          child: const Text('Forgot password?'),
        ),
      ),
      ElevatedButton(
        onPressed: busy ? null : () => signIn(user),
        child: const Text('Sign in'),
      ),
      if (accounts.googleEnabled) ...[
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: busy ? null : continueWithGoogle,
          child: const Text('Continue with Google'),
        ),
      ],
      const SizedBox(height: 24),
      const Text('New here?', textAlign: TextAlign.center),
      TextButton(
        onPressed: busy ? null : createAccount,
        child: const Text('Create an account'),
      ),
      if (user == null)
        TextButton(
          onPressed:
              busy
                  ? null
                  : () => perform(accounts.guest, 'Guest session started.'),
          child: const Text('Continue as guest'),
        ),
    ];
  }
}

class _DeletePrompt extends StatefulWidget {
  final bool needsPassword;
  const _DeletePrompt({required this.needsPassword});

  @override
  State<_DeletePrompt> createState() => _DeletePromptState();
}

class _DeletePromptState extends State<_DeletePrompt> {
  final password = TextEditingController();

  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delete this account?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.needsPassword
              ? 'This deletes the account, its room memberships and votes, and closes rooms it hosts. Enter your password to confirm.'
              : 'This deletes the account, its room memberships and votes, and closes rooms it hosts. Google will ask you to sign in again to confirm.',
        ),
        if (widget.needsPassword)
          TextField(
            controller: password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, password.text),
        child: const Text('Delete'),
      ),
    ],
  );
}

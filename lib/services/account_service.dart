import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AccountService {
  final FirebaseAuth auth;

  /// True when Auth is the local emulator, where no real email is ever sent.
  final bool usesEmulator;

  /// Shows Google sign-in. Off where the Google provider is not configured.
  final bool googleEnabled;

  /// Web uses popups; Android and iOS use the platform provider flow.
  final bool web;

  /// Removes the account's app data and Auth user on the server. Without it,
  /// deletion only removes the Auth user.
  final Future<void> Function()? deleteOnServer;
  AccountService(
    this.auth, {
    this.deleteOnServer,
    this.usesEmulator = false,
    this.googleEnabled = false,
    bool? web,
  }) : web = web ?? kIsWeb;

  /// Links a guest to Google, keeping the guest's identity, or signs in when
  /// there is no session. A Google account that already exists is never merged;
  /// the error propagates and the guest session is unchanged.
  Future<void> continueWithGoogle() async {
    final user = auth.currentUser;
    if (user != null && !user.isAnonymous) {
      throw StateError('Sign out before using another account.');
    }
    final provider = GoogleAuthProvider();
    if (user == null) {
      await signInWithGoogle();
    } else if (web) {
      await user.linkWithPopup(provider);
    } else {
      await user.linkWithProvider(provider);
    }
  }

  /// Switches to an existing Google account, leaving any guest session behind.
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    if (web) {
      await auth.signInWithPopup(provider);
    } else {
      await auth.signInWithProvider(provider);
    }
  }

  static bool usesPassword(User user) =>
      user.providerData.any((info) => info.providerId == 'password');

  Future<void> register(String email, String password) async {
    final user = auth.currentUser;
    if (user != null && !user.isAnonymous) {
      throw StateError('Sign out before creating another account.');
    }
    if (password.length < 6) {
      throw FirebaseAuthException(code: 'weak-password');
    }
    if (user?.isAnonymous == true) {
      // A conflict propagates without signing out or merging unrelated accounts.
      await user!.linkWithCredential(
        EmailAuthProvider.credential(email: email.trim(), password: password),
      );
    } else {
      await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendVerification() async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Create an account first.');
    }
    if (!user.emailVerified) await user.sendEmailVerification();
  }

  Future<void> refreshVerification() async {
    await auth.currentUser?.reload();
    // Refresh the token as well as the displayed user: backend checks use claims.
    await auth.currentUser?.getIdToken(true);
  }

  Future<void> resetPassword(String email) async {
    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      if (error.code != 'user-not-found') rethrow;
    }
  }

  Future<void> guest() async {
    final user = auth.currentUser;
    if (user != null) {
      try {
        await user.reload();
        return;
      } on FirebaseAuthException catch (error) {
        // A saved session for an account that no longer exists (for example after
        // the local emulators restart) can never get a token again. Anything else,
        // such as being offline, keeps the session.
        if (!_accountGone(error)) return;
        await auth.signOut();
      }
    }
    await auth.signInAnonymously();
  }

  static bool _accountGone(FirebaseAuthException error) {
    if (const {
      'user-not-found',
      'user-token-expired',
      'invalid-user-token',
    }.contains(error.code)) {
      return true;
    }
    // Android reports a rejected refresh token from the Auth emulator as an
    // "internal error" that only names the server reason in its message.
    final message = error.message ?? '';
    return error.code == 'unknown' &&
        (message.contains('INVALID_REFRESH_TOKEN') ||
            message.contains('USER_NOT_FOUND'));
  }

  Future<void> deleteAccount(String password) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('No account to delete.');
    if (!user.isAnonymous && usesPassword(user)) {
      if (password.isEmpty) {
        throw FirebaseAuthException(code: 'missing-password');
      }
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password),
      );
    } else if (!user.isAnonymous) {
      // The server only deletes accounts that signed in moments ago.
      final provider = GoogleAuthProvider();
      if (web) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
    }
    final server = deleteOnServer;
    if (server == null) {
      await user.delete();
    } else {
      // The server deletes the Auth user after the data, so only the local
      // session is left to clear.
      await server();
      await auth.signOut();
    }
    await auth.signInAnonymously();
  }

  /// Leaves a registered account. A fresh guest session follows so joining
  /// rooms keeps working without a separate step.
  Future<void> signOut() async {
    await auth.signOut();
    await auth.signInAnonymously();
  }
}

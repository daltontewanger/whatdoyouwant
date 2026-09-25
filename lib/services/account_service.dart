import 'package:firebase_auth/firebase_auth.dart';

// Used only by the opt-in local account preview until integration is reviewed.
class AccountService {
  final FirebaseAuth auth;
  AccountService(this.auth);

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
    if (auth.currentUser == null) await auth.signInAnonymously();
  }

  Future<void> deleteLocalAccount(String password) async {
    final user = auth.currentUser;
    if (user == null) throw StateError('No account to delete.');
    if (!user.isAnonymous) {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password),
      );
    }
    await user.delete();
  }
}

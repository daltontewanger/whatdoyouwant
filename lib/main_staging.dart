import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options_staging.dart';
import 'environment_guard.dart';
import 'main.dart' show MyApp;
import 'services/account_service.dart';
import 'services/active_room_store.dart';
import 'services/callable_room_backend.dart';

class _StagingDebugTokens {
  const _StagingDebugTokens(this.android, this.web)
    : assert(
        kDebugMode || (android == '' && web == ''),
        'App Check debug tokens must not be compiled into staging release builds.',
      );

  final String android;
  final String web;
}

// The app on the deployed staging room backend. STAGING_CONNECTION_CHECK=true
// shows the connection check instead.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = StagingFirebaseOptions.currentPlatform;
  checkFirebaseEnvironment('staging', options.projectId);
  if (options.projectId != 'whatdoyouwant-staging') {
    throw StateError('Staging must never use another Firebase project.');
  }
  await Firebase.initializeApp(options: options);
  const debugTokens = _StagingDebugTokens(
    String.fromEnvironment('STAGING_ANDROID_APPCHECK_DEBUG_TOKEN'),
    String.fromEnvironment('STAGING_WEB_APPCHECK_DEBUG_TOKEN'),
  );
  await FirebaseAppCheck.instance.activate(
    providerAndroid:
        kDebugMode && debugTokens.android.isNotEmpty
            ? AndroidDebugProvider(debugToken: debugTokens.android)
            : const AndroidPlayIntegrityProvider(),
    providerWeb:
        kDebugMode && debugTokens.web.isNotEmpty
            ? WebDebugProvider(debugToken: debugTokens.web)
            : ReCaptchaEnterpriseProvider(
              '6LcXxtItAAAAALnRWSxKceE_-dWM8JYmcuvV7miO',
            ),
  );
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  if (const bool.fromEnvironment('STAGING_CONNECTION_CHECK')) {
    runApp(const MaterialApp(home: StagingCheck()));
    return;
  }
  final accounts = AccountService(
    FirebaseAuth.instance,
    // Off until the Google provider is configured in the staging project.
    googleEnabled: const bool.fromEnvironment('GOOGLE_SIGN_IN'),
    deleteOnServer:
        () => FirebaseFunctions.instance.httpsCallable('deleteAccount').call(),
  );
  await accounts.guest();
  runApp(
    MyApp(
      currentUid: FirebaseAuth.instance.currentUser!.uid,
      backend: CallableRoomBackend(),
      accounts: accounts,
      activeRooms: PreferencesActiveRoomStore(),
    ),
  );
}

class StagingCheck extends StatefulWidget {
  const StagingCheck({super.key});

  @override
  State<StagingCheck> createState() => _StagingCheckState();
}

class _StagingCheckState extends State<StagingCheck> {
  String status = 'Ready to check staging. No room data will be written.';
  bool running = false;

  @override
  void initState() {
    super.initState();
    // Opt-in automation for disposable staging accounts, never production.
    if (kDebugMode && const bool.fromEnvironment('STAGING_AUTOCHECK')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => check());
    }
  }

  Future<void> check() async {
    setState(() => running = true);
    var result = '';
    var operation = 'App Check';
    User? testUser;
    try {
      final appCheckToken = await FirebaseAppCheck.instance
          .getToken(true)
          .timeout(const Duration(seconds: 30));
      if (appCheckToken == null || appCheckToken.isEmpty) {
        throw StateError('No App Check token was issued.');
      }
      operation = 'Sign-in';
      await FirebaseAuth.instance.signOut();
      final credential = await FirebaseAuth.instance.signInAnonymously();
      testUser = credential.user;
      if (testUser == null) throw StateError('No staging test identity.');
      final refreshed = await testUser.getIdToken(true);
      if (refreshed == null || refreshed.isEmpty) {
        throw StateError('Token refresh failed.');
      }
      try {
        await FirebaseFirestore.instance
            .doc('_connection_check/nonexistent')
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 30));
        result = 'FAILED: Firestore unexpectedly allowed a client read.';
      } on FirebaseException catch (error) {
        result =
            error.code == 'permission-denied'
                ? 'PASS: App Check, anonymous sign-in, and token refresh work; Firestore denied the read. Confirm deny-all rules in the console.'
                : 'Firestore check failed: ${error.code}';
      }
    } on FirebaseException catch (error) {
      result = '$operation failed: ${error.code}';
    } catch (_) {
      result = 'Connection check failed. Check your network and configuration.';
    } finally {
      // Remove only the temporary anonymous account created by this check.
      try {
        if (testUser != null && testUser.isAnonymous) {
          await testUser.delete();
          result += ' Temporary test account deleted.';
        }
      } catch (_) {
        result =
            'FAIL: temporary staging account cleanup failed. Review staging Authentication users.';
      }
      if (kDebugMode && const bool.fromEnvironment('STAGING_AUTOCHECK')) {
        debugPrint('Staging connection check: $result');
      }
      if (mounted) {
        setState(() {
          status = result;
          running = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Staging connection check')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('whatdoyouwant-staging'),
          const SizedBox(height: 16),
          Text(status),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: running ? null : check,
            child: Text(running ? 'Checking…' : 'Check staging connection'),
          ),
        ],
      ),
    ),
  );
}

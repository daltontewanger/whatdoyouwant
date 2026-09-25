// Local-only entry point. Production continues to use main.dart.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'main.dart' show MyApp;
import 'environment_guard.dart';
import 'firebase_options_local.dart';
import 'screens/account_preview_screen.dart';
import 'services/account_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  checkFirebaseEnvironment('local', 'demo-whatdoyouwant');
  if (!kDebugMode) {
    throw StateError('The local entry point must only run in debug mode.');
  }
  const host = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  if (!const ['127.0.0.1', 'localhost', '10.0.2.2'].contains(host)) {
    throw StateError(
      'Local testing requires a loopback or Android emulator host.',
    );
  }
  final options =
      kIsWeb ? LocalFirebaseOptions.web : LocalFirebaseOptions.android;
  final app = await Firebase.initializeApp(options: options);
  checkFirebaseEnvironment('local', app.options.projectId);
  if (app.options.apiKey != options.apiKey ||
      app.options.appId != options.appId) {
    throw StateError(
      'The native Firebase app does not match the local configuration.',
    );
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
  if (const bool.fromEnvironment('ACCOUNT_FLOW_PREVIEW')) {
    // Only this emulator-wired entry point exposes the account preview.
    final accounts = AccountService(FirebaseAuth.instance);
    await accounts.guest();
    runApp(MaterialApp(home: AccountPreviewScreen(accounts: accounts)));
    return;
  }
  // No App Check activation or registered debug token in this local-only path.
  final credential = await FirebaseAuth.instance.signInAnonymously();
  runApp(MyApp(currentUid: credential.user!.uid));
}

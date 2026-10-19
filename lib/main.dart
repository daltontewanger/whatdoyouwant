import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'environment_guard.dart';
import 'firebase_options.dart';
import 'screens/main_shell.dart';
import 'screens/update_gate.dart';
import 'services/account_service.dart';
import 'services/active_room_store.dart';
import 'services/callable_room_backend.dart';
import 'services/error_reporter.dart';
import 'services/room_backend.dart';
import 'themes/main_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  useBundledFonts();
  checkFirebaseEnvironment(
    'production',
    DefaultFirebaseOptions.currentPlatform.projectId,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    providerAndroid:
        kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
    providerWeb: ReCaptchaEnterpriseProvider(
      '6LfB8dwsAAAAADI3urO26SxS_C_lHi7jiydt1KSv',
    ),
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  final accounts = AccountService(
    FirebaseAuth.instance,
    // The web client is set up for the production domain. Installed apps
    // also need their signing fingerprints registered, so there it stays
    // behind a build flag until that is done.
    googleEnabled: kIsWeb || const bool.fromEnvironment('GOOGLE_SIGN_IN'),
    deleteOnServer:
        () => FirebaseFunctions.instance.httpsCallable('deleteAccount').call(),
  );
  await accounts.guest();
  // Release builds report uncaught errors; debug builds show them instead.
  if (!kDebugMode) {
    ErrorReporter(
      (report) => FirebaseFunctions.instance
          .httpsCallable('reportClientError')
          .call(report),
      build: await appBuildNumber(),
    ).install();
  }
  runApp(
    MyApp(
      currentUid: FirebaseAuth.instance.currentUser!.uid,
      backend: CallableRoomBackend(),
      accounts: accounts,
      activeRooms: PreferencesActiveRoomStore(),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String currentUid;
  final RoomBackend backend;
  final AccountService? accounts;
  final ActiveRoomStore? activeRooms;
  const MyApp({
    super.key,
    required this.currentUid,
    required this.backend,
    this.accounts,
    this.activeRooms,
  });

  @override
  Widget build(BuildContext context) {
    return RoomBackendScope(
      backend: backend,
      accounts: accounts,
      activeRooms: activeRooms,
      child: MaterialApp(
        title: 'What Do You Want?!',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        home: UpdateGate(child: MainShell(currentUid: currentUid)),
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'environment_guard.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/update_gate.dart';
import 'services/account_service.dart';
import 'services/active_room_store.dart';
import 'services/callable_room_backend.dart';
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
    // On once the production Google provider is set up.
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
        home: UpdateGate(child: HomeScreen(currentUid: currentUid)),
      ),
    );
  }
}

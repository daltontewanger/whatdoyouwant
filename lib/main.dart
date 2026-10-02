import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'environment_guard.dart';
import 'screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'services/account_service.dart';
import 'services/active_room_store.dart';
import 'services/legacy_room_backend.dart';
import 'services/room_backend.dart';
import 'themes/main_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Sign in anonymously
  final cred = await FirebaseAuth.instance.signInAnonymously();
  // Production keeps the original client-managed rooms until its migration.
  runApp(MyApp(currentUid: cred.user!.uid, backend: LegacyRoomBackend()));
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
        home: HomeScreen(currentUid: currentUid),
      ),
    );
  }
}

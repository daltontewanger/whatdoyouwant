import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'themes/main_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await FirebaseAppCheck.instance.activate(
    providerAndroid:
        kDebugMode ? AndroidDebugProvider() : AndroidPlayIntegrityProvider(),
    providerWeb: ReCaptchaEnterpriseProvider('6LfB8dwsAAAAADI3urO26SxS_C_lHi7jiydt1KSv'),
  );

  // Sign in anonymously
  final cred = await FirebaseAuth.instance.signInAnonymously();
  runApp(MyApp(currentUid: cred.user!.uid));
}

class MyApp extends StatelessWidget {
  final String currentUid;
  const MyApp({super.key, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'What Do You Want?!',
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: HomeScreen(currentUid: currentUid),
    );
  }
}

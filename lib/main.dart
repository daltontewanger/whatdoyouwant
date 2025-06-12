import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
      theme: ThemeData(primarySwatch: Colors.orange),
      home: HomeScreen(currentUid: currentUid),
    );
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Sign the user in anonymously so they satisfy request.auth != null
  final cred = await FirebaseAuth.instance.signInAnonymously();
  print(">> anon uid: ${cred.user!.uid}");
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
      theme: ThemeData(
        primarySwatch: Colors.orange,
      ),
      home: HomeScreen(currentUid: currentUid),
    );
  }
}

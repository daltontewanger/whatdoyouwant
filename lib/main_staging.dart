import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options_staging.dart';
import 'environment_guard.dart';

// Foundation smoke check only. The live room UI requires reviewed permissions
// and a staging backend before it can be connected here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = StagingFirebaseOptions.currentPlatform;
  checkFirebaseEnvironment('staging', options.projectId);
  if (options.projectId != 'whatdoyouwant-staging') {
    throw StateError('Staging must never use another Firebase project.');
  }
  await Firebase.initializeApp(options: options);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
  runApp(const MaterialApp(home: StagingCheck()));
}

class StagingCheck extends StatefulWidget {
  const StagingCheck({super.key});

  @override
  State<StagingCheck> createState() => _StagingCheckState();
}

class _StagingCheckState extends State<StagingCheck> {
  String status = 'Ready to check staging. No room data will be written.';
  bool running = false;

  Future<void> check() async {
    setState(() => running = true);
    var result = '';
    try {
      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      try {
        await FirebaseFirestore.instance
            .doc('_connection_check/nonexistent')
            .get(const GetOptions(source: Source.server));
        result = 'FAILED: Firestore unexpectedly allowed a client read.';
      } on FirebaseException catch (error) {
        result =
            error.code == 'permission-denied'
                ? 'PASS: anonymous sign-in works and Firestore denies client reads.'
                : 'Firestore check failed: ${error.code}';
      }
    } on FirebaseException catch (error) {
      result = 'Sign-in failed: ${error.code}';
    } catch (_) {
      result = 'Connection check failed. Check your network and configuration.';
    } finally {
      // Remove only the temporary anonymous account created by this check.
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.isAnonymous) await user.delete();
      } catch (_) {
        result += ' Temporary staging account cleanup failed.';
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

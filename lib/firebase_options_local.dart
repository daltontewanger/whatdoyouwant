import 'package:firebase_core/firebase_core.dart';

// Synthetic identifiers for emulators only; no registered cloud app or secret.
class LocalFirebaseOptions {
  static const android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:android:0123456789abcdef0123456789abcdef',
    messagingSenderId: '123456789',
    projectId: 'demo-whatdoyouwant',
  );

  static const web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:web:localtest',
    messagingSenderId: '123456789',
    projectId: 'demo-whatdoyouwant',
    authDomain: 'demo-whatdoyouwant.firebaseapp.com',
  );
}

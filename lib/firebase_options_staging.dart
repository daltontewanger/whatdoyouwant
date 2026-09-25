import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class StagingFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Staging is configured for web and Android only.');
  }

  static const web = FirebaseOptions(
    apiKey: 'AIzaSyBNeIs_TCMs7wpRkyay_crnNvPoW3HzyJE',
    appId: '1:443362448287:web:140bf23b802081600823aa',
    messagingSenderId: '443362448287',
    projectId: 'whatdoyouwant-staging',
    authDomain: 'whatdoyouwant-staging.firebaseapp.com',
    storageBucket: 'whatdoyouwant-staging.firebasestorage.app',
  );

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyDiC4wtEnnHA7Wy3H7CCHMEQILiOhuWdsQ',
    appId: '1:443362448287:android:a1bcf8295c3cef0c0823aa',
    messagingSenderId: '443362448287',
    projectId: 'whatdoyouwant-staging',
    storageBucket: 'whatdoyouwant-staging.firebasestorage.app',
  );
}

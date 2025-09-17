import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDvjv6mCMP52FuXbM3kafCp0pXa4mvHsNA',
    appId: '1:1086599505073:web:2e866f2b9731d18be02e90',
    messagingSenderId: '1086599505073',
    projectId: 'what-do-you-want-8a404',
    authDomain: 'what-do-you-want-8a404.firebaseapp.com',
    storageBucket: 'what-do-you-want-8a404.firebasestorage.app',
    measurementId: 'G-ST9EVFYE6K',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDoyShjxWSBIWVoP99NtKJQPX1cAe3oImY',
    appId: '1:1086599505073:android:9e373690ee1ffe9fe02e90',
    messagingSenderId: '1086599505073',
    projectId: 'what-do-you-want-8a404',
    storageBucket: 'what-do-you-want-8a404.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAJvObv3tqgzrYTCmJQehOjKKsFqH8hEI8',
    appId: '1:1086599505073:ios:a9ab3646e81ae01de02e90',
    messagingSenderId: '1086599505073',
    projectId: 'what-do-you-want-8a404',
    storageBucket: 'what-do-you-want-8a404.firebasestorage.app',
    iosBundleId: 'com.example.whatdoyouwant',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAZp-5X7Wksp-P2-MNSqvLaNWSuIFi27xc',
    appId: '1:1086599505073:ios:a9ab3646e81ae01de02e90',
    messagingSenderId: '1086599505073',
    projectId: 'what-do-you-want-8a404',
    storageBucket: 'what-do-you-want-8a404.firebasestorage.app',
    iosBundleId: 'com.example.whatdoyouwant',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDvjv6mCMP52FuXbM3kafCp0pXa4mvHsNA',
    appId: '1:1086599505073:web:20dad3287620f7bbe02e90',
    messagingSenderId: '1086599505073',
    projectId: 'what-do-you-want-8a404',
    authDomain: 'what-do-you-want-8a404.firebaseapp.com',
    storageBucket: 'what-do-you-want-8a404.firebasestorage.app',
    measurementId: 'G-CD0DLD3CSJ',
  );
}

// Generated for Electrical Parts Store V2 production Firebase project.
// This file contains client configuration identifiers, not server credentials.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'Android Firebase configuration is not registered yet.',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS Firebase configuration is not registered yet.',
        );
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase configuration is not registered for this platform yet.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBIG_sfRb4S8aEAHHLhFPy0tsh3BHPwyI',
    appId: '1:416563072606:web:bfe4b37f7fa49ca6542ecf',
    messagingSenderId: '416563072606',
    projectId: 'electrical-store-v2-prod',
    authDomain: 'electrical-store-v2-prod.firebaseapp.com',
    storageBucket: 'electrical-store-v2-prod.firebasestorage.app',
  );
}

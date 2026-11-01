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
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase configuration is not registered for this platform yet.',
        );
    }
  }

  // These values must come from the real independent V2 Firebase apps.
  // No V1/mobile identifiers or guessed app IDs are bundled into source.
  // The Android/iOS Flutter platform directories are not yet in this repo.
  static FirebaseOptions get android => FirebaseNativeConfiguration.build(
        platform: 'Android',
        apiKey: const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
        appId: const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
        senderId: const String.fromEnvironment('FIREBASE_ANDROID_SENDER_ID'),
        projectId: const String.fromEnvironment('FIREBASE_ANDROID_PROJECT_ID'),
        storageBucket: const String.fromEnvironment(
          'FIREBASE_ANDROID_STORAGE_BUCKET',
        ),
      );

  static FirebaseOptions get ios => FirebaseNativeConfiguration.build(
        platform: 'iOS',
        apiKey: const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        appId: const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
        senderId: const String.fromEnvironment('FIREBASE_IOS_SENDER_ID'),
        projectId: const String.fromEnvironment('FIREBASE_IOS_PROJECT_ID'),
        storageBucket:
            const String.fromEnvironment('FIREBASE_IOS_STORAGE_BUCKET'),
        iosBundleId: const String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID'),
      );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBIG_sfRb4S8aEAHHLhFPy0tsh3BHPwyI',
    appId: '1:416563072606:web:bfe4b37f7fa49ca6542ecf',
    messagingSenderId: '416563072606',
    projectId: 'electrical-store-v2-prod',
    authDomain: 'electrical-store-v2-prod.firebaseapp.com',
    storageBucket: 'electrical-store-v2-prod.firebasestorage.app',
  );
}

/// Native startup is fail-closed until the V2 app registration data is
/// supplied explicitly. Never reuse Web appId or V1 identifiers.
abstract final class FirebaseNativeConfiguration {
  static FirebaseOptions build({
    required String platform,
    required String apiKey,
    required String appId,
    required String senderId,
    required String projectId,
    required String storageBucket,
    String? iosBundleId,
  }) {
    if (apiKey.trim().isEmpty ||
        appId.trim().isEmpty ||
        senderId.trim().isEmpty ||
        projectId.trim().isEmpty ||
        storageBucket.trim().isEmpty ||
        (platform == 'iOS' && (iosBundleId?.trim().isEmpty ?? true))) {
      throw UnsupportedError(
        '$platform is not configured with its registered V2 Firebase app. '
        'Supply the native Firebase configuration before running.',
      );
    }
    if ((platform == 'Android' && !appId.contains(':android:')) ||
        (platform == 'iOS' && !appId.contains(':ios:')) ||
        !appId.startsWith('1:${senderId.trim()}:')) {
      throw ArgumentError(
        '$platform configuration must use a matching native Firebase app ID.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey.trim(),
      appId: appId.trim(),
      messagingSenderId: senderId.trim(),
      projectId: projectId.trim(),
      storageBucket: storageBucket.trim(),
      iosBundleId: platform == 'iOS' ? iosBundleId!.trim() : null,
    );
  }
}

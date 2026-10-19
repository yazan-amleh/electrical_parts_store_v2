import 'package:firebase_core/firebase_core.dart';

import '../core/config/app_runtime_config.dart';

abstract final class AppBootstrap {
  static Future<void> initialize({
    AppRuntimeConfig? config,
  }) async {
    final runtime = config ?? AppRuntimeConfig.fromEnvironment();
    if (!runtime.useFirebase || Firebase.apps.isNotEmpty) {
      return;
    }

    await Firebase.initializeApp();
  }
}

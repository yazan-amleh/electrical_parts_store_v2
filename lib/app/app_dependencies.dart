import '../core/config/app_runtime_config.dart';
import '../features/auth/application/auth_session_controller.dart';

class AppDependencies {
  const AppDependencies({
    required this.runtime,
    this.authSession,
  });

  final AppRuntimeConfig runtime;
  final AuthSessionController? authSession;

  bool get hasFirebaseSession => authSession != null;
}

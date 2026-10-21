import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/config/app_runtime_config.dart';
import '../../shell/presentation/app_shell_page.dart';
import '../application/auth_session_controller.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    final controller = dependencies.authSession;
    if (controller == null) {
      return FirebaseSetupPage(runtime: dependencies.runtime);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        switch (controller.status) {
          case AuthSessionStatus.signedOut:
          case AuthSessionStatus.signingIn:
            return LoginPage(controller: controller);
          case AuthSessionStatus.loadingMembership:
            return const _LoadingPage(message: 'جارٍ تحميل صلاحيات المتجر...');
          case AuthSessionStatus.ready:
            final user = controller.user;
            final membership = controller.membership;
            if (user == null || membership == null) {
              return const _SessionErrorPage(
                message: 'تعذر بناء جلسة المتجر. حاول مرة أخرى.',
              );
            }
            return AppShellPage(
              dependencies: dependencies,
              user: user,
              membership: membership,
              onSignOut: controller.signOut,
            );
          case AuthSessionStatus.storeNotConfigured:
            return FirebaseSetupPage(runtime: dependencies.runtime);
          case AuthSessionStatus.failure:
            return _SessionErrorPage(
              message: controller.errorMessage ?? 'تعذر تحميل جلسة المتجر.',
              onRetry: controller.reloadMembership,
              onSignOut: controller.signOut,
            );
        }
      },
    );
  }
}

class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({required this.runtime, super.key});

  final AppRuntimeConfig runtime;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.settings_suggest_outlined, size: 56),
                    const SizedBox(height: 16),
                    Text(
                      'التطبيق غير مهيأ بعد',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'أضف إعدادات Firebase الخاصة ببيئة V2 ثم شغّل التطبيق مع '
                      'USE_FIREBASE=true و STORE_ID بمعرّف المتجر.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'البيئة: ${runtime.environment.name}',
                      textAlign: TextAlign.center,
                    ),
                    if (runtime.firebaseProjectId.isNotEmpty)
                      Text(
                        'المشروع: ${runtime.firebaseProjectId}',
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingPage extends StatelessWidget {
  const _LoadingPage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionErrorPage extends StatelessWidget {
  const _SessionErrorPage({
    required this.message,
    this.onRetry,
    this.onSignOut,
  });

  final String message;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'تعذر تحميل جلسة المتجر',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  SelectableText(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  if (onSignOut != null)
                    TextButton(
                      onPressed: onSignOut,
                      child: const Text('تسجيل الخروج'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

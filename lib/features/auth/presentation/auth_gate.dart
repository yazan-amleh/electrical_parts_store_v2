import 'package:flutter/material.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/config/app_runtime_config.dart';
import '../../shell/presentation/app_shell_page.dart';
import '../application/auth_session_controller.dart';
import '../domain/entities/authenticated_user.dart';
import 'login_page.dart';
import 'store_setup_page.dart';

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
              return _SessionErrorPage(
                message: 'تعذر بناء جلسة المتجر. حاول مرة أخرى.',
                storeId: controller.storeId,
                user: user,
                onRetry: controller.reloadMembership,
                onSignOut: controller.signOut,
                onChooseStore: controller.openStoreSetup,
              );
            }
            // Reset all stateful feature screens when tenant or role changes.
            return AppShellPage(
              key: ValueKey('tenant:${user.id}:${membership.storeId}:${membership.role.name}'),
              dependencies: dependencies,
              user: user,
              membership: membership,
              onSignOut: controller.signOut,
              onChooseStore: controller.openStoreSetup,
            );
          case AuthSessionStatus.storeSetupRequired:
            return StoreSetupPage(controller: controller);
          case AuthSessionStatus.creatingStore:
            return const _LoadingPage(message: 'جارٍ إنشاء المتجر...');
          case AuthSessionStatus.storeNotConfigured:
            return FirebaseSetupPage(runtime: dependencies.runtime);
          case AuthSessionStatus.failure:
            return _SessionErrorPage(
              message: controller.errorMessage ?? 'تعذر تحميل جلسة المتجر.',
              storeId: controller.storeId,
              user: controller.user,
              onRetry: controller.reloadMembership,
              onSignOut: controller.signOut,
              onChooseStore: controller.user == null
                  ? null
                  : controller.openStoreSetup,
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
                    if (runtime.storeId.isNotEmpty)
                      Text(
                        'المتجر: ${runtime.storeId}',
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
    this.storeId,
    this.user,
    this.onRetry,
    this.onSignOut,
    this.onChooseStore,
  });

  final String message;
  final String? storeId;
  final AuthenticatedUser? user;
  final Future<void> Function()? onRetry;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onChooseStore;

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
                  if (user != null || (storeId?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (user?.email.isNotEmpty == true)
                      SelectableText(
                        'الحساب: ${user!.email}',
                        textAlign: TextAlign.center,
                      ),
                    if (user?.id.isNotEmpty == true)
                      SelectableText(
                        'Firebase UID: ${user!.id}',
                        textAlign: TextAlign.center,
                      ),
                    if (storeId?.isNotEmpty == true)
                      SelectableText(
                        'Store ID: $storeId',
                        textAlign: TextAlign.center,
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'إذا كان الحساب جديدًا، يجب أن يضيفه مالك المتجر كعضو '
                      'نشط، ثم اضغط «إعادة المحاولة».',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  if (onChooseStore != null)
                    TextButton.icon(
                      onPressed: onChooseStore,
                      icon: const Icon(Icons.storefront_outlined),
                      label: const Text('اختيار متجر آخر'),
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

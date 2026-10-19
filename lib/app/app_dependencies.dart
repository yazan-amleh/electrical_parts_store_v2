import '../core/config/app_runtime_config.dart';
import '../features/accounting/domain/repositories/accounting_query_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/inventory/domain/repositories/product_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.runtime,
    this.authSession,
    this.accountingQueryRepository,
    this.productRepository,
  });

  final AppRuntimeConfig runtime;
  final AuthSessionController? authSession;
  final AccountingQueryRepository? accountingQueryRepository;
  final ProductRepository? productRepository;

  bool get hasFirebaseSession => authSession != null;
}

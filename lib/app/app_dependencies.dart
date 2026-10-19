import '../core/config/app_runtime_config.dart';
import '../features/accounting/domain/repositories/accounting_query_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/domain/repositories/product_repository.dart';
import '../features/sales/domain/repositories/sale_repository.dart';
import '../features/purchases/domain/repositories/purchase_repository.dart';
import '../features/expenses/domain/repositories/expense_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.runtime,
    this.authSession,
    this.accountingQueryRepository,
    this.inventoryRepository,
    this.productRepository,
    this.saleRepository,
    this.purchaseRepository,
    this.expenseRepository,
  });

  final AppRuntimeConfig runtime;
  final AuthSessionController? authSession;
  final AccountingQueryRepository? accountingQueryRepository;
  final InventoryRepository? inventoryRepository;
  final ProductRepository? productRepository;
  final SaleRepository? saleRepository;
  final PurchaseRepository? purchaseRepository;
  final ExpenseRepository? expenseRepository;

  bool get hasFirebaseSession => authSession != null;
}

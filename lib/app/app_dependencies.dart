import '../core/config/app_runtime_config.dart';
import '../features/accounting/domain/repositories/accounting_query_repository.dart';
import '../features/offers/domain/repositories/offer_repository.dart';
import '../features/accounting/domain/repositories/accounting_repository.dart';
import '../features/categories/domain/repositories/category_repository.dart';
import '../features/auth/application/auth_session_controller.dart';
import '../features/inventory/domain/repositories/inventory_repository.dart';
import '../features/inventory/domain/repositories/product_repository.dart';
import '../features/sales/domain/repositories/sale_repository.dart';
import '../features/purchases/domain/repositories/purchase_repository.dart';
import '../features/purchase_orders/domain/repositories/purchase_order_repository.dart';
import '../features/expenses/domain/repositories/expense_repository.dart';
import '../features/payments/domain/repositories/party_payment_repository.dart';
import '../features/parties/domain/repositories/party_repository.dart';
import '../features/transfers/domain/repositories/account_transfer_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.runtime,
    this.authSession,
    this.accountingRepository,
    this.categoryRepository,
    this.accountingQueryRepository,
    this.inventoryRepository,
    this.productRepository,
    this.saleRepository,
    this.purchaseRepository,
    this.purchaseOrderRepository,
    this.offerRepository,
    this.expenseRepository,
    this.partyPaymentRepository,
    this.partyRepository,
    this.accountTransferRepository,
  });

  final AppRuntimeConfig runtime;
  final AuthSessionController? authSession;
  final AccountingRepository? accountingRepository;
  final CategoryRepository? categoryRepository;
  final AccountingQueryRepository? accountingQueryRepository;
  final InventoryRepository? inventoryRepository;
  final ProductRepository? productRepository;
  final SaleRepository? saleRepository;
  final PurchaseRepository? purchaseRepository;
  final PurchaseOrderRepository? purchaseOrderRepository;
  final OfferRepository? offerRepository;
  final ExpenseRepository? expenseRepository;
  final PartyPaymentRepository? partyPaymentRepository;
  final PartyRepository? partyRepository;
  final AccountTransferRepository? accountTransferRepository;

  bool get hasFirebaseSession => authSession != null;
}
